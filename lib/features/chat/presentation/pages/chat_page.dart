import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/mama_background.dart';
import '../../../../core/widgets/mama_logo.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/events/auth_event.dart';
import '../../domain/chat_session.dart';
import '../../domain/chat_turn.dart';
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
      // The standard hamburger icon appears automatically because a drawer
      // is attached. Tapping it shows every saved conversation.
      drawer: const _ChatHistoryDrawer(),
      // A slightly wider "grab area" on the left edge makes the swipe-to-open
      // gesture feel more forgiving and smoother.
      drawerEdgeDragWidth: 28,
      onDrawerChanged: (isOpened) {
        // Refresh on every open, whether the person tapped the icon or swiped.
        if (isOpened) {
          context.read<ChatBloc>().add(const ChatHistoryRequested());
        }
      },
      appBar: AppBar(
        titleSpacing: 16,
        title: const _Title(),
        actions: const [
          _NewChatButton(),
          ThemeToggleButton(),
          _ChatMenuButton(),
        ],
      ),
      body: const SafeArea(
        top: false,
        bottom: false,
        child: MamaBackground(
          child: Column(
            children: [
              OfflineModelBanner(),
              Expanded(child: _MessageList()),
              ChatComposer(),
            ],
          ),
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
    final scheme = Theme.of(context).colorScheme;
    // The app bar is neutral in both themes now, so the status label simply
    // follows the header's normal ink.
    final headerInk =
        Theme.of(context).appBarTheme.foregroundColor ?? scheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'MamaBot',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        BlocSelector<ChatBloc, ChatState, bool>(
          selector: (s) => s.isOnline,
          builder: (context, isOnline) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isOnline ? c.online : c.offline,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isOnline ? 'Online' : 'Offline mode',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: headerInk.withValues(alpha: 0.65)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
          'MamaBot will start a fresh conversation. This one will stay in '
          'Chat history so you can come back to it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
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

/// One compact menu for the whole conversation. Gemini keeps the history
/// list clean and moves the per-chat actions here, under the "more" button.
class _ChatMenuButton extends StatelessWidget {
  const _ChatMenuButton();

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign in again any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
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

  Future<void> _confirmDelete(
    BuildContext context,
    String chatId,
    String title,
  ) async {
    final bloc = context.read<ChatBloc>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: Text(
          '“$title” and all of its messages will be removed from this phone. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) bloc.add(ChatDeleted(chatId));
  }

  Future<void> _copyConversation(
    BuildContext context,
    List<ChatTurn> turns,
  ) async {
    final transcript = StringBuffer();
    for (final turn in turns) {
      final question = turn.message.trim();
      final answer = turn.aiResponse.trim();
      if (question.isNotEmpty) transcript.writeln('You: $question');
      if (answer.isNotEmpty) transcript.writeln('MamaBot: $answer');
      transcript.writeln();
    }
    if (transcript.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: transcript.toString().trim()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Conversation copied')));
  }

  Future<void> _sendFeedback(BuildContext context, ChatTurn turn) async {
    final bloc = context.read<ChatBloc>();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send feedback'),
        content: const Text('Was this conversation helpful?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'not_helpful'),
            child: const Text('Not helpful'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, 'positive'),
            child: const Text('Helpful'),
          ),
        ],
      ),
    );
    if (value == null) return;

    bloc.add(FeedbackSubmitted(turnId: turn.id, feedbackValue: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Thanks for your feedback')));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      buildWhen: (previous, current) =>
          previous.messages != current.messages ||
          previous.sessions != current.sessions ||
          previous.activeChatId != current.activeChatId ||
          previous.isGenerating != current.isGenerating,
      builder: (context, state) {
        // The last finished answer is what a conversation-level feedback
        // rating applies to.
        ChatTurn? lastAnswer;
        for (final turn in state.messages) {
          if (!turn.isStreaming &&
              !turn.isError &&
              turn.aiResponse.trim().isNotEmpty) {
            lastAnswer = turn;
          }
        }

        String chatTitle = 'This chat';
        for (final session in state.sessions) {
          if (session.id == state.activeChatId) chatTitle = session.title;
        }

        final hasChat = state.activeChatId != null && state.messages.isNotEmpty;

        return PopupMenuButton<String>(
          tooltip: 'More options',
          onSelected: (value) {
            if (value == 'copy') {
              _copyConversation(context, state.messages);
            } else if (value == 'feedback') {
              if (lastAnswer != null) _sendFeedback(context, lastAnswer);
            } else if (value == 'delete') {
              if (state.activeChatId != null) {
                _confirmDelete(context, state.activeChatId!, chatTitle);
              }
            } else if (value == 'signout') {
              _confirmSignOut(context);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'copy',
              enabled: state.messages.isNotEmpty,
              child: const _MenuItem(
                icon: Icons.copy_all_rounded,
                label: 'Copy conversation',
              ),
            ),
            PopupMenuItem(
              value: 'feedback',
              enabled: lastAnswer != null,
              child: const _MenuItem(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Send feedback',
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              enabled: hasChat,
              child: const _MenuItem(
                icon: Icons.delete_outline_rounded,
                label: 'Delete chat',
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'signout',
              child: _MenuItem(icon: Icons.logout_rounded, label: 'Sign out'),
            ),
          ],
        );
      },
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatBloc, ChatState>(
      buildWhen: (p, c) =>
          p.messages != c.messages || p.isLoading != c.isLoading,
      builder: (context, state) {
        if (state.isLoading) return const SizedBox.shrink();
        if (state.messages.isEmpty) return const _EmptyState();

        final items = state.messages;
        // reverse: true keeps the newest message pinned at the bottom,
        // so we never need manual "scroll to bottom" code.
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MamaLogo(size: 72),
            const SizedBox(height: 18),
            Text(
              'Hello Mum',
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask me anything about pregnancy, your baby or vaccines.',
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in _starters)
                  ActionChip(
                    label: Text(q),
                    onPressed: () =>
                        context.read<ChatBloc>().add(MessageSent(q)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatHistoryDrawer extends StatelessWidget {
  const _ChatHistoryDrawer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return BlocBuilder<ChatBloc, ChatState>(
      buildWhen: (previous, current) =>
          previous.sessions != current.sessions ||
          previous.activeChatId != current.activeChatId ||
          previous.isGenerating != current.isGenerating,
      builder: (context, state) {
        return Drawer(
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: const RoundedRectangleBorder(),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DrawerHeader(scheme: scheme),
                _NewChatRow(
                  scheme: scheme,
                  enabled: !state.isGenerating,
                  onPressed: () {
                    // Read the bloc BEFORE closing the drawer, because the
                    // drawer's context stops working once it is popped.
                    final bloc = context.read<ChatBloc>();
                    Navigator.of(context).pop();
                    bloc.add(const NewChatStarted());
                  },
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
                  child: Text(
                    'All',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: state.sessions.isEmpty
                      ? const _EmptyHistory()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                          itemCount: state.sessions.length,
                          itemBuilder: (context, index) {
                            final session = state.sessions[index];
                            return _SessionTile(
                              session: session,
                              selected: session.id == state.activeChatId,
                              enabled: !state.isGenerating,
                            );
                          },
                        ),
                ),
                _DrawerFooter(scheme: scheme),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 10, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'MamaBot',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: scheme.onSurface,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close_rounded,
              size: 22,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NewChatRow extends StatelessWidget {
  const _NewChatRow({
    required this.scheme,
    required this.enabled,
    required this.onPressed,
  });

  final ColorScheme scheme;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 22, color: scheme.onSurface),
                  const SizedBox(width: 12),
                  Text(
                    'New chat',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.forum_outlined,
                size: 28,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No saved chats yet',
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'When you start a new chat, the old one will appear here.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 13,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'Your chats are saved on this phone.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.selected,
    required this.enabled,
  });

  final ChatSession session;
  final bool selected;

  /// Chats cannot be switched while an answer is still being written.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? scheme.surfaceContainerHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled
              ? () {
                  // Grab the bloc before the drawer closes.
                  final bloc = context.read<ChatBloc>();
                  Navigator.of(context).pop();
                  bloc.add(ChatOpened(session.id));
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Text(
              session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
