import 'package:equatable/equatable.dart';

/// One question and its answer. Replaces the loose `Map<String, dynamic>`
/// so typos like record['mesage'] become compile errors, not blank bubbles.
class ChatTurn extends Equatable {
  const ChatTurn({
    required this.id,
    required this.message,
    required this.aiResponse,
    required this.date,
    required this.state,
    this.isStreaming = false,
    this.isError = false,
    this.synced = false,
  });

  /// Reads the ObjectBox record format:
  /// {message, ai_response, date, state} (+ id, synced).
  factory ChatTurn.fromJson(Map<String, dynamic> json) => ChatTurn(
        id: (json['id'] ?? json['date'] ?? '').toString(),
        message: (json['message'] ?? '').toString(),
        aiResponse: (json['ai_response'] ?? '').toString(),
        date: (json['date'] ?? '').toString(),
        state: (json['state'] ?? 'online').toString(),
        synced: json['synced'] == true,
      );

  final String id;
  final String message;
  final String aiResponse;
  final String date; // UTC ISO-8601
  final String state; // 'online' | 'offline'
  final bool isStreaming; // answer is still being written (never saved)
  final bool isError; // show as a problem, never saved
  final bool synced; // offline message already pushed to the cloud

  bool get isOffline => state == 'offline';

  Map<String, dynamic> toJson() => {
        'id': id,
        'message': message,
        'ai_response': aiResponse,
        'date': date,
        'state': state,
        'synced': synced,
      };

  ChatTurn copyWith({
    String? aiResponse,
    String? state,
    bool? isStreaming,
    bool? isError,
    bool? synced,
  }) =>
      ChatTurn(
        id: id,
        message: message,
        aiResponse: aiResponse ?? this.aiResponse,
        date: date,
        state: state ?? this.state,
        isStreaming: isStreaming ?? this.isStreaming,
        isError: isError ?? this.isError,
        synced: synced ?? this.synced,
      );

  @override
  List<Object?> get props =>
      [id, message, aiResponse, date, state, isStreaming, isError, synced];
}
