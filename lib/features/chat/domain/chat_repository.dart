import 'chat_turn.dart';

abstract class ChatRepository {
  /// Everything saved for the chat that is open.
  Future<List<ChatTurn>> loadHistory();

  /// Emits the turn many times: first empty, then growing as words arrive,
  /// finally complete. Lets the screen show the answer being typed.
  Stream<ChatTurn> sendMessage(String text, {required bool isOnline});

  /// Stops the offline model mid-answer.
  Future<void> cancelGeneration();

  /// NEW CHAT: closes the current conversation and opens a blank one.
  /// The old messages stay stored on the phone; they just stop being "open".
  Future<void> startNewChat();

  /// NEW: the person rated an offline answer. Creates an `offline_feedback`
  /// telemetry event. feedbackValue: 'positive' | 'negative' | 'not_helpful'.
  Future<void> submitFeedback({required String feedbackValue, String? comment});
}