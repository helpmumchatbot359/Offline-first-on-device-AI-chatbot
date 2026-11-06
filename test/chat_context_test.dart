import 'package:flutter_test/flutter_test.dart';
import 'package:mama_ai/features/chat/data/ai/chat_context.dart';
import 'package:mama_ai/features/chat/data/local/entities/local_chat_entity.dart';

LocalChatMessage _turn(
  String question,
  String answer, {
  String source = 'cloud',
  String syncState = 'acknowledged',
}) {
  return LocalChatMessage(
    chatId: 'chat-1',
    message: question,
    aiResponse: answer,
    date: '2026-01-01T00:00:00Z',
    syncState: syncState,
    source: source,
  );
}

void main() {
  group('ChatContext.offlineMessages', () {
    test('sends earlier turns oldest-first and skips unfinished rows', () {
      final rows = [
        _turn('first question', 'first answer', source: 'cloud'),
        _turn('failed question', '', source: 'offline'),
        _turn('second question', 'second answer', source: 'offline'),
        _turn(
          'interrupted',
          'partial',
          source: 'offline',
          syncState: 'inprogress',
        ),
      ];

      final messages = ChatContext.offlineMessages(rows);

      expect(messages, [
        {'role': 'user', 'content': 'first question'},
        {'role': 'assistant', 'content': 'first answer'},
        {'role': 'user', 'content': 'second question'},
        {'role': 'assistant', 'content': 'second answer'},
      ]);
    });

    test('includes both cloud and offline turns', () {
      final rows = [
        _turn('online question', 'online answer', source: 'cloud'),
        _turn('offline question', 'offline answer', source: 'offline'),
      ];

      final messages = ChatContext.offlineMessages(rows);

      expect(messages.length, 4);
      expect(messages[0]['content'], 'online question');
      expect(messages[3]['content'], 'offline answer');
    });
  });

  group('ChatContext.offlineMessages bounds', () {
    test('keeps only the most recent turns after a long conversation', () {
      final rows = [
        for (var i = 0; i < 20; i++)
          _turn('question number $i', 'answer $i', source: 'offline'),
      ];

      final messages = ChatContext.offlineMessages(rows);

      expect(messages.length, 16); // 8 turns
      expect(messages.first['content'], 'question number 12');
      expect(messages.last['content'], 'answer 19');
    });

    test('clips a very long answer so the small model still has room', () {
      final rows = [_turn('question', 'x' * 2000, source: 'offline')];

      final messages = ChatContext.offlineMessages(rows);

      expect(messages[1]['content'], contains('…'));
      expect(messages[1]['content']!.length, lessThan(1300));
    });
  });
}
