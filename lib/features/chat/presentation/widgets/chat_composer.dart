import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/chat_bloc.dart';
import '../events/chat_event.dart';
import '../states/chat_state.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({super.key});

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    final bloc = context.read<ChatBloc>();
    if (text.isEmpty || bloc.state.isGenerating) return;
    _controller.clear();
    bloc.add(MessageSent(text));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // The composer floats on top of the page gradient. It is a neutral pill
    // with one small green action button - no big green block at the bottom.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: BlocBuilder<ChatBloc, ChatState>(
          buildWhen: (p, c) =>
              p.isGenerating != c.isGenerating ||
              p.canStop != c.canStop ||
              p.isOnline != c.isOnline,
          builder: (context, state) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      // ≈ the offline model's 1024-token input limit
                      maxLength: 1000,
                      buildCounter: (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => null,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: TextStyle(
                        fontSize: 15.5,
                        height: 1.35,
                        color: scheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: state.isOnline
                            ? 'Ask about pregnancy or baby care'
                            : 'Offline: answers on this phone',
                        filled: false,
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        hintStyle: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 52,
                  height: 52,
                  child: state.canStop
                      ? IconButton.filled(
                          tooltip: 'Stop answer',
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.surfaceContainerHigh,
                            foregroundColor: scheme.onSurface,
                            shape: const CircleBorder(),
                          ),
                          onPressed: () => context.read<ChatBloc>().add(
                            const GenerationStopped(),
                          ),
                          icon: const Icon(Icons.stop_rounded),
                        )
                      : IconButton.filled(
                          tooltip: 'Send',
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.primary,
                            foregroundColor: scheme.onPrimary,
                            disabledBackgroundColor: scheme.surfaceContainer,
                            disabledForegroundColor: scheme.onSurfaceVariant,
                            shape: const CircleBorder(),
                          ),
                          onPressed: _hasText && !state.isGenerating
                              ? _send
                              : null,
                          icon: const Icon(Icons.send_rounded, size: 21),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
