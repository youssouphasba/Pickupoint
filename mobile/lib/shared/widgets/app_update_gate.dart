import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/app_update_info.dart';
import '../../core/providers/app_update_provider.dart';

class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate> {
  var _optionalPromptShown = false;

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(appUpdateProvider);
    return update.when(
      loading: () => widget.child,
      error: (_, __) => widget.child,
      data: (state) {
        if (state.decision == AppUpdateDecision.required) {
          return _RequiredUpdateScreen(state: state);
        }
        if (state.decision == AppUpdateDecision.available &&
            !_optionalPromptShown) {
          _optionalPromptShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showOptionalUpdateDialog(context, state);
          });
        }
        return widget.child;
      },
    );
  }
}

class _RequiredUpdateScreen extends StatelessWidget {
  const _RequiredUpdateScreen({required this.state});

  final AppUpdateState state;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.system_update_alt,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                'Mise à jour requise',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                state.info.message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Version installée : ${state.installedVersion}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => _openStore(state.info.storeUrl),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Mettre à jour'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showOptionalUpdateDialog(
  BuildContext context,
  AppUpdateState state,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Nouvelle version disponible'),
      content: Text(state.info.message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Plus tard'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            _openStore(state.info.storeUrl);
          },
          child: const Text('Mettre à jour'),
        ),
      ],
    ),
  );
}

Future<void> _openStore(String storeUrl) async {
  final uri = Uri.tryParse(storeUrl.trim());
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
