import 'package:objectbox/objectbox.dart';

@Entity()
class LocalTelemetryEvent {
  @Id()
  int id = 0;

  @Index()
  String eventUuid; // Generated on phone, reused for retries

  String eventType;
  String? chatId;
  String date;
  String? modelVersion;
  int? latencyMs;
  String? outcome; // success, error, cancelled
  String? errorCode;
  String connectivity;
  String metadataJson;
  String syncState; // 'pending' or 'acknowledged'
  String? acknowledgedAt;

  LocalTelemetryEvent({
    this.id = 0,
    required this.eventUuid,
    required this.eventType,
    this.chatId,
    required this.date,
    this.modelVersion,
    this.latencyMs,
    this.outcome,
    this.errorCode,
    required this.connectivity,
    required this.metadataJson,
    required this.syncState,
    this.acknowledgedAt,
  });
}