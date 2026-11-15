/// The server's history endpoint may prefix client generated chat IDs with a
/// numeric value. Treat `<number>-user-<uuid>` and `user-<uuid>` as one chat.
String chatHistoryIdentity(String chatId) {
  final match = RegExp(
    r'^\d+-(user-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$',
  ).firstMatch(chatId);
  return match?.group(1) ?? chatId;
}

bool sameChatHistory(String left, String right) =>
    chatHistoryIdentity(left) == chatHistoryIdentity(right);

/// Both forms are useful for operations that must cover the local and server
/// representations of one chat.
List<String> chatHistoryIdAliases(String chatId) {
  final identity = chatHistoryIdentity(chatId);
  final aliases = <String>{chatId, identity};
  if (chatId == identity && identity.startsWith('user-')) {
    aliases.add('8-$identity');
  }
  return aliases.toList();
}
