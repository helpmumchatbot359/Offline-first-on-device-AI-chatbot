import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/selection_toolbar.dart';
import '../../domain/chat_turn.dart';
import '../bloc/chat_bloc.dart';
import '../events/chat_event.dart';

/// One question + its answer.
class TurnView extends StatelessWidget {
  const TurnView({super.key, required this.turn});
  final ChatTurn turn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UserBubble(text: turn.message),
          const SizedBox(height: 8),
          _AiBubble(turn: turn),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.chatColors;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: c.userBubble,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: SelectableText(
            text,
            contextMenuBuilder: buildMamaSelectionToolbar,
            style: TextStyle(color: c.onUserBubble, fontSize: 16, height: 1.4),
          ),
        ),
      ),
    );
  }
}

class _AiBubble extends StatelessWidget {
  const _AiBubble({required this.turn});
  final ChatTurn turn;

  @override
  Widget build(BuildContext context) {
    final c = context.chatColors;
    final bg = turn.isError ? c.errorBubble : c.aiBubble;
    final fg = turn.isError ? c.onErrorBubble : c.onAiBubble;
    final waiting = turn.isStreaming && turn.aiResponse.isEmpty;

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.86,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(15, 11, 15, 11),
              decoration: BoxDecoration(
                color: bg,
                border: Border.all(color: c.aiBubbleBorder),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: waiting
                  ? _ThinkingIndicator(color: fg)
                  : SelectableText(
                      turn.aiResponse,
                      contextMenuBuilder: buildMamaSelectionToolbar,
                      style: TextStyle(color: fg, fontSize: 16, height: 1.4),
                    ),
            ),
          ),
          if (!waiting && !turn.isError)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 4),
              child: _MetaRow(turn: turn),
            ),
        ],
      ),
    );
  }
}

/// The quiet row under an answer: offline badge, time, and the same
/// copy / thumbs actions Gemini shows beneath its replies.
class _MetaRow extends StatefulWidget {
  const _MetaRow({required this.turn});
  final ChatTurn turn;

  @override
  State<_MetaRow> createState() => _MetaRowState();
}

class _MetaRowState extends State<_MetaRow> {
  String? _feedback;

  Future<void> _copyAnswer() async {
    await Clipboard.setData(ClipboardData(text: widget.turn.aiResponse));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Answer copied')));
  }

  void _sendFeedback(String value) {
    context.read<ChatBloc>().add(
      FeedbackSubmitted(turnId: widget.turn.id, feedbackValue: value),
    );
    setState(() => _feedback = value);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Thanks for your feedback')));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.chatColors;
    final scheme = Theme.of(context).colorScheme;
    final turn = widget.turn;
    final style = TextStyle(fontSize: 12, color: c.meta);
    final positive = _feedback == 'positive';
    final negative = _feedback == 'not_helpful';

    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (turn.isOffline)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.offlineBadge,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 12,
                  color: c.onOfflineBadge,
                ),
                const SizedBox(width: 4),
                Text(
                  'Offline answer',
                  style: TextStyle(fontSize: 12, color: c.onOfflineBadge),
                ),
              ],
            ),
          ),
        if (turn.isOffline && turn.synced)
          Icon(Icons.cloud_done_rounded, size: 14, color: c.meta),
        if (!turn.isStreaming) Text(_time(turn.date), style: style),
        if (!turn.isStreaming) ...[
          const SizedBox(width: 2),
          _ActionIcon(
            tooltip: 'Copy answer',
            icon: Icons.copy_rounded,
            color: c.meta,
            onTap: _copyAnswer,
          ),
          _ActionIcon(
            tooltip: 'Helpful',
            icon: positive ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
            color: positive ? scheme.primary : c.meta,
            onTap: () => _sendFeedback('positive'),
          ),
          _ActionIcon(
            tooltip: 'Not helpful',
            icon: negative
                ? Icons.thumb_down_rounded
                : Icons.thumb_down_outlined,
            color: negative ? scheme.error : c.meta,
            onTap: () => _sendFeedback('not_helpful'),
          ),
        ],
      ],
    );
  }

  static String _time(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

/// A small, low-contrast icon target that still has a comfortable tap area.
class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

/// Three softly pulsing dots. Static text if the phone asks for less motion.
class _ThinkingIndicator extends StatefulWidget {
  const _ThinkingIndicator({required this.color});
  final Color color;

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = Text(
      'Thinking',
      style: TextStyle(color: widget.color, fontSize: 16),
    );
    if (MediaQuery.of(context).disableAnimations) return label;
    return Semantics(
      label: 'MamaBot is thinking',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          label,
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_controller.value + i * 0.2) % 1.0;
                final opacity =
                    0.25 + 0.75 * math.max(0.0, math.sin(math.pi * phase));
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Opacity(
                    opacity: opacity,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
