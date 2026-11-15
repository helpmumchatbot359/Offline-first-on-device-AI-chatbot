import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';

/// The paginated response returned by GET /v1/chats.
class RemoteChatPage {
  const RemoteChatPage({
    required this.chats,
    required this.hasMore,
    required this.nextSkip,
  });

  final List<RemoteChatSummary> chats;
  final bool hasMore;
  final int nextSkip;
}

class RemoteChatSummary {
  const RemoteChatSummary({
    required this.id,
    required this.lastMessageAt,
    required this.messageCount,
    this.title,
  });

  final String id;
  final String lastMessageAt;
  final int messageCount;
  final String? title;
}

class RemoteChatMessage {
  const RemoteChatMessage({
    required this.message,
    required this.aiResponse,
    required this.date,
  });

  final String message;
  final String aiResponse;
  final String date;
}

class RemoteChatMessagesPage {
  const RemoteChatMessagesPage({
    required this.messages,
    required this.hasMore,
    required this.nextSkip,
  });

  final List<RemoteChatMessage> messages;
  final bool hasMore;
  final int nextSkip;
}

/// Network calls for the signed-in user's chat history.
///
/// Keeping HTTP and response parsing here leaves ChatRepositoryImpl to
/// coordinate remote history with the existing local/offline database.
class RemoteChatDataSource {
  RemoteChatDataSource(ApiClient apiClient) : _dio = apiClient.dio;

  final Dio _dio;

  Future<RemoteChatPage> listChats({required int skip, int take = 20}) async {
    final response = await _dio.get<dynamic>(
      '/v1/chats',
      queryParameters: {'skip': skip, 'take': take},
    );
    final data = response.data;
    if (data is! Map) {
      throw const FormatException('Invalid chat-list response.');
    }

    final rawChats = data['chats'];
    if (rawChats is! List) {
      throw const FormatException('Invalid chat-list response.');
    }

    final chats = <RemoteChatSummary>[];
    for (final raw in rawChats) {
      if (raw is! Map) continue;
      final id = raw['chat_id']?.toString();
      if (id == null || id.isEmpty) continue;

      final rawCount = raw['message_count'];
      final rawTitle =
          raw['title'] ??
          raw['first_message'] ??
          raw['first_question'] ??
          raw['preview'] ??
          raw['last_message'];
      chats.add(
        RemoteChatSummary(
          id: id,
          lastMessageAt: raw['last_message_at']?.toString() ?? '',
          messageCount: rawCount is num
              ? rawCount.toInt()
              : int.tryParse(rawCount?.toString() ?? '') ?? 0,
          title: rawTitle is String && rawTitle.trim().isNotEmpty
              ? rawTitle.trim()
              : null,
        ),
      );
    }

    final rawSkip = data['next_skip'];
    final nextSkip = rawSkip is num
        ? rawSkip.toInt()
        : int.tryParse(rawSkip?.toString() ?? '') ?? skip + rawChats.length;
    final hasMore = data['has_more'] == true;
    if (hasMore && nextSkip <= skip) {
      throw const FormatException('Invalid chat-list pagination cursor.');
    }

    return RemoteChatPage(
      chats: chats,
      hasMore: hasMore && rawChats.isNotEmpty,
      nextSkip: nextSkip,
    );
  }

  Future<void> deleteChat(String chatId) async {
    await _dio.delete<dynamic>('/v1/chats/${Uri.encodeComponent(chatId)}');
  }

  /// Reads one page. The server returns newest messages first; local history is
  /// sorted chronologically before the existing chat UI displays it.
  Future<RemoteChatMessagesPage> getMessages(
    String chatId, {
    required int skip,
    int take = 50,
  }) async {
    final response = await _dio.get<dynamic>(
      '/v1/chats/${Uri.encodeComponent(chatId)}',
      queryParameters: {'skip': skip, 'take': take},
    );
    final data = response.data;
    if (data is! Map || data['messages'] is! List) {
      throw const FormatException('Invalid chat-messages response.');
    }

    final rawMessages = data['messages'] as List;
    final messages = <RemoteChatMessage>[];
    for (final raw in rawMessages) {
      if (raw is! Map) continue;
      // The current chat sync endpoint uploads these same three fields.
      final question = raw['message'] ?? raw['user_message'] ?? raw['question'];
      final answer =
          raw['ai_response'] ?? raw['assistant_response'] ?? raw['answer'];
      final date = raw['date'] ?? raw['created_at'] ?? raw['timestamp'];
      if (question == null || date == null) continue;
      messages.add(
        RemoteChatMessage(
          message: question.toString(),
          aiResponse: answer?.toString() ?? '',
          date: date.toString(),
        ),
      );
    }

    final rawSkip = data['next_skip'];
    final nextSkip = rawSkip is num
        ? rawSkip.toInt()
        : int.tryParse(rawSkip?.toString() ?? '') ?? skip + rawMessages.length;
    final hasMore = data['has_more'] == true && rawMessages.isNotEmpty;
    if (hasMore && nextSkip <= skip) {
      throw const FormatException('Invalid chat-messages pagination cursor.');
    }
    messages.sort((a, b) => a.date.compareTo(b.date));
    return RemoteChatMessagesPage(
      messages: messages,
      hasMore: hasMore,
      nextSkip: nextSkip,
    );
  }
}
