import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mama_ai/features/chat/data/ai/native_offline_ai_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('mama_ai/offline_ai');
  const eventChannel = EventChannel('mama_ai/offline_ai_events');

  test('generate sends the conversation history to Android', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (arguments, sink) {}),
    );

    final service = NativeOfflineAiService();
    final subscription = service
        .generate(
          userId: 'user-1',
          sessionId: 'chat-1',
          chatId: 'chat-1',
          message: 'follow up',
          history: const [
            {'role': 'user', 'content': 'first question'},
            {'role': 'assistant', 'content': 'first answer'},
          ],
        )
        .listen((_) {});

    await pumpEventQueue();

    expect(calls, hasLength(1));
    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(arguments['message'], 'follow up');
    expect(arguments.containsKey('system_message'), isFalse);
    expect(arguments['messages'], [
      {'role': 'user', 'content': 'first question'},
      {'role': 'assistant', 'content': 'first answer'},
      {'role': 'user', 'content': 'follow up'},
    ]);

    await subscription.cancel();
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });
}
