import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/mama_logo.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/events/auth_event.dart';
import '../bloc/chat_bloc.dart';
import '../events/chat_event.dart';
import '../states/chat_state.dart';
import '../widgets/chat_composer.dart';
import '../widgets/message_bubble.dart';
import '../widgets/offline_model_banner.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const _Title(),
        actions: const [_NewChatButton(), ThemeToggleButton(), _MenuButton()],
      ),
      body: const SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            OfflineModelBanner(),
            Expanded(child: _MessageList()),
            ChatComposer(),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    final c = context.chatColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('MamaBot', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        BlocSelector<ChatBloc, ChatState, bool>(
          selector: (s) => s.isOnline,
          builder: (context, isOnline) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOnline ? c.online : c.offline,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isOnline ? 'Online' : 'Offline mode',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The "New chat" button in the top bar.
///
/// It is GREYED OUT when pressing it would be pointless or unsafe:
///  - while history is still loading
///  - while an answer is being written (the half-written answer would leak
///    into the new chat)
///  - when the chat is already empty (nothing to start over from)
class _NewChatButton extends StatelessWidget {
  const _NewChatButton();

  Future<void> _confirm(BuildContext context) async {
    // Grab the bloc BEFORE the dialog opens (the context may change while it is open).
    final bloc = context.read<ChatBloc>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new chat?'),
        content: const Text(
          'MamaBot will start a fresh conversation and will not remember this one.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('New chat'),
          ),
        ],
      ),
    );
    if (ok == true) bloc.add(const NewChatStarted());
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ChatBloc, ChatState, bool>(
      selector: (s) => !s.isLoading && !s.isGenerating && s.messages.isNotEmpty,
      builder: (context, enabled) => IconButton(
        tooltip: 'New chat',
        icon: const Icon(Icons.add_comment_outlined),
        onPressed: enabled ? () => _confirm(context) : null,
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton();

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign in again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<AuthBloc>().add(SignedOut());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (v) {
        if (v == 'signout') _confirmSignOut(context);
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'signout', child: Text('Sign out')),
      ],
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      buildWhen: (p, c) => p.messages != c.messages || p.isLoading != c.isLoading,
      builder: (context, state) {
        if (state.isLoading) return const SizedBox.shrink();
        if (state.messages.isEmpty) return const _EmptyState();

        final items = state.messages;
        // reverse: true keeps the newest message pinned at the bottom,
        // so we never need manual "scroll to bottom" code.
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: items.length,
          itemBuilder: (context, index) {
            final turn = items[items.length - 1 - index];
            return TurnView(key: ValueKey(turn.id), turn: turn);
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  static const _starters = [
    'What foods are good during pregnancy?',
    'Which vaccines does my baby need?',
    'What are the danger signs in pregnancy?',
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MamaLogo(size: 72),
            const SizedBox(height: 16),
            Text('Hello Mum', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Ask me anything about pregnancy, your baby or vaccines.',
              textAlign: TextAlign.center,
              style: text.bodyLarge,
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in _starters)
                  ActionChip(
                    label: Text(q),
                    onPressed: () => context.read<ChatBloc>().add(MessageSent(q)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}