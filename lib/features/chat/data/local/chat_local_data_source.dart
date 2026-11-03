
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'entities/local_chat_entity.dart';
import 'entities/local_telemetry_entity.dart';
import '../../../../objectbox.g.dart';

class ChatLocalDataSource {
  late final Store _store;
  late final Box<LocalChat> _chatBox;
  late final Box<LocalChatMessage> _messageBox;
  late final Box<LocalTelemetryEvent> _telemetryBox;

  Future<void> init() async {
    final docsDir = await getApplicationDocumentsDirectory();
    _store = await openStore(directory: p.join(docsDir.path, 'mama_ai_db'));
    _chatBox = _store.box<LocalChat>();
    _messageBox = _store.box<LocalChatMessage>();
    _telemetryBox = _store.box<LocalTelemetryEvent>();
  }

  // --- Chat Storage ---

  Future<void> saveMessage({
    required String chatId,
    required String message,
    required String aiResponse,
    required String date,
    required String syncState,
    String source = 'cloud', // NEW: 'cloud' or 'offline'
  }) async {
    var chatQuery = _chatBox.query(LocalChat_.chatId.equals(chatId)).build();
    var chat = chatQuery.findFirst();
    chatQuery.close();

    if (chat == null) {
      chat = LocalChat(
        chatId: chatId,
        createdAt: date,
        updatedAt: date,
      );
      _chatBox.put(chat);
    } else {
      chat.updatedAt = date;
      _chatBox.put(chat);
    }

    final chatMessage = LocalChatMessage(
      chatId: chatId,
      message: message,
      aiResponse: aiResponse,
      date: date,
      syncState: syncState,
      source: source,
    );
    chatMessage.chat.target = chat;
    _messageBox.put(chatMessage);
  }

  // --- Save-as-you-go (so a half-written answer survives the app closing) ---
  //
  // The life of one question:
  //   beginTurn()   -> row is created the moment the person sends the question
  //                    syncState = 'inprogress'  (SyncService ignores it: it only
  //                    uploads rows that are 'pending')
  //   updateTurn()  -> called every second or two while words arrive
  //   finishTurn()  -> answer complete: syncState becomes 'pending' (will upload)
  //   interruptTurn() / recoverInterruptedTurns() -> the app closed in the middle

  static const String stateInProgress = 'inprogress';
  static const String stateInterrupted = 'interrupted'; // nothing to keep or upload

  static const String interruptedNote =
      'This answer was interrupted before it finished. Please ask again.';

  LocalChat _findOrCreateChat(String chatId, String date) {
    final query = _chatBox.query(LocalChat_.chatId.equals(chatId)).build();
    var chat = query.findFirst();
    query.close();
    if (chat == null) {
      chat = LocalChat(chatId: chatId, createdAt: date, updatedAt: date);
    } else {
      chat.updatedAt = date;
    }
    _chatBox.put(chat);
    return chat;
  }

  /// Saves the question IMMEDIATELY (with an empty answer). Returns the row id.
  Future<int> beginTurn({
    required String chatId,
    required String message,
    required String date,
    required String source,
  }) async {
    final chat = _findOrCreateChat(chatId, date);
    final row = LocalChatMessage(
      chatId: chatId,
      message: message,
      aiResponse: '',
      date: date,
      syncState: stateInProgress,
      source: source,
    );
    row.chat.target = chat;
    return _messageBox.put(row);
  }

  /// Saves the words written so far. Row stays 'inprogress'.
  Future<void> updateTurn(int rowId, {required String aiResponse, required String source}) async {
    final row = _messageBox.get(rowId);
    if (row == null) return;
    row.aiResponse = aiResponse;
    row.source = source;
    _messageBox.put(row);
  }

  /// The answer is complete: from now on it is a normal message waiting to upload.
  Future<void> finishTurn(int rowId, {required String aiResponse, required String source}) async {
    final row = _messageBox.get(rowId);
    if (row == null) return;
    row.aiResponse = aiResponse;
    row.source = source;
    row.syncState = 'pending';
    _messageBox.put(row);
  }

  /// The app/screen closed in the middle. Keep the partial answer if there is
  /// one, otherwise leave the question with a short "interrupted" note.
  Future<void> interruptTurn(int rowId, {required String partial, required String source}) async {
    final row = _messageBox.get(rowId);
    if (row == null) return;
    if (partial.trim().isNotEmpty) {
      row.aiResponse = partial;
      row.source = source;
      row.syncState = 'pending';
    } else {
      row.aiResponse = interruptedNote;
      row.syncState = stateInterrupted;
    }
    _messageBox.put(row);
  }

  /// A failed answer is not kept (same rule as before this change).
  Future<void> deleteTurn(int rowId) async {
    _messageBox.remove(rowId);
  }

  /// Call ONCE when the app process starts. Any row still 'inprogress' belongs to
  /// an answer that was cut off when Android closed the app.
  Future<void> recoverInterruptedTurns() async {
    final query = _messageBox.query(LocalChatMessage_.syncState.equals(stateInProgress)).build();
    final rows = query.find();
    query.close();
    for (final row in rows) {
      if (row.aiResponse.trim().isNotEmpty) {
        row.syncState = 'pending'; // keep the partial answer and let it upload
      } else {
        row.aiResponse = interruptedNote;
        row.syncState = stateInterrupted;
      }
    }
    if (rows.isNotEmpty) _messageBox.putMany(rows);
  }

  Future<List<LocalChatMessage>> getMessages(String chatId) async {
    final query = _messageBox.query(LocalChatMessage_.chatId.equals(chatId)).order(LocalChatMessage_.id).build();
    final results = query.find();
    query.close();
    return results;
  }

  Future<List<LocalChatMessage>> getPendingMessages() async {
    final query = _messageBox.query(LocalChatMessage_.syncState.equals('pending')).order(LocalChatMessage_.id).build();
    final results = query.find();
    query.close();
    return results;
  }

  Future<void> markMessagesAcknowledged(List<int> ids) async {
    for (final id in ids) {
      final msg = _messageBox.get(id);
      if (msg != null) {
        msg.syncState = 'acknowledged';
        _messageBox.put(msg);
      }
    }
  }

  Future<int> countPendingMessages() async {
    final query = _messageBox.query(LocalChatMessage_.syncState.equals('pending')).build();
    final n = query.count();
    query.close();
    return n;
  }

  // --- Telemetry Storage ---------------------------------------------------

  Future<void> saveTelemetryEvent(LocalTelemetryEvent event) async {
    _telemetryBox.put(event);
  }

  /// Persists events that were repaired (not newly created). Used by the sync
  /// service to add the device envelope / RAG defaults to rows written by an
  /// older build before uploading them.
  Future<void> saveTelemetryEvents(List<LocalTelemetryEvent> events) async {
    if (events.isEmpty) return;
    _telemetryBox.putMany(events);
  }

  /// Oldest pending events first. Pass [limit] to send in small batches.
  Future<List<LocalTelemetryEvent>> getPendingTelemetryEvents({int? limit}) async {
    final query = _telemetryBox
        .query(LocalTelemetryEvent_.syncState.equals('pending'))
        .order(LocalTelemetryEvent_.id)
        .build();
    final results = query.find();
    query.close();
    return limit == null ? results : results.take(limit).toList();
  }

  Future<int> countPendingTelemetry() async {
    final query = _telemetryBox.query(LocalTelemetryEvent_.syncState.equals('pending')).build();
    final n = query.count();
    query.close();
    return n;
  }

  /// How many events are in a given state ('pending', 'acknowledged',
  /// 'rejected'). Used by the diagnostics audit to show the real queue state.
  Future<int> countTelemetryByState(String syncState) async {
    final query = _telemetryBox.query(LocalTelemetryEvent_.syncState.equals(syncState)).build();
    final n = query.count();
    query.close();
    return n;
  }

  /// Marks ONLY the given event UUIDs as acknowledged. Everything else stays pending.
  Future<void> markTelemetryAcknowledged(List<String> eventUuids) async {
    if (eventUuids.isEmpty) return;
    final query = _telemetryBox.query(LocalTelemetryEvent_.eventUuid.oneOf(eventUuids)).build();
    final events = query.find();
    query.close();

    final now = DateTime.now().toUtc().toIso8601String();
    for (final event in events) {
      event.syncState = 'acknowledged';
      event.acknowledgedAt = now;
    }
    _telemetryBox.putMany(events);
  }

  /// Used only to throw away old events that can never be accepted by the backend.
  Future<void> removeTelemetry(List<int> localIds) async {
    if (localIds.isEmpty) return;
    _telemetryBox.removeMany(localIds);
  }

  /// Quarantines events the server permanently refused (HTTP 400/413/422).
  /// They stop blocking the good events behind them, but stay on the phone for
  /// debugging. A diagnostic record explains why each one was rejected.
  Future<void> markTelemetryRejected(List<int> localIds) async {
    if (localIds.isEmpty) return;
    final events = _telemetryBox.getMany(localIds);
    for (final event in events) {
      if (event == null) continue;
      event.syncState = 'rejected';
    }
    _telemetryBox.putMany(events.whereType<LocalTelemetryEvent>().toList());
  }
}