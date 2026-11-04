import 'package:equatable/equatable.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();
  @override
  List<Object?> get props => [];
}

class ChatStarted extends ChatEvent {
  const ChatStarted();
}

class MessageSent extends ChatEvent {
  const MessageSent(this.text);
  final String text;
  @override
  List<Object?> get props => [text];
}

/// The person tapped the stop button.
class GenerationStopped extends ChatEvent {
  const GenerationStopped();
}

/// The person tapped "New chat" and confirmed.
class NewChatStarted extends ChatEvent {
  const NewChatStarted();
}

/// The history drawer was opened: make sure the list is up to date.
class ChatHistoryRequested extends ChatEvent {
  const ChatHistoryRequested();
}

/// The person picked an old conversation from the history drawer.
class ChatOpened extends ChatEvent {
  const ChatOpened(this.chatId);
  final String chatId;
  @override
  List<Object?> get props => [chatId];
}

/// The person deleted a conversation from the history drawer.
class ChatDeleted extends ChatEvent {
  const ChatDeleted(this.chatId);
  final String chatId;
  @override
  List<Object?> get props => [chatId];
}

/// Internal: the phone went online/offline.
class ConnectivityChanged extends ChatEvent {
  const ConnectivityChanged(this.isOnline);
  final bool isOnline;
  @override
  List<Object?> get props => [isOnline];
}

/// NEW: The user submitted feedback for an offline answer.
class FeedbackSubmitted extends ChatEvent {
  const FeedbackSubmitted({
    required this.turnId,
    required this.feedbackValue,
    this.comment,
  });

  final String turnId;
  final String feedbackValue; // 'positive' | 'negative' | 'not_helpful'
  final String? comment;

  @override
  List<Object?> get props => [turnId, feedbackValue, comment];
}
