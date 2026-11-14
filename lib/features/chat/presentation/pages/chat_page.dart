import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/mama_background.dart';
import '../../../../core/widgets/mama_logo.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/events/auth_event.dart';
import '../../../auth/presentation/states/auth_state.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../domain/chat_session.dart';
import '../../domain/chat_turn.dart';
import '../bloc/chat_bloc.dart';
import '../cubit/offline_setup_cubit.dart';
import '../events/chat_event.dart';
import '../states/chat_state.dart';
import '../utils/conversation_actions.dart';
import '../widgets/chat_composer.dart';
import '../widgets/message_bubble.dart';
import '../widgets/offline_model_banner.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<ChatBloc, ChatState>(
      listenWhen: (previous, current) =>
          previous.notice != current.notice && current.notice != null,
      listener: (context, state) {
        final notice = state.notice;
        if (notice == null) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(notice)));
        context.read<ChatBloc>().add(const ChatNoticeCleared());
      },
      child: Scaffold(
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
          actions: const [_ChatActions()],
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

/// The right side of the app bar. A brand-new chat shows the person's badge
/// (like Gemini's avatar); a conversation shows the chat actions instead.
class _ChatActions extends StatelessWidget {
  const _ChatActions();

  @override
  Widget build(BuildContext context) {
    // The profile chip plus a full-size theme button is a tight fit on small
    // phones. The theme switch also lives in Settings, so drop it from the
    // bar below 380dp rather than risk an overflow.
    final showThemeToggle = MediaQuery.sizeOf(context).width >= 380;

    return BlocSelector<ChatBloc, ChatState, bool>(
      selector: (state) => state.messages.isEmpty && !state.isLoading,
      builder: (context, isFreshChat) {
        if (isFreshChat) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _ProfileChip(),
              if (showThemeToggle) const ThemeToggleButton(),
            ],
          );
        }
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [_NewChatButton(), ThemeToggleButton(), _ChatMenuButton()],
        );
      },
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip();

  void _openSettings(BuildContext context) {
    final offlineSetupCubit = context.read<OfflineSetupCubit>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: offlineSetupCubit,
          child: const SettingsPage(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<AuthBloc, AuthState>(
      buildWhen: (previous, current) =>
          previous.displayName != current.displayName ||
          previous.email != current.email,
      builder: (context, auth) {
        final name = auth.displayName?.trim();
        final email = auth.email?.trim() ?? '';
        final initial = _initialFor(name, email);
        final label = (name != null && name.isNotEmpty) ? name : 'Mama';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openSettings(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    UserAvatar(initial: initial, radius: 15),
                    const SizedBox(width: 7),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 82),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _initialFor(String? name, String email) {
    final source = (name != null && name.isNotEmpty) ? name : email;
    if (source.isEmpty) return 'M';
    return String.fromCharCode(source.runes.first).toUpperCase();
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

  Future<void> _renameChat(
    BuildContext context,
    String chatId,
    String currentTitle,
  ) async {
    final bloc = context.read<ChatBloc>();
    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          buildCounter: (
            _, {
            required currentLength,
            required isFocused,
            maxLength,
          }) => null,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(ctx, value),
          decoration: const InputDecoration(hintText: 'Give this chat a name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    final clean = newTitle?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean == null || clean.isEmpty || clean == currentTitle.trim()) return;
    bloc.add(ChatRenamed(chatId, clean));
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
          '“$title” and all of its messages will be removed from your chat history and this phone. '
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

  Future<void> _confirmSignOut(BuildContext context) async {
    final authBloc = context.read<AuthBloc>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your saved chats will stay on this phone. You can sign in again '
          'any time.',
        ),
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
    if (ok == true) authBloc.add(SignedOut());
  }

  Future<void> _copyConversation(
    BuildContext context,
    List<ChatTurn> turns,
  ) async {
    await ConversationActions.copy(turns);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Conversation copied')));
  }

  Future<void> _draftInGmail(BuildContext context, List<ChatTurn> turns) async {
    final opened = await ConversationActions.draftInGmail(turns);
    if (opened || !context.mounted) return;
    await ConversationActions.copy(turns);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No email app was found. The conversation was copied instead.',
        ),
      ),
    );
  }

  Future<void> _exportToDocs(BuildContext context, List<ChatTurn> turns) async {
    final shared = await ConversationActions.exportToDocs(turns);
    if (!context.mounted) return;
    if (!shared) {
      await ConversationActions.copy(turns);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the share sheet. The conversation was copied.',
          ),
        ),
      );
    }
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
            if (value == 'rename') {
              if (state.activeChatId != null) {
                _renameChat(context, state.activeChatId!, chatTitle);
              }
            } else if (value == 'branch') {
              context.read<ChatBloc>().add(const ChatBranched());
            } else if (value == 'copy') {
              _copyConversation(context, state.messages);
            } else if (value == 'docs') {
              _exportToDocs(context, state.messages);
            } else if (value == 'gmail') {
              _draftInGmail(context, state.messages);
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
              value: 'rename',
              enabled: hasChat,
              child: const _MenuItem(
                icon: Icons.edit_outlined,
                label: 'Rename chat',
              ),
            ),
            PopupMenuItem(
              value: 'branch',
              enabled: hasChat && !state.isGenerating,
              child: const _MenuItem(
                icon: Icons.account_tree_outlined,
                label: 'Branch in new chat',
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'copy',
              enabled: state.messages.isNotEmpty,
              child: const _MenuItem(
                icon: Icons.copy_all_rounded,
                label: 'Copy conversation',
              ),
            ),
            PopupMenuItem(
              value: 'docs',
              enabled: state.messages.isNotEmpty,
              child: const _MenuItem(
                icon: Icons.description_outlined,
                label: 'Export to Docs',
              ),
            ),
            PopupMenuItem(
              value: 'gmail',
              enabled: state.messages.isNotEmpty,
              child: const _MenuItem(
                icon: Icons.mail_outline_rounded,
                label: 'Draft in Gmail',
              ),
            ),
            const PopupMenuDivider(),
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
            PopupMenuItem(
              value: 'signout',
              child: _MenuItem(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = color ?? scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: ink),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
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
          p.messages != c.messages ||
          p.isLoading != c.isLoading ||
          p.hasMoreMessages != c.hasMoreMessages ||
          p.isLoadingMoreMessages != c.isLoadingMoreMessages,
      builder: (context, state) {
        if (state.isLoading) return const SizedBox.shrink();
        if (state.messages.isEmpty) return const _EmptyState();

        final items = state.messages;
        // reverse: true keeps the newest message pinned at the bottom,
        // so we never need manual "scroll to bottom" code.
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 120 &&
                state.hasMoreMessages &&
                !state.isLoadingMoreMessages) {
              context.read<ChatBloc>().add(const ChatMessagesMoreRequested());
            }
            return false;
          },
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: items.length + (state.isLoadingMoreMessages ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == items.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final turn = items[items.length - 1 - index];
              return TurnView(key: ValueKey(turn.id), turn: turn);
            },
          ),
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
          previous.hasMoreSessions != current.hasMoreSessions ||
          previous.isLoadingMoreSessions != current.isLoadingMoreSessions ||
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
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification.metrics.extentAfter < 120 &&
                                state.hasMoreSessions &&
                                !state.isLoadingMoreSessions) {
                              context.read<ChatBloc>().add(
                                const ChatHistoryMoreRequested(),
                              );
                            }
                            return false;
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                            itemCount:
                                state.sessions.length +
                                (state.isLoadingMoreSessions ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == state.sessions.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final session = state.sessions[index];
                              return _SessionTile(
                                session: session,
                                selected: session.id == state.activeChatId,
                                enabled: !state.isGenerating,
                              );
                            },
                          ),
                        ),
                ),
                _DrawerAccount(scheme: scheme),
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

/// The account row that replaces the old storage note at the bottom of the
/// drawer: avatar, name and a direct way into Settings.
class _DrawerAccount extends StatelessWidget {
  const _DrawerAccount({required this.scheme});

  final ColorScheme scheme;

  void _openSettings(BuildContext context) {
    final offlineSetupCubit = context.read<OfflineSetupCubit>();
    final navigator = Navigator.of(context);
    navigator.pop(); // close the drawer first
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: offlineSetupCubit,
          child: const SettingsPage(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      buildWhen: (previous, current) =>
          previous.displayName != current.displayName,
      builder: (context, auth) {
        final name = auth.displayName?.trim();
        // Only the username is shown here. The email stays in Settings where
        // it belongs, so the drawer footer feels personal rather than
        // technical.
        final label = (name != null && name.isNotEmpty) ? name : 'Mama';
        final initial = String.fromCharCode(label.runes.first).toUpperCase();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(
              height: 1,
              indent: 18,
              endIndent: 18,
              color: scheme.outlineVariant.withValues(alpha: 0.7),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openSettings(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                    child: Row(
                      children: [
                        UserAvatar(initial: initial, radius: 17),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Settings',
                          onPressed: () => _openSettings(context),
                          icon: Icon(
                            Icons.settings_outlined,
                            size: 21,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
                  bloc.add(
                    ChatOpened(session.id, restoreRemote: session.isRemote),
                  );
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
