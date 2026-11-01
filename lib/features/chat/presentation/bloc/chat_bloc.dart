import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/chat_repository.dart';
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
    on<ConnectivityChanged>((e, emit) => emit(state.copyWith(isOnline: e.isOnline)));
    on<FeedbackSubmitted>(_onFeedbackSubmitted); // NEW: registered feedback handler
  }

  final ChatRepository _repo; // the rules (interface), not the concrete class
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  static bool _hasNetwork(List<ConnectivityResult> r) =>
      r.any((x) => x != ConnectivityResult.none);

  Future<void> _onStarted(ChatStarted event, Emitter<ChatState> emit) async {
    var history = <ChatTurn>[];
    var online = true;
    try {
      history = await _repo.loadHistory(); // old messages survive restarts
    } catch (_) {}
    try {
      online = _hasNetwork(await _connectivity.checkConnectivity());
    } catch (_) {}
    emit(state.copyWith(messages: history, isOnline: online, isLoading: false));

    await _connectivitySub?.cancel();
    _connectivitySub = _connectivity.onConnectivityChanged
        .listen((r) => add(ConnectivityChanged(_hasNetwork(r))));
  }

  Future<void> _onMessageSent(MessageSent event, Emitter<ChatState> emit) async {
    if (state.isGenerating) return; // one question at a time
    emit(state.copyWith(isGenerating: true));
    try {
      await emit.forEach<ChatTurn>(
        _repo.sendMessage(event.text, isOnline: state.isOnline),
        onData: (turn) => state.copyWith(messages: _upsert(state.messages, turn)),
      );
    } catch (_) {
      // Never leave a bubble "typing" forever.
      final fixed = state.messages
          .map((t) => t.isStreaming
              ? t.copyWith(
                  isStreaming: false,
                  isError: true,
                  aiResponse: 'Something went wrong. Please try again.',
                )
              : t)
          .toList();
      emit(state.copyWith(messages: fixed));
    }
    emit(state.copyWith(isGenerating: false));
  }

  Future<void> _onStopped(GenerationStopped event, Emitter<ChatState> emit) async {
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
      emit(state.copyWith(messages: const [], isGenerating: false, isLoading: false));
    } catch (_) {
      // Storage failed: keep the old chat on screen rather than show a lie.
      emit(state.copyWith(isGenerating: false));
    }
  }

  /// NEW: Handles the feedback submission event by notifying the repository.
  Future<void> _onFeedbackSubmitted(
      FeedbackSubmitted event, Emitter<ChatState> emit) async {
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