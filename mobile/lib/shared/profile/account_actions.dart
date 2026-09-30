import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../features/driver/providers/driver_provider.dart';
import '../utils/error_utils.dart';

Future<bool> canLeaveCurrentAccount(BuildContext context, WidgetRef ref) async {
  final user = ref.read(authProvider).valueOrNull?.user;
  if (user == null) return false;
  if (!user.isDriver) return true;
  try {
    if (await canLeaveDriverAccount(ref)) return context.mounted;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Terminez ou libérez votre course active avant de quitter votre compte.'),
      ));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Impossible de vérifier vos courses en cours. Réessayez.'),
      ));
    }
  }
  return false;
}

class AccountManagementSection extends ConsumerStatefulWidget {
  const AccountManagementSection({super.key});

  @override
  ConsumerState<AccountManagementSection> createState() =>
      _AccountManagementSectionState();
}

class _AccountManagementSectionState
    extends ConsumerState<AccountManagementSection> {
  bool _busy = false;
  bool _working = false;

  Future<void> _run({required bool delete}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await canLeaveCurrentAccount(context, ref) || !mounted) return;
      if (delete) {
        if (!await _confirmDeletion() || !mounted) return;
        if (!await canLeaveCurrentAccount(context, ref) || !mounted) return;
        setState(() => _working = true);
        await ref.read(authProvider.notifier).deleteAccount();
      } else {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Se déconnecter ?'),
            content: const Text(
                'Vous devrez vous reconnecter pour accéder à votre compte.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Se déconnecter')),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        setState(() => _working = true);
        await ref.read(authProvider.notifier).logout();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _working = false;
        });
      }
    }
  }

  Future<bool> _confirmDeletion() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer mon compte ?'),
        content: const Text(
            'Votre accès sera supprimé et vos informations personnelles seront anonymisées. Cette action ne peut pas être annulée.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuer')),
        ],
      ),
    );
    if (first != true || !mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (_) => const _DeleteAccountConfirmation(),
        ) ==
        true;
  }

  @override
  Widget build(BuildContext context) {
    final authenticated =
        ref.watch(authProvider).valueOrNull?.isAuthenticated == true;
    return PopScope(
        canPop: !_working,
        child: Column(
          children: [
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout),
                title: const Text('Se déconnecter'),
                onTap:
                    _busy || !authenticated ? null : () => _run(delete: false)),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('Supprimer mon compte'),
                onTap:
                    _busy || !authenticated ? null : () => _run(delete: true)),
            if (_working) const LinearProgressIndicator(),
          ],
        ));
  }
}

class _DeleteAccountConfirmation extends StatefulWidget {
  const _DeleteAccountConfirmation();

  @override
  State<_DeleteAccountConfirmation> createState() =>
      _DeleteAccountConfirmationState();
}

class _DeleteAccountConfirmationState
    extends State<_DeleteAccountConfirmation> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Confirmation finale'),
        content: TextField(
          controller: _controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
              labelText: 'Tapez SUPPRIMER', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: _controller.text.trim().toUpperCase() == 'SUPPRIMER'
                ? () => Navigator.pop(context, true)
                : null,
            child: const Text('Supprimer définitivement'),
          ),
        ],
      );
}
