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
    this.hasMoreSessions = false,
    this.isLoadingMoreSessions = false,
    this.nextSessionSkip = 0,
    this.hasMoreMessages = false,
    this.isLoadingMoreMessages = false,
    this.nextMessageSkip = 0,
    this.notice,
  });

  final List<ChatTurn> messages;

  /// Saved conversations shown in the history drawer (newest first).
  final List<ChatSession> sessions;

  /// Which conversation is open right now.
  final String? activeChatId;

  final bool isGenerating;
  final bool isOnline;
  final bool isLoading; // reading saved history
  final bool hasMoreSessions;
  final bool isLoadingMoreSessions;
  final int nextSessionSkip;
  final bool hasMoreMessages;
  final bool isLoadingMoreMessages;
  final int nextMessageSkip;

  /// A one-time message for an action such as a failed remote chat deletion.
  final String? notice;

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
    bool? hasMoreSessions,
    bool? isLoadingMoreSessions,
    int? nextSessionSkip,
    bool? hasMoreMessages,
    bool? isLoadingMoreMessages,
    int? nextMessageSkip,
    String? notice,
    bool clearNotice = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      sessions: sessions ?? this.sessions,
      activeChatId: activeChatId ?? this.activeChatId,
      isGenerating: isGenerating ?? this.isGenerating,
      isOnline: isOnline ?? this.isOnline,
      isLoading: isLoading ?? this.isLoading,
      hasMoreSessions: hasMoreSessions ?? this.hasMoreSessions,
      isLoadingMoreSessions:
          isLoadingMoreSessions ?? this.isLoadingMoreSessions,
      nextSessionSkip: nextSessionSkip ?? this.nextSessionSkip,
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
      isLoadingMoreMessages:
          isLoadingMoreMessages ?? this.isLoadingMoreMessages,
      nextMessageSkip: nextMessageSkip ?? this.nextMessageSkip,
      notice: clearNotice ? null : (notice ?? this.notice),
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
    hasMoreSessions,
    isLoadingMoreSessions,
    nextSessionSkip,
    hasMoreMessages,
    isLoadingMoreMessages,
    nextMessageSkip,
    notice,
  ];
}
