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
    on<ChatOpened>(_onChatOpened);
    on<ChatDeleted>(_onChatDeleted);
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
    String? activeChatId;
    var online = true;
    try {
      history = await _repo.loadHistory(); // old messages survive restarts
    } catch (_) {}
    try {
      activeChatId = await _repo.activeChatId();
      sessions = await _repo.loadChatSessions();
    } catch (_) {}
    try {
      online = _hasNetwork(await _connectivity.checkConnectivity());
    } catch (_) {}
    emit(
      state.copyWith(
        messages: history,
        sessions: sessions,
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
      final sessions = await _repo.loadChatSessions();
      final activeChatId = await _repo.activeChatId();
      emit(state.copyWith(sessions: sessions, activeChatId: activeChatId));
    } catch (_) {
      // Keep the list that is already on screen.
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
      final sessions = await _repo.loadChatSessions();
      emit(
        state.copyWith(
          messages: const [],
          sessions: sessions,
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
    if (event.chatId == state.activeChatId) return;

    // Borrow the "busy" flag so no message can be sent while the old chat
    // is being swapped for the selected one.
    emit(state.copyWith(isGenerating: true));
    try {
      await _repo.openChat(event.chatId);
      final history = await _repo.loadHistory();
      final sessions = await _repo.loadChatSessions();
      emit(
        state.copyWith(
          messages: history,
          sessions: sessions,
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
      final sessions = await _repo.loadChatSessions();
      final activeChatId = await _repo.activeChatId();
      emit(
        state.copyWith(
          messages: history,
          sessions: sessions,
          activeChatId: activeChatId,
          isGenerating: false,
          isLoading: false,
        ),
      );
    } catch (_) {
      emit(state.copyWith(isGenerating: false));
    }
  }

  Future<void> _onChatRenamed(
    ChatRenamed event,
    Emitter<ChatState> emit,
  ) async {
    try {
      await _repo.renameChat(event.chatId, event.title);
      final sessions = await _repo.loadChatSessions();
      emit(state.copyWith(sessions: sessions));
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
      final sessions = await _repo.loadChatSessions();
      emit(
        state.copyWith(
          messages: history,
          sessions: sessions,
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

  @override
  Future<void> close() async {
    await _connectivitySub?.cancel();
    return super.close();
  }
}
