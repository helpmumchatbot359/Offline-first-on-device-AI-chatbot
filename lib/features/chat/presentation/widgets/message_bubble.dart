import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
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
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.userBubble,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: SelectableText(
            text,
            style: TextStyle(color: c.onUserBubble, fontSize: 16, height: 1.35),
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
    final scheme = Theme.of(context).colorScheme;
    final bg = turn.isError ? c.errorBubble : c.aiBubble;
    final fg = turn.isError ? c.onErrorBubble : c.onAiBubble;
    final waiting = turn.isStreaming && turn.aiResponse.isEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: scheme.primaryContainer,
          child: Icon(Icons.favorite_rounded, size: 16, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                color: bg,
                border: Border.all(color: c.aiBubbleBorder),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (waiting)
                    _ThinkingIndicator(color: fg)
                  else
                    SelectableText(
                      turn.aiResponse,
                      style: TextStyle(color: fg, fontSize: 16, height: 1.4),
                    ),
                  if (!waiting && !turn.isError) ...[
                    const SizedBox(height: 6),
                    _MetaRow(turn: turn),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.turn});
  final ChatTurn turn;

  void _showFeedbackDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rate Offline Answer'),
        content: const Text('Was this offline response helpful?'),
        actions: [
          TextButton(
            onPressed: () {
              context.read<ChatBloc>().add(
                    FeedbackSubmitted(
                      turnId: turn.id,
                      feedbackValue: 'not_helpful',
                    ),
                  );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Thank you for your feedback!')),
              );
            },
            child: const Text('Not Helpful'),
          ),
          FilledButton(
            onPressed: () {
              context.read<ChatBloc>().add(
                    FeedbackSubmitted(
                      turnId: turn.id,
                      feedbackValue: 'positive',
                    ),
                  );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Thank you for your feedback!')),
              );
            },
            child: const Text('Helpful'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.chatColors;
    final style = TextStyle(fontSize: 12, color: c.meta);
    return Wrap(
      spacing: 8,
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
                Icon(Icons.cloud_off_rounded, size: 12, color: c.onOfflineBadge),
                const SizedBox(width: 4),
                Text('Offline answer',
                    style: TextStyle(fontSize: 12, color: c.onOfflineBadge)),
              ],
            ),
          ),
        if (turn.isOffline && turn.synced)
          Icon(Icons.cloud_done_rounded, size: 14, color: c.meta),
        if (!turn.isStreaming) Text(_time(turn.date), style: style),
        if (turn.isOffline && !turn.isStreaming) ...[
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _showFeedbackDialog(context),
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: Icon(Icons.thumb_up_outlined, size: 14, color: c.meta),
            ),
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
    final label = Text('Thinking', style: TextStyle(color: widget.color, fontSize: 16));
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
                final opacity = 0.25 + 0.75 * math.max(0.0, math.sin(math.pi * phase));
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Opacity(
                    opacity: opacity,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
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