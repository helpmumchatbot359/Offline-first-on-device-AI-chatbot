import 'dart:async';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

class OfflineAiException implements Exception {
  const OfflineAiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The events Android's OfflineMamaAiRuntime sends back.
enum AiEventType {
  started,
  token,
  retrievalContext,
  toolCallRequested,
  toolResult,
  completed,
  cancelled,
  error,
  unknown,
}

class AiEvent {
  AiEvent(this.type, this.raw);

  factory AiEvent.fromMap(Map<String, dynamic> map) {
    switch (map['event']) {
      case 'started':
        return AiEvent(AiEventType.started, map);
      case 'token':
        return AiEvent(AiEventType.token, map);
      case 'retrieval_context':
        return AiEvent(AiEventType.retrievalContext, map);
      case 'tool_call_requested':
        return AiEvent(AiEventType.toolCallRequested, map);
      case 'tool_result':
        return AiEvent(AiEventType.toolResult, map);
      case 'completed':
        return AiEvent(AiEventType.completed, map);
      case 'cancelled':
        return AiEvent(AiEventType.cancelled, map);
      case 'error':
        return AiEvent(AiEventType.error, map);
      default:
        return AiEvent(AiEventType.unknown, map);
    }
  }

  final AiEventType type;
  final Map<String, dynamic> raw;

  String get text => (raw['text'] as String?) ?? '';
  String get error => (raw['error'] as String?) ?? 'The offline assistant failed.';
  String? get safetyLevel => raw['safety_level'] as String?;

  bool get isTerminal =>
      type == AiEventType.completed ||
      type == AiEventType.cancelled ||
      type == AiEventType.error;
}

/// Dart side of the Android bridge in MainActivity.java.
class NativeOfflineAiService {
  // These names MUST match MainActivity.java exactly.
  static const MethodChannel _method = MethodChannel('mama_ai/offline_ai');
  static const EventChannel _events = EventChannel('mama_ai/offline_ai_events');

  /// Android has ONE event sink, so Dart opens ONE shared stream and each
  /// request just filters it by its own request_id.
  late final Stream<Map<String, dynamic>> _nativeEvents = _events
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));

  Future<void>? _initializing;
  String? _initializedKey;

  /// Loads the 2.5 GB model once. Safe to call before every message.
  Future<void> ensureInitialized({
    required String modelPath,
    required String knowledgePath,
    required String runtimePath,
  }) {
    final key = '$modelPath|$knowledgePath|$runtimePath';
    if (_initializedKey == key) return Future.value();
    return _initializing ??= _initialize(key, modelPath, knowledgePath, runtimePath)
        .whenComplete(() => _initializing = null);
  }

  Future<void> _initialize(
    String key,
    String modelPath,
    String knowledgePath,
    String runtimePath,
  ) async {
    try {
      await _method.invokeMethod<void>('initialize', {
        'model_path': modelPath,
        'knowledge_path': knowledgePath,
        'runtime_path': runtimePath,
      });
      _initializedKey = key;
    } on MissingPluginException {
      throw const OfflineAiException('The offline assistant is only available on Android.');
    } on PlatformException catch (e) {
      _initializedKey = null;
      throw OfflineAiException(e.message ?? 'The offline assistant could not start.');
    }
  }

  /// Starts one answer and streams its events until it finishes.
  Stream<AiEvent> generate({
    required String userId,
    required String sessionId,
    required String chatId,
    required String message,
  }) {
    final requestId = 'req-${const Uuid().v4()}';
    late final StreamController<AiEvent> controller;
    StreamSubscription<Map<String, dynamic>>? subscription;
    Timer? watchdog;

    Future<void> finish() async {
      watchdog?.cancel();
      await subscription?.cancel();
      if (!controller.isClosed) await controller.close();
    }

    void fail(Object error) {
      if (!controller.isClosed) controller.addError(error);
      finish();
    }

    void armWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(const Duration(minutes: 6), () {
        fail(const OfflineAiException('The offline assistant stopped responding.'));
      });
    }

    controller = StreamController<AiEvent>(
      onListen: () async {
        // 1) start listening FIRST so no early event is missed...
        subscription = _nativeEvents
            .where((map) => map['request_id'] == requestId)
            .listen((map) {
          armWatchdog();
          final event = AiEvent.fromMap(map);
          if (!controller.isClosed) controller.add(event);
          if (event.isTerminal) finish();
        }, onError: fail);
        armWatchdog();
        // 2) ...THEN tell Android to start.
        try {
          await _method.invokeMethod<void>('generate', {
            'request_id': requestId,
            'user_id': userId,
            'session_id': sessionId,
            'chat_id': chatId,
            'message': message,
            // 'tool_names': <String>[],                          // don't send the 12 KB tool list
            // 'generation_options': {'max_output_tokens': 300}, // shorter answers finish faster. The trade-off is that offline mode won’t run the five tools (pregnancy dates, reminders, saving records, and so on). It will still answer questions using the local knowledge base.
          });
        } on PlatformException catch (e) {
          fail(OfflineAiException(e.message ?? 'Could not start the answer.'));
        } on MissingPluginException {
          fail(const OfflineAiException('The offline assistant is only available on Android.'));
        }
      },
      onCancel: () async {
        watchdog?.cancel();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> cancelGeneration(String chatId) async {
    try {
      await _method.invokeMethod<void>('cancel', {'chat_id': chatId});
    } on PlatformException {
      // Nothing to cancel is not a problem.
    } on MissingPluginException {
      // Not on Android.
    }
  }
}
