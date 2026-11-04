import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/mama_logo.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/events/auth_event.dart';
import '../../domain/chat_session.dart';
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
      onDrawerChanged: (isOpened) {
        // Refresh on every open, whether the person tapped the icon or swiped.
        if (isOpened) {
          context.read<ChatBloc>().add(const ChatHistoryRequested());
        }
      },
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
    final scheme = Theme.of(context).colorScheme;
    // The header is a light surface in both themes, so the status label must
    // follow the app bar's ink instead of the screen's onSurface colour.
    final headerInk =
        Theme.of(context).appBarTheme.foregroundColor ??
        scheme.onPrimaryContainer;
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
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: headerInk.withValues(alpha: 0.85),
                ),
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

class _MenuButton extends StatelessWidget {
  const _MenuButton();

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
            Text(
              'Hello Mum',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
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

/// The left drawer that lists every conversation saved on this phone.
///
/// This is the part that behaves like Gemini / ChatGPT history: starting a new
/// chat no longer throws the old one away, it simply adds it to this list.
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
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      const MamaLogo(size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Chat history',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: state.isGenerating
                          ? null
                          : () {
                              // Read the bloc BEFORE closing the drawer,
                              // because the drawer's context stops working
                              // once it is popped.
                              final bloc = context.read<ChatBloc>();
                              Navigator.of(context).pop();
                              bloc.add(const NewChatStarted());
                            },
                      icon: const Icon(Icons.add_comment_outlined),
                      label: const Text('New chat'),
                    ),
                  ),
                ),
                Divider(height: 1, color: scheme.outlineVariant),
                Expanded(
                  child: state.sessions.isEmpty
                      ? const _EmptyHistory()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                  child: Text(
                    'Your chats are saved on this phone.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
            Icon(
              Icons.forum_outlined,
              size: 44,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
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

  Future<void> _confirmDelete(BuildContext context) async {
    final bloc = context.read<ChatBloc>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: Text(
          '“${session.title}” and all of its messages will be removed from '
          'this phone. This cannot be undone.',
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

    if (ok == true) bloc.add(ChatDeleted(session.id));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected ? scheme.primaryContainer : Colors.transparent;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    final secondary = selected
        ? scheme.onPrimaryContainer.withValues(alpha: 0.72)
        : scheme.onSurfaceVariant;

    final messages = session.messageCount;
    final messageLabel = messages == 1 ? 'message' : 'messages';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          contentPadding: const EdgeInsets.only(left: 12, right: 4),
          leading: Icon(
            selected
                ? Icons.chat_bubble_rounded
                : Icons.chat_bubble_outline_rounded,
            size: 20,
            color: selected ? foreground : scheme.onSurfaceVariant,
          ),
          title: Text(
            session.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: foreground,
            ),
          ),
          subtitle: Text(
            '${_relativeTime(session.updatedAt)} · $messages $messageLabel',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: secondary),
          ),
          trailing: IconButton(
            tooltip: 'Delete chat',
            onPressed: enabled ? () => _confirmDelete(context) : null,
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: selected
                  ? foreground.withValues(alpha: 0.8)
                  : scheme.onSurfaceVariant,
            ),
          ),
          onTap: enabled
              ? () {
                  // Grab the bloc before the drawer closes.
                  final bloc = context.read<ChatBloc>();
                  Navigator.of(context).pop();
                  bloc.add(ChatOpened(session.id));
                }
              : null,
        ),
      ),
    );
  }
}

/// "Today", "Yesterday", "Tue" or "4 Nov 2026" for the history list.
String _relativeTime(String iso) {
  final time = DateTime.tryParse(iso)?.toLocal();
  if (time == null) return '';

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final difference = today.difference(day).inDays;

  if (difference == 0) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return 'Today $hour:$minute';
  }
  if (difference == 1) return 'Yesterday';
  if (difference > 1 && difference < 7) {
    return const [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ][time.weekday - 1];
  }

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${time.day} ${months[time.month - 1]} ${time.year}';
}
