import '../local/entities/local_chat_entity.dart';

class ChatContext {
  ChatContext._();

  /// How many earlier turns the on-phone model is allowed to see.
  /// Android trims this again to its own context budget, but keeping the list
  /// short avoids sending a huge prompt to a small model.
  static const int _maxOfflineTurns = 8;

  /// A single very long answer must not fill the whole request.
  static const int _maxCharsPerTurn = 1200;

  /// Earlier turns formatted the way Android's OfflineMamaAiRuntime expects
  /// them: a list of `{role, content}` maps. Android adds the current question
  /// itself, so we only return the turns BEFORE it.
  ///
  /// This is real conversation data only. No instructions or summary text are
  /// generated here; Android's RuntimePolicy decides how much of this history
  /// fits in the model's context.
  static List<Map<String, String>> offlineMessages(
    List<LocalChatMessage> rows,
  ) {
    final turns = _completedTurns(rows);
    final recent = _last(turns, _maxOfflineTurns);
    return [
      for (final turn in recent) ...[
        {'role': 'user', 'content': _clean(turn.message)},
        {'role': 'assistant', 'content': _clean(turn.aiResponse)},
      ],
    ];
  }

  /// Complete user/assistant pairs, oldest first.
  ///
  /// A row is usable only when it has both a question and a finished answer.
  /// Failed, interrupted and still-streaming rows are ignored so the model is
  /// never fed an empty or half-written answer.
  static List<LocalChatMessage> _completedTurns(List<LocalChatMessage> rows) {
    return rows
        .where(
          (row) =>
              row.message.trim().isNotEmpty &&
              row.aiResponse.trim().isNotEmpty &&
              row.syncState != 'inprogress' &&
              row.syncState != 'interrupted',
        )
        .toList(growable: false);
  }

  static List<LocalChatMessage> _last(List<LocalChatMessage> rows, int limit) {
    if (rows.length <= limit) return rows;
    return rows.sublist(rows.length - limit);
  }

  static String _clean(String text) => _clip(text, _maxCharsPerTurn);

  static String _clip(String text, int maxChars) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= maxChars) return clean;
    return '${clean.substring(0, maxChars).trimRight()}…';
  }
}
