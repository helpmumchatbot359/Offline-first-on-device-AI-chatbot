import 'package:flutter_test/flutter_test.dart';
import 'package:mama_ai/features/auth/domain/user_profile.dart';
import 'package:mama_ai/features/chat/domain/chat_turn.dart';
import 'package:mama_ai/features/chat/presentation/utils/conversation_actions.dart';

ChatTurn _turn({required String message, required String answer}) => ChatTurn(
  id: message,
  message: message,
  aiResponse: answer,
  date: '2026-07-20T10:00:00Z',
  state: 'online',
);

void main() {
  group('ConversationActions.transcript', () {
    test('labels both sides of every turn and separates turns', () {
      final turns = [
        _turn(message: ' Is my baby due soon? ', answer: ' Tell me your date '),
        _turn(message: 'Thanks', answer: 'You are welcome'),
      ];

      expect(
        ConversationActions.transcript(turns),
        'You: Is my baby due soon?\n'
        'MamaBot: Tell me your date\n'
        '\n'
        'You: Thanks\n'
        'MamaBot: You are welcome',
      );
    });

    test('skips empty halves instead of writing blank labels', () {
      final turns = [
        _turn(message: 'Hello', answer: ''),
        _turn(message: '', answer: 'A late answer'),
      ];

      expect(
        ConversationActions.transcript(turns),
        'You: Hello\n'
        '\n'
        'MamaBot: A late answer',
      );
    });

    test('returns an empty string when there is nothing to share', () {
      expect(ConversationActions.transcript(const []), '');
    });
  });

  group('ConversationActions.subject', () {
    test('includes the conversation date', () {
      expect(
        ConversationActions.subject(at: DateTime(2026, 7, 5)),
        'My MamaBot conversation (2026-07-05)',
      );
    });
  });

  group('UserProfile', () {
    test('prefers the name for the initial and first name', () {
      const profile = UserProfile(
        name: 'Ada Lovelace',
        email: 'ada@example.com',
      );

      expect(profile.initial, 'A');
      expect(profile.firstName, 'Ada');
    });

    test('falls back to the email when the name is blank', () {
      const profile = UserProfile(name: '  ', email: 'grace@example.com');

      expect(profile.initial, 'G');
      expect(profile.firstName, 'grace@example.com');
    });
  });
}
