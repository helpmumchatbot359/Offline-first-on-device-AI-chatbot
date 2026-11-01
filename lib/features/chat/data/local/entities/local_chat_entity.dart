import 'package:objectbox/objectbox.dart';

@Entity()
class LocalChat {
  @Id()
  int id = 0;

  @Index()
  @Unique()
  String chatId;

  String createdAt;
  String updatedAt;

  @Backlink('chat')
  final messages = ToMany<LocalChatMessage>();

  LocalChat({
    this.id = 0,
    required this.chatId,
    required this.createdAt,
    required this.updatedAt,
  });
}

@Entity()
class LocalChatMessage {
  @Id()
  int id = 0; // Local-only ID, never sent to backend

  String chatId;
  String message;
  String aiResponse;
  String date; // Original UTC time of the turn
  String syncState; // 'pending' or 'acknowledged'

  /// NEW: who wrote the answer? 'cloud' or 'offline'.
  /// Old rows saved before this field existed read back as '' and count as 'cloud'.
  String source;

  @TargetIdProperty('chatRowId')
  final chat = ToOne<LocalChat>();

  LocalChatMessage({
    this.id = 0,
    required this.chatId,
    required this.message,
    required this.aiResponse,
    required this.date,
    required this.syncState,
    this.source = 'cloud',
  });
}