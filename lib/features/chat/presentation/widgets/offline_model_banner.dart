import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/offline_setup_cubit.dart';

/// Appears above the chat until the offline assistant is on the phone.
class OfflineModelBanner extends StatelessWidget {
  const OfflineModelBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OfflineSetupCubit, OfflineSetupState>(
      builder: (context, s) {
        if (s.status == OfflineSetupStatus.ready ||
            s.status == OfflineSetupStatus.checking) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;
        final cubit = context.read<OfflineSetupCubit>();
        final busy =
            s.status == OfflineSetupStatus.downloading ||
            s.status == OfflineSetupStatus.verifying;

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            // Neutral card with a thin border. Only the icon and the download
            // button carry the brand green.
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cloud_download_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Get answers with no internet',
                      style: text.titleSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                s.status == OfflineSetupStatus.failed && s.message != null
                    ? s.message!
                    : 'Download the offline assistant once (about 2.6 GB). Wi-Fi is best.',
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              if (busy) ...[
                LinearProgressIndicator(
                  value: s.status == OfflineSetupStatus.verifying
                      ? null
                      : s.progress,
                  borderRadius: BorderRadius.circular(8),
                  minHeight: 8,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.status == OfflineSetupStatus.verifying
                            ? 'Checking the file is safe…'
                            : '${(s.progress * 100).round()}% downloaded',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (s.status == OfflineSetupStatus.downloading)
                      TextButton(
                        onPressed: cubit.pause,
                        child: const Text('Pause'),
                      ),
                  ],
                ),
              ] else
                FilledButton.icon(
                  onPressed: cubit.download,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(
                    s.status == OfflineSetupStatus.failed
                        ? 'Resume download'
                        : 'Download',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
