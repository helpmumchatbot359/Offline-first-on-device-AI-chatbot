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
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      // ≈ the offline model's 1024-token input limit
                      maxLength: 1000,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: state.isOnline
                            ? 'Ask about pregnancy, baby or vaccines'
                            : 'Offline: answers come from this phone',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (state.canStop)
                    IconButton.filled(
                      tooltip: 'Stop answer',
                      onPressed: () => context.read<ChatBloc>().add(const GenerationStopped()),
                      icon: const Icon(Icons.stop_rounded),
                    )
                  else
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: _hasText && !state.isGenerating ? _send : null,
                      icon: const Icon(Icons.send_rounded),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}