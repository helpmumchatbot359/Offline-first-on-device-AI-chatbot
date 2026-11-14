import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/chat_turn.dart';

/// Small, screen-independent actions for a saved conversation.
///
/// Keeping the transcript builder here means the copy, Docs export and Gmail
/// draft all produce exactly the same text.
class ConversationActions {
  ConversationActions._();

  static String transcript(List<ChatTurn> turns) {
    final buffer = StringBuffer();
    for (final turn in turns) {
      final question = turn.message.trim();
      final answer = turn.aiResponse.trim();
      if (question.isNotEmpty) buffer.writeln('You: $question');
      if (answer.isNotEmpty) buffer.writeln('MamaBot: $answer');
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  static String subject({DateTime? at}) {
    final date = at ?? DateTime.now();
    final stamp =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return 'My MamaBot conversation ($stamp)';
  }

  static Future<void> copy(List<ChatTurn> turns) async {
    final text = transcript(turns);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Opens the phone's email app with the whole conversation already in the
  /// draft body. Returns false when no email app is available.
  static Future<bool> draftInGmail(List<ChatTurn> turns) async {
    final text = transcript(turns);
    if (text.isEmpty) return false;

    final uri = Uri.parse(
      'mailto:?subject=${Uri.encodeComponent(subject())}'
      '&body=${Uri.encodeComponent(text)}',
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Writes the conversation as a small text document and opens the Android
  /// share sheet, where Google Docs/Drive can take over the export.
  static Future<bool> exportToDocs(List<ChatTurn> turns) async {
    final text = transcript(turns);
    if (text.isEmpty) return false;

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/MamaBot conversation.txt');
      await file.writeAsString(text, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          subject: subject(),
          text: text,
          files: [XFile(file.path, mimeType: 'text/plain')],
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
