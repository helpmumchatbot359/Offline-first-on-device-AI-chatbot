import 'package:equatable/equatable.dart';

import '../../domain/chat_session.dart';
import '../../domain/chat_turn.dart';

class ChatState extends Equatable {
  const ChatState({
    this.messages = const [],
    this.sessions = const [],
    this.activeChatId,
    this.isGenerating = false,
    this.isOnline = true,
    this.isLoading = true,
  });

  final List<ChatTurn> messages;

  /// Saved conversations shown in the history drawer (newest first).
  final List<ChatSession> sessions;

  /// Which conversation is open right now.
  final String? activeChatId;

  final bool isGenerating;
  final bool isOnline;
  final bool isLoading; // reading saved history

  /// Stop only makes sense while the on-phone model is writing.
  bool get canStop =>
      isGenerating && messages.isNotEmpty && messages.last.isOffline;

  ChatState copyWith({
    List<ChatTurn>? messages,
    List<ChatSession>? sessions,
    String? activeChatId,
    bool? isGenerating,
    bool? isOnline,
    bool? isLoading,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      sessions: sessions ?? this.sessions,
      activeChatId: activeChatId ?? this.activeChatId,
      isGenerating: isGenerating ?? this.isGenerating,
      isOnline: isOnline ?? this.isOnline,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [
    messages,
    sessions,
    activeChatId,
    isGenerating,
    isOnline,
    isLoading,
  ];
}
