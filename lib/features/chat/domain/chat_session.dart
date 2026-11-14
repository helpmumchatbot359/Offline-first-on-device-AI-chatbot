import 'package:equatable/equatable.dart';

class ChatSessionsPage {
  const ChatSessionsPage({
    required this.sessions,
    required this.hasMore,
    required this.nextSkip,
  });

  final List<ChatSession> sessions;
  final bool hasMore;
  final int nextSkip;
}

class ChatMessageHistoryPage {
  const ChatMessageHistoryPage({required this.hasMore, required this.nextSkip});

  const ChatMessageHistoryPage.empty() : hasMore = false, nextSkip = 0;

  final bool hasMore;
  final int nextSkip;
}

/// A saved conversation shown in the history drawer.
///
/// It is only a summary; the full messages are loaded when the person taps it.
class ChatSession extends Equatable {
  const ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messageCount,
    this.isRemote = false,
  });

  /// The same id used by ObjectBox and the backend (`user-...`).
  final String id;

  /// The first question in the chat, shortened to fit on one line.
  final String title;

  /// UTC ISO-8601 of the last message.
  final String updatedAt;

  final int messageCount;

  /// True when this summary came from the account's server history list.
  final bool isRemote;

  @override
  List<Object?> get props => [id, title, updatedAt, messageCount, isRemote];
}
