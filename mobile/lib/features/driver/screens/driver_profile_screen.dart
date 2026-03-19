import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/user.dart';
import '../../../shared/utils/currency_format.dart';
import '../providers/driver_provider.dart';

class DriverProfileScreen extends ConsumerStatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  ConsumerState<DriverProfileScreen> createState() =>
      _DriverProfileScreenState();
}

class _DriverProfileScreenState extends ConsumerState<DriverProfileScreen> {
  bool _busyAvailability = false;
  bool _busyAvatar = false;
  String? _busyDocType;

  Future<void> _refresh() async {
    await ref.read(authProvider.notifier).fetchMe();
    ref.invalidate(driverWalletProvider);
    await ref.read(driverWalletProvider.future);
  }

  Future<void> _toggleAvailability() async {
    if (_busyAvailability) return;
    setState(() => _busyAvailability = true);
    try {
      final res = await ref.read(apiClientProvider).toggleAvailability();
      final newValue = res.data['is_available'] as bool? ?? false;
      ref.read(authProvider.notifier).updateUserAvailability(newValue);
    } catch (e) {
      _snack('Impossible de changer la disponibilite: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyAvailability = false);
    }
  }

  Future<void> _pickAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (image == null) return;
    setState(() => _busyAvatar = true);
    try {
      await ref.read(apiClientProvider).uploadAvatar(File(image.path));
      await ref.read(authProvider.notifier).fetchMe();
      _snack('Photo mise a jour.');
    } catch (e) {
      _snack('Upload photo impossible: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyAvatar = false);
    }
  }

  Future<void> _pickKyc(String docType, String label) async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image == null) return;
    setState(() => _busyDocType = docType);
    try {
      await ref.read(apiClientProvider).uploadKyc(File(image.path), docType);
      await ref.read(authProvider.notifier).fetchMe();
      _snack('$label envoye pour verification.');
    } catch (e) {
      _snack('Envoi impossible: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyDocType = null);
    }
  }

  Future<void> _editProfile(User user) async {
    final emailCtrl = TextEditingController(text: user.email ?? '');
    final bioCtrl = TextEditingController(text: user.bio ?? '');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mettre a jour mon profil'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: user.fullName ?? '',
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Nom complet',
                  helperText:
                      'Le nom n est pas modifiable pour des raisons de securite.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: user.phone,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Telephone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: bioCtrl,
                maxLines: 4,
                maxLength: 160,
                decoration: const InputDecoration(
                  labelText: 'Bio professionnelle',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final body = <String, dynamic>{
                  'bio': bioCtrl.text.trim(),
                };
                if (emailCtrl.text.trim().isNotEmpty) {
                  body['email'] = emailCtrl.text.trim();
                }
                await ref.read(apiClientProvider).updateProfile(body);
                await ref.read(authProvider.notifier).fetchMe();
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                _snack('Profil mis a jour.');
              } catch (e) {
                _snack('Mise a jour impossible: $e', error: true);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<void> _updatePrefs(String key, bool value, User user) async {
    final prefs = <String, dynamic>{
      'push': user.notificationPrefs.pushEnabled,
      'email': user.notificationPrefs.emailEnabled,
      'whatsapp': user.notificationPrefs.whatsappEnabled,
      'parcel_updates': user.notificationPrefs.parcelUpdatesEnabled,
      'promotions': user.notificationPrefs.promotionsEnabled,
    };
    prefs[key] = value;
    try {
      await ref.read(apiClientProvider).updateProfile({
        'notification_prefs': prefs,
      });
      await ref.read(authProvider.notifier).fetchMe();
      _snack('Preferences mises a jour.');
    } catch (e) {
      _snack('Impossible de mettre a jour les preferences: $e', error: true);
    }
  }

  void _copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    _snack('Information copiee.');
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider).valueOrNull;
    final user = authState?.user;
    final walletAsync = ref.watch(driverWalletProvider);
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Non connecte')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon profil livreur'),
        actions: [
          IconButton(
            onPressed: () => _editProfile(user),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildHeader(context, user, authState?.canSwitchToClient ?? false),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    icon: Icons.local_shipping_outlined,
                    label: 'Livraisons',
                    value: '${user.deliveriesCompleted}',
                    footer: 'terminees',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    icon: Icons.star_outline,
                    label: 'Note',
                    value: user.averageRating.toStringAsFixed(1),
                    footer: '${user.totalRatingsCount} avis',
                    color: Colors.amber.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Identite',
              subtitle: 'Informations de reference du compte livreur.',
              trailing: IconButton(
                onPressed: () => _editProfile(user),
                icon: const Icon(Icons.edit_outlined),
              ),
              child: Column(
                children: [
                  _infoRow(Icons.badge_outlined, 'Nom', user.fullName ?? '-',
                      helper: 'Non modifiable pour des raisons de securite.'),
                  _infoRow(Icons.phone_outlined, 'Telephone', user.phone,
                      helper: user.isPhoneVerified
                          ? 'Numero verifie'
                          : 'Numero non verifie'),
                  _infoRow(
                      Icons.alternate_email,
                      'E-mail',
                      (user.email ?? '').isEmpty
                          ? 'Non renseigne'
                          : user.email!),
                  _infoRow(Icons.fingerprint, 'ID livreur', user.id,
                      actionLabel: 'Copier', onAction: () => _copy(user.id)),
                  _infoRow(Icons.calendar_today_outlined, 'Membre depuis',
                      _formatDate(user.createdAt)),
                  _infoRow(Icons.language_outlined, 'Langue / devise',
                      '${user.language.toUpperCase()} - ${user.currency}'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Activite',
              subtitle: 'Controle terrain et acces rapides.',
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Disponibilite'),
                    subtitle: Text(user.isAvailable
                        ? 'Vous apparaissez dans les missions disponibles.'
                        : 'Vous etes hors ligne pour les nouvelles missions.'),
                    value: user.isAvailable,
                    onChanged:
                        _busyAvailability ? null : (_) => _toggleAvailability(),
                  ),
                  const Divider(height: 24),
                  walletAsync.when(
                    data: (wallet) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        child: Icon(Icons.account_balance_wallet_outlined),
                      ),
                      title: Text(formatXof(wallet.balance)),
                      subtitle: Text(
                          'En attente: ${formatXof(wallet.pendingBalance)}'),
                      trailing: TextButton(
                        onPressed: () => context.go('/driver/wallet'),
                        child: const Text('Voir'),
                      ),
                    ),
                    loading: () => const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Chargement du wallet...'),
                    ),
                    error: (_, __) => const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Wallet indisponible'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/driver/performance'),
                          icon: const Icon(Icons.insights_outlined),
                          label: const Text('Performance'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.go('/driver/wallet'),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Gains'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Conformite',
              subtitle:
                  'Documents utiles pour la verification et le controle admin.',
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor:
                          _kycColor(user.kycStatus).withValues(alpha: 0.12),
                      child: Icon(Icons.verified_user_outlined,
                          color: _kycColor(user.kycStatus)),
                    ),
                    title: Text(_kycLabel(user.kycStatus)),
                    subtitle: const Text(
                        'Gardez vos pieces a jour pour fluidifier les operations.'),
                  ),
                  const Divider(height: 24),
                  _docTile(
                    icon: Icons.credit_card_outlined,
                    title: 'Piece d identite',
                    subtitle: (user.kycIdCardUrl ?? '').isNotEmpty
                        ? 'Document deja envoye'
                        : 'Envoyer votre piece officielle',
                    isLoading: _busyDocType == 'id_card',
                    onPressed: () => _pickKyc('id_card', 'Piece d identite'),
                  ),
                  const SizedBox(height: 12),
                  _docTile(
                    icon: Icons.two_wheeler_outlined,
                    title: 'Permis ou justificatif livreur',
                    subtitle: (user.kycLicenseUrl ?? '').isNotEmpty
                        ? 'Document deja envoye'
                        : 'Envoyer votre permis ou justificatif',
                    isLoading: _busyDocType == 'license',
                    onPressed: () =>
                        _pickKyc('license', 'Justificatif livreur'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Notifications',
              subtitle: 'Canaux et alertes que vous souhaitez recevoir.',
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Push'),
                    subtitle: const Text('Alertes dans l application.'),
                    value: user.notificationPrefs.pushEnabled,
                    onChanged: (value) => _updatePrefs('push', value, user),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('WhatsApp'),
                    subtitle: const Text('Suivi et alertes complementaires.'),
                    value: user.notificationPrefs.whatsappEnabled,
                    onChanged: (value) => _updatePrefs('whatsapp', value, user),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mises a jour colis'),
                    subtitle: const Text('Infos sur vos missions et remises.'),
                    value: user.notificationPrefs.parcelUpdatesEnabled,
                    onChanged: (value) =>
                        _updatePrefs('parcel_updates', value, user),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Promotions'),
                    subtitle: const Text('Bonus et campagnes Denkma.'),
                    value: user.notificationPrefs.promotionsEnabled,
                    onChanged: (value) =>
                        _updatePrefs('promotions', value, user),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'Securite et liens utiles',
              subtitle:
                  'Repere rapide pour le compte, les documents legaux et la navigation.',
              child: Column(
                children: [
                  _infoRow(Icons.verified_user, 'Etat du compte',
                      user.isBanned ? 'Suspendu' : 'Actif'),
                  _infoRow(Icons.gavel_outlined, 'Acceptation legale',
                      user.acceptedLegal ? 'Acceptee' : 'Non acceptee',
                      helper: user.acceptedLegalAt != null
                          ? 'Le ${_formatDate(user.acceptedLegalAt)}'
                          : null),
                  _infoRow(Icons.schedule_outlined, 'Derniere mise a jour',
                      _formatDate(user.updatedAt)),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Politique de confidentialite'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/legal/privacy'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.gavel_outlined),
                    title: const Text('Conditions generales'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/legal/cgu'),
                  ),
                  if (authState?.canSwitchToClient ?? false)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.swap_horiz),
                      title: const Text('Passer a la vue client'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        ref.read(authProvider.notifier).switchView('client');
                        context.go('/client');
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => ref.read(authProvider.notifier).logout(),
              icon: const Icon(Icons.logout),
              label: const Text('Se deconnecter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, User user, bool canSwitchToClient) {
    final avatarUrl = user.profilePictureUrl ?? user.avatarUrl;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueGrey.shade900, Colors.blueGrey.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 46,
                backgroundColor: Colors.white24,
                child: CircleAvatar(
                  radius: 42,
                  backgroundColor: Colors.white,
                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl == null || avatarUrl.isEmpty
                      ? Text(
                          _initials(user.fullName ?? user.phone),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                        )
                      : null,
                ),
              ),
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  onPressed: _busyAvatar ? null : _pickAvatar,
                  icon: _busyAvatar
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_outlined),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            user.fullName ?? 'Livreur Denkma',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(user.phone, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _chip(user.isAvailable ? 'Disponible' : 'Hors ligne'),
              _chip(_kycLabel(user.kycStatus)),
              _chip('Niveau ${user.level}'),
            ],
          ),
          if ((user.bio ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              user.bio!.trim(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
          if (canSwitchToClient) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
              ),
              onPressed: () {
                ref.read(authProvider.notifier).switchView('client');
                context.go('/client');
              },
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Voir aussi ma vue client'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required String subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required String footer,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          Text(footer,
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value,
      {String? helper, String? actionLabel, VoidCallback? onAction}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: Colors.blueGrey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                if (helper != null) ...[
                  const SizedBox(height: 2),
                  Text(helper,
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }

  Widget _docTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.blueGrey.withValues(alpha: 0.1),
            child: Icon(icon, color: Colors.blueGrey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : OutlinedButton(
                  onPressed: onPressed,
                  child: const Text('Envoyer'),
                ),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  String _initials(String value) {
    final parts =
        value.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return 'D';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Non renseigne';
    return DateFormat('dd/MM/yyyy').format(date.toLocal());
  }

  String _kycLabel(String status) {
    switch (status) {
      case 'verified':
        return 'KYC verifie';
      case 'pending':
        return 'KYC en attente';
      case 'rejected':
        return 'KYC a corriger';
      default:
        return 'KYC non complete';
    }
  }

  Color _kycColor(String status) {
    switch (status) {
      case 'verified':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
