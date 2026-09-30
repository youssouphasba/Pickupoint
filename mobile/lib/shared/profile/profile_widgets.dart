import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/user.dart';
import '../widgets/account_switcher.dart';
import '../widgets/authenticated_avatar.dart';
import '../widgets/support_whatsapp_tile.dart';

String profileModeLabel(String role) => switch (role) {
      'driver' => 'Mode livreur',
      'relay_agent' => 'Mode point relais',
      _ => 'Mode client',
    };

String identityVerificationLabel(String status) => switch (status) {
      'verified' => 'Identité vérifiée',
      'pending' => 'Vérification en cours',
      'rejected' => 'Documents à corriger',
      _ => 'Documents à compléter',
    };

String profilePhotoLabel(User user) {
  if ((user.profilePictureUrl ?? user.avatarUrl ?? '').isEmpty) {
    return 'Photo à ajouter';
  }
  return switch (user.profilePictureStatus) {
    'approved' => 'Photo approuvée',
    'pending' => 'Photo en attente de validation',
    'rejected' => 'Photo à remplacer',
    _ => 'Validation de la photo à vérifier',
  };
}

class ProfileAppBarActions extends StatelessWidget {
  const ProfileAppBarActions({super.key, this.showSettings = true});

  final bool showSettings;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AccountSwitcherButton(),
          const SupportWhatsAppButton(),
          if (showSettings)
            IconButton(
              tooltip: 'Paramètres',
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      );
}

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.user, required this.role});

  final User user;
  final String role;

  @override
  Widget build(BuildContext context) => ProfileSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AuthenticatedAvatar(
                  imageUrl: user.profilePictureUrl ?? user.avatarUrl,
                  radius: 30,
                  fallback: const Icon(Icons.person_outline, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(user.phone),
                      const SizedBox(height: 4),
                      Text(profileModeLabel(role),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary)),
                    ],
                  ),
                ),
                if (user.isPhoneVerified)
                  const Tooltip(
                    message: 'Numéro de téléphone vérifié',
                    child: Icon(Icons.verified_outlined, color: Colors.green),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/settings/account'),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Modifier mes informations'),
            ),
          ],
        ),
      );
}

class ProfileSection extends StatelessWidget {
  const ProfileSection(
      {super.key, this.title, this.subtitle, required this.child});

  final String? title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side:
                BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null) ...[
                  Text(title!,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 5),
                    Text(subtitle!,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 12),
                ],
                child,
              ],
            ),
          ),
        ),
      );
}

class ProfileAction extends StatelessWidget {
  const ProfileAction(
      {super.key,
      required this.title,
      required this.icon,
      this.subtitle,
      this.route,
      this.onTap});

  final String title;
  final IconData icon;
  final String? subtitle;
  final String? route;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap ?? (route == null ? null : () => context.push(route!)),
      );
}

class ProfileNotice extends StatelessWidget {
  const ProfileNotice({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          if (onRetry != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer')),
            ),
        ],
      );
}
