import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/chat_repository.dart';
import '../../domain/chat_session.dart';
import '../../domain/chat_turn.dart';
import '../events/chat_event.dart';
import '../states/chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this._repo, {Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity(),
      super(const ChatState()) {
    on<ChatStarted>(_onStarted);
    on<MessageSent>(_onMessageSent);
    on<GenerationStopped>(_onStopped);
    on<NewChatStarted>(_onNewChat);
    on<ChatHistoryRequested>(_onChatHistoryRequested);
    on<ChatHistoryMoreRequested>(_onChatHistoryMoreRequested);
    on<ChatMessagesMoreRequested>(_onChatMessagesMoreRequested);
    on<ChatOpened>(_onChatOpened);
    on<ChatDeleted>(_onChatDeleted);
    on<ChatNoticeCleared>((event, emit) {
      emit(state.copyWith(clearNotice: true));
    });
    on<ChatRenamed>(_onChatRenamed);
    on<ChatBranched>(_onChatBranched);
    on<ConnectivityChanged>(
      (e, emit) => emit(state.copyWith(isOnline: e.isOnline)),
    );
    on<FeedbackSubmitted>(
      _onFeedbackSubmitted,
    ); // NEW: registered feedback handler
  }

  final ChatRepository _repo; // the rules (interface), not the concrete class
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  static bool _hasNetwork(List<ConnectivityResult> r) =>
      r.any((x) => x != ConnectivityResult.none);

  Future<void> _onStarted(ChatStarted event, Emitter<ChatState> emit) async {
    var history = <ChatTurn>[];
    var sessions = <ChatSession>[];
    var hasMoreSessions = false;
    var nextSessionSkip = 0;
    String? activeChatId;
    var online = true;
    try {
      history = await _repo.loadHistory(); // old messages survive restarts
    } catch (_) {}
    try {
      activeChatId = await _repo.activeChatId();
      final page = await _repo.loadChatSessions(includeRemote: false);
      sessions = page.sessions;
      hasMoreSessions = page.hasMore;
      nextSessionSkip = page.nextSkip;
    } catch (_) {}
    try {
      online = _hasNetwork(await _connectivity.checkConnectivity());
    } catch (_) {}
    emit(
      state.copyWith(
        messages: history,
        sessions: sessions,
        hasMoreSessions: hasMoreSessions,
        nextSessionSkip: nextSessionSkip,
        activeChatId: activeChatId,
        isOnline: online,
        isLoading: false,
      ),
    );

    await _connectivitySub?.cancel();
    _connectivitySub = _connectivity.onConnectivityChanged.listen(
      (r) => add(ConnectivityChanged(_hasNetwork(r))),
    );
  }

  Future<void> _onMessageSent(
    MessageSent event,
    Emitter<ChatState> emit,
  ) async {
    if (state.isGenerating) return; // one question at a time
    emit(state.copyWith(isGenerating: true));
    try {
      await emit.forEach<ChatTurn>(
        _repo.sendMessage(event.text, isOnline: state.isOnline),
        onData: (turn) =>
            state.copyWith(messages: _upsert(state.messages, turn)),
      );
    } catch (_) {
      // Never leave a bubble "typing" forever.
      final fixed = state.messages
          .map(
            (t) => t.isStreaming
                ? t.copyWith(
                    isStreaming: false,
                    isError: true,
                    aiResponse: 'Something went wrong. Please try again.',
                  )
                : t,
          )
          .toList();
      emit(state.copyWith(messages: fixed));
    }
    emit(state.copyWith(isGenerating: false));
  }

  /// Runs whenever the drawer opens, so a brand-new chat that has just saved
  /// its first message appears in the list immediately.
  Future<void> _onChatHistoryRequested(
    ChatHistoryRequested event,
    Emitter<ChatState> emit,
  ) async {
    if (state.isLoading) return;
    try {
      final page = await _repo.loadChatSessions();
      final activeChatId = await _repo.activeChatId();
      emit(
        state.copyWith(
          sessions: page.sessions,
          activeChatId: activeChatId,
          hasMoreSessions: page.hasMore,
          nextSessionSkip: page.nextSkip,
        ),
      );
    } catch (_) {
      // Keep the list that is already on screen.
    }
  }

  Future<void> _onChatHistoryMoreRequested(
    ChatHistoryMoreRequested event,
    Emitter<ChatState> emit,
  ) async {
    if (!state.hasMoreSessions || state.isLoadingMoreSessions) return;
    emit(state.copyWith(isLoadingMoreSessions: true));
    try {
      final page = await _repo.loadChatSessions(skip: state.nextSessionSkip);
      emit(
        state.copyWith(
          sessions: _mergeSessions(state.sessions, page.sessions),
          hasMoreSessions: page.hasMore,
          nextSessionSkip: page.nextSkip,
          isLoadingMoreSessions: false,
        ),
      );
    } catch (_) {
      emit(state.copyWith(isLoadingMoreSessions: false));
    }
  }

  Future<void> _onChatMessagesMoreRequested(
    ChatMessagesMoreRequested event,
    Emitter<ChatState> emit,
  ) async {
    final chatId = state.activeChatId;
    if (chatId == null ||
        !state.hasMoreMessages ||
        state.isLoadingMoreMessages ||
        state.isGenerating) {
      return;
    }

    emit(state.copyWith(isLoadingMoreMessages: true));
    try {
      final page = await _repo.loadOlderMessages(
        chatId,
        skip: state.nextMessageSkip,
      );
      final history = await _repo.loadHistory();
      emit(
        state.copyWith(
          messages: history,
          hasMoreMessages: page.hasMore,
          nextMessageSkip: page.nextSkip,
          isLoadingMoreMessages: false,
        ),
      );
    } catch (_) {
      emit(state.copyWith(isLoadingMoreMessages: false));
    }
  }

  Future<void> _onStopped(
    GenerationStopped event,
    Emitter<ChatState> emit,
  ) async {
    await _repo.cancelGeneration();
  }

  /// NEW CHAT.
  /// 1) Refuse while an answer is being written (otherwise the unfinished
  ///    answer would land inside the NEW chat).
  /// 2) Refuse if the screen is already blank (nothing to start over from).
  /// 3) Ask the repository for a fresh chat id. Only if that worked, clear the screen.
  Future<void> _onNewChat(NewChatStarted event, Emitter<ChatState> emit) async {
    if (state.isGenerating || state.messages.isEmpty) return;

    // Borrow the "busy" flag so nobody can send a message in the split second
    // while the new chat is being created.
    emit(state.copyWith(isGenerating: true));
    try {
      await _repo.startNewChat();
      final activeChatId = await _repo.activeChatId();
      final page = await _repo.loadChatSessions();
      emit(
        state.copyWith(
          messages: const [],
          sessions: page.sessions,
          hasMoreSessions: page.hasMore,
          nextSessionSkip: page.nextSkip,
          hasMoreMessages: false,
          isLoadingMoreMessages: false,
          nextMessageSkip: 0,
          activeChatId: activeChatId,
          isGenerating: false,
          isLoading: false,
        ),
      );
    } catch (_) {
      // Storage failed: keep the old chat on screen rather than show a lie.
      emit(state.copyWith(isGenerating: false));
    }
  }

  /// The person tapped a saved conversation in the history drawer.
  Future<void> _onChatOpened(ChatOpened event, Emitter<ChatState> emit) async {
    if (state.isGenerating || state.isLoading) return;
    if (event.chatId == state.activeChatId && !event.restoreRemote) return;

    // Borrow the "busy" flag so no message can be sent while the old chat
    // is being swapped for the selected one.
    emit(state.copyWith(isGenerating: true));
    try {
      final messagePage = await _repo.openChat(
        event.chatId,
        restoreRemote: event.restoreRemote,
      );
      final history = await _repo.loadHistory();
      final page = await _repo.loadChatSessions();
      emit(
        state.copyWith(
          messages: history,
          sessions: page.sessions,
          hasMoreSessions: page.hasMore,
          nextSessionSkip: page.nextSkip,
          hasMoreMessages: messagePage.hasMore,
          isLoadingMoreMessages: false,
          nextMessageSkip: messagePage.nextSkip,
          activeChatId: event.chatId,
          isGenerating: false,
          isLoading: false,
        ),
      );
    } catch (_) {
      emit(state.copyWith(isGenerating: false));
    }
  }

  /// The person deleted a conversation from the history drawer.
  Future<void> _onChatDeleted(
    ChatDeleted event,
    Emitter<ChatState> emit,
  ) async {
    if (state.isGenerating || state.isLoading) return;

    emit(state.copyWith(isGenerating: true));
    try {
      await _repo.deleteChat(event.chatId);
      // If the deleted chat was open, the repository already moved us to a
      // fresh chat. Loading history now gives the correct new state.
      final history = await _repo.loadHistory();
      final page = await _repo.loadChatSessions();
      final activeChatId = await _repo.activeChatId();
      emit(
        state.copyWith(
          messages: history,
          sessions: page.sessions,
          hasMoreSessions: page.hasMore,
          nextSessionSkip: page.nextSkip,
          hasMoreMessages: false,
          isLoadingMoreMessages: false,
          nextMessageSkip: 0,
          activeChatId: activeChatId,
          isGenerating: false,
          isLoading: false,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isGenerating: false,
          notice: 'Could not delete this chat. Check your connection and try again.',
        ),
      );
    }
  }

  Future<void> _onChatRenamed(
    ChatRenamed event,
    Emitter<ChatState> emit,
  ) async {
    try {
      await _repo.renameChat(event.chatId, event.title);
      final page = await _repo.loadChatSessions();
      emit(
        state.copyWith(
          sessions: page.sessions,
          hasMoreSessions: page.hasMore,
          nextSessionSkip: page.nextSkip,
        ),
      );
    } catch (_) {
      // Keep the old name if the phone could not save the new one.
    }
  }

  Future<void> _onChatBranched(
    ChatBranched event,
    Emitter<ChatState> emit,
  ) async {
    if (state.isGenerating || state.isLoading || state.messages.isEmpty) return;

    // Copying can take a moment. The busy flag also stops a message from
    // landing in the old chat while the new one is being prepared.
    emit(state.copyWith(isGenerating: true));
    try {
      String? currentTitle;
      for (final session in state.sessions) {
        if (session.id == state.activeChatId) currentTitle = session.title;
      }

      final newChatId = await _repo.branchChat();
      if (currentTitle != null && currentTitle.trim().isNotEmpty) {
        await _repo.renameChat(newChatId, '$currentTitle (branch)');
      }

      final history = await _repo.loadHistory();
      final page = await _repo.loadChatSessions();
      emit(
        state.copyWith(
          messages: history,
          sessions: page.sessions,
          hasMoreSessions: page.hasMore,
          nextSessionSkip: page.nextSkip,
          hasMoreMessages: false,
          isLoadingMoreMessages: false,
          nextMessageSkip: 0,
          activeChatId: newChatId,
          isGenerating: false,
          isLoading: false,
        ),
      );
    } catch (_) {
      emit(state.copyWith(isGenerating: false));
    }
  }

  /// NEW: Handles the feedback submission event by notifying the repository.
  Future<void> _onFeedbackSubmitted(
    FeedbackSubmitted event,
    Emitter<ChatState> emit,
  ) async {
    try {
      await _repo.submitFeedback(
        feedbackValue: event.feedbackValue,
        comment: event.comment,
      );
    } catch (_) {
      // Feedback collection should fail silently to preserve user experience.
    }
  }

  static List<ChatTurn> _upsert(List<ChatTurn> list, ChatTurn turn) {
    final i = list.indexWhere((t) => t.id == turn.id);
    if (i == -1) return [...list, turn];
    final copy = List<ChatTurn>.of(list);
    copy[i] = turn;
    return copy;
  }

  static List<ChatSession> _mergeSessions(
    List<ChatSession> existing,
    List<ChatSession> incoming,
  ) {
    final byId = <String, ChatSession>{
      for (final session in existing) session.id: session,
    };
    for (final session in incoming) {
      byId[session.id] = session;
    }
    return byId.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<void> close() async {
    await _connectivitySub?.cancel();
    return super.close();
  }
}
