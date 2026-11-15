/// The server's history endpoint may prefix client generated chat IDs with
/// `8-`. Treat `8-user-<uuid>` and `user-<uuid>` as the same conversation.
String chatHistoryIdentity(String chatId) =>
    chatId.startsWith('8-user-') ? chatId.substring(2) : chatId;

bool sameChatHistory(String left, String right) =>
    chatHistoryIdentity(left) == chatHistoryIdentity(right);

/// Both forms are useful for operations that must cover the local and server
/// representations of one chat.
List<String> chatHistoryIdAliases(String chatId) {
  final identity = chatHistoryIdentity(chatId);
  return identity.startsWith('user-')
      ? <String>{chatId, identity, '8-$identity'}.toList()
      : <String>{chatId, identity}.toList();
}
