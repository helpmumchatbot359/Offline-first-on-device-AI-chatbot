import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/legal_links.dart';
import '../../../../core/theme/theme_bloc/theme_bloc.dart';
import '../../../../core/theme/theme_bloc/theme_event.dart';
import '../../../../core/theme/theme_bloc/theme_state.dart';
import '../../../../core/widgets/mama_background.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/events/auth_event.dart';
import '../../../auth/presentation/states/auth_state.dart';
import '../../../chat/presentation/cubit/offline_setup_cubit.dart';
import '../../../chat/presentation/widgets/offline_model_banner.dart';
import 'legal_document_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _confirmSignOut(BuildContext context) async {
    final authBloc = context.read<AuthBloc>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your saved chats will stay on this phone. You can sign in again any time.',
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

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final authBloc = context.read<AuthBloc>();
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountConfirmationDialog(),
    );
    if (deleted == true) authBloc.add(AccountDeletionRequested());
  }

  void _openLegal(
    BuildContext context, {
    required String title,
    required String assetPath,
    required String externalUrl,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentPage(
          title: title,
          assetPath: assetPath,
          externalUrl: externalUrl,
        ),
      ),
    );
  }

  void _openOfflineAssistant(BuildContext context) {
    // The dialog is another route, so pass the already-created cubit in
    // explicitly. BlocProvider.value never disposes it: closing the dialog
    // must not stop a download that is already running.
    final offlineSetupCubit = context.read<OfflineSetupCubit>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: offlineSetupCubit,
        child: Dialog(
          // The banner already draws its own card, so the dialog itself stays
          // invisible and only provides the centred position + dimmed barrier.
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: OfflineModelBanner(
              showWhenReady: true,
              margin: EdgeInsets.zero,
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: MamaBackground(
        child: BlocBuilder<AuthBloc, AuthState>(
          buildWhen: (previous, current) =>
              previous.displayName != current.displayName ||
              previous.email != current.email ||
              previous.status != current.status ||
              previous.busy != current.busy ||
              previous.error != current.error,
          builder: (context, auth) {
            final name = (auth.displayName?.trim().isNotEmpty ?? false)
                ? auth.displayName!.trim()
                : 'Mama';
            final email = auth.email?.trim() ?? '';
            final initial = _initial(name, email);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                _ProfileCard(name: name, email: email, initial: initial),
                const SizedBox(height: 22),
                _SectionLabel('Appearance'),
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: BlocBuilder<ThemeBloc, ThemeState>(
                    buildWhen: (previous, current) =>
                        previous.themeMode != current.themeMode,
                    builder: (context, theme) {
                      final isDark = theme.themeMode == ThemeMode.dark;
                      return SwitchListTile.adaptive(
                        value: isDark,
                        onChanged: (_) =>
                            context.read<ThemeBloc>().add(const ThemeToggled()),
                        secondary: Icon(
                          isDark
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                        title: const Text('Dark mode'),
                        subtitle: const Text('Easier on the eyes at night'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 3,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 22),
                _SectionLabel('Offline assistant'),
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.cloud_download_outlined),
                    title: const Text('Download offline assistant'),
                    subtitle: const Text('Manage the on-device model'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openOfflineAssistant(context),
                  ),
                ),
                const SizedBox(height: 22),
                _SectionLabel('Legal'),
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: const Text('Terms of Use'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openLegal(
                          context,
                          title: 'Terms of Use',
                          assetPath: 'assets/legal/terms_of_use.md',
                          externalUrl: LegalLinks.terms,
                        ),
                      ),
                      Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: scheme.outlineVariant,
                      ),
                      ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('Privacy Policy'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _openLegal(
                          context,
                          title: 'Privacy Policy',
                          assetPath: 'assets/legal/privacy_policy.md',
                          externalUrl: LegalLinks.privacy,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _SectionLabel('Account'),
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        enabled: !auth.busy,
                        leading: const Icon(Icons.logout_rounded),
                        title: const Text('Sign out'),
                        onTap: auth.busy
                            ? null
                            : () => _confirmSignOut(context),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
                  child: Text(
                    'PERMANENT DELETION',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: scheme.error.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (auth.error != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Text(
                            auth.error!,
                            style: TextStyle(color: scheme.error),
                          ),
                        ),
                      ListTile(
                        enabled: !auth.busy,
                        leading: Icon(
                          Icons.delete_forever_outlined,
                          color: scheme.error,
                        ),
                        title: Text(
                          auth.busy ? 'Deleting account…' : 'Delete account',
                          style: TextStyle(
                            color: scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Permanently delete your account and saved chats',
                        ),
                        trailing: auth.busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : null,
                        onTap: auth.busy
                            ? null
                            : () => _confirmDeleteAccount(context),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _initial(String name, String email) {
    final source = name.trim().isNotEmpty ? name : email.trim();
    if (source.isEmpty) return 'M';
    return String.fromCharCode(source.runes.first).toUpperCase();
  }
}

class _DeleteAccountConfirmationDialog extends StatefulWidget {
  const _DeleteAccountConfirmationDialog();

  @override
  State<_DeleteAccountConfirmationDialog> createState() =>
      _DeleteAccountConfirmationDialogState();
}

class _DeleteAccountConfirmationDialogState
    extends State<_DeleteAccountConfirmationDialog> {
  final _confirmationController = TextEditingController();

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Are you sure?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This will permanently delete your account and remove your '
            'saved chats from this phone. You will be signed out. This '
            'action cannot be undone.',
          ),
          const SizedBox(height: 16),
          const Text('Type “Delete Account” to continue.'),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmationController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Delete Account',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
            minimumSize: const Size(120, 44),
          ),
          onPressed: _confirmationController.text.trim() == 'Delete Account'
              ? () => Navigator.pop(context, true)
              : null,
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.email,
    required this.initial,
  });

  final String name;
  final String email;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          UserAvatar(initial: initial, radius: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
