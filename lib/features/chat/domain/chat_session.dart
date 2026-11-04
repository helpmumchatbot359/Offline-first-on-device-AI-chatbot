import 'package:equatable/equatable.dart';

/// A saved conversation shown in the history drawer.
///
/// It is only a summary; the full messages are loaded when the person taps it.
class ChatSession extends Equatable {
  const ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messageCount,
  });

  /// The same id used by ObjectBox and the backend (`user-...`).
  final String id;

  /// The first question in the chat, shortened to fit on one line.
  final String title;

  /// UTC ISO-8601 of the last message.
  final String updatedAt;

  final int messageCount;

  @override
  List<Object?> get props => [id, title, updatedAt, messageCount];
}
