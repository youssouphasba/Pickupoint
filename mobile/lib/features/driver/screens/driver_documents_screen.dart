import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/profile/profile_widgets.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/widgets/support_whatsapp_tile.dart';

class DriverDocumentsScreen extends ConsumerStatefulWidget {
  const DriverDocumentsScreen({super.key});

  @override
  ConsumerState<DriverDocumentsScreen> createState() =>
      _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends ConsumerState<DriverDocumentsScreen> {
  String? _busyDocument;

  Future<void> _send(String type) async {
    if (_busyDocument != null) return;
    setState(() => _busyDocument = type);
    try {
      final now = DateTime.now();
      final expiresOn = await showDatePicker(
        context: context,
        initialDate: DateTime(now.year + 1),
        firstDate: now,
        lastDate: DateTime(now.year + 20),
        helpText: 'Date d’expiration du document',
      );
      if (expiresOn == null || !mounted) return;
      final photo = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (photo == null || !mounted) return;
      await ref
          .read(apiClientProvider)
          .uploadKyc(File(photo.path), type, expiresOn: expiresOn);
      await ref.read(authProvider.notifier).fetchMe();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Document envoyé. La vérification est en cours.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _busyDocument = null);
    }
  }

  String _description(String? url, DateTime? expiration) {
    if (url?.isNotEmpty != true) return 'Aucun document envoyé.';
    if (expiration == null) {
      return 'Document envoyé · date d’expiration non renseignée.';
    }
    final date = DateFormat('dd/MM/yyyy').format(expiration.toLocal());
    final expired =
        !DateTime(expiration.year, expiration.month, expiration.day + 1)
            .isAfter(DateTime.now());
    return expired
        ? 'Document expiré le $date · à remplacer.'
        : 'Document envoyé · expire le $date.';
  }

  Widget _document(String type, String title, IconData icon, String? url,
          DateTime? expiration) =>
      ProfileSection(
        title: title,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_description(url, expiration)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busyDocument == null ? () => _send(type) : null,
            icon: Icon(icon),
            label: Text(_busyDocument == type
                ? 'Envoi…'
                : url?.isNotEmpty == true
                    ? 'Remplacer le document'
                    : 'Envoyer le document'),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull?.user;
    return PopScope(
      canPop: _busyDocument == null,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Mes documents'),
            actions: const [SupportWhatsAppButton()]),
        body: user == null
            ? const Center(
                child: Text('Connectez-vous pour consulter vos documents.'))
            : RefreshIndicator(
                onRefresh: () => ref.read(authProvider.notifier).fetchMe(),
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      ProfileSection(
                          title: identityVerificationLabel(user.kycStatus),
                          subtitle:
                              'Ce statut concerne la vérification de votre dossier. La validation de votre photo de profil est distincte.',
                          child: const Text(
                              'Envoyez des documents lisibles et gardez leurs dates d’expiration à jour.')),
                      ProfileSection(
                          title: 'Photo de profil',
                          child: ProfileAction(
                              title: profilePhotoLabel(user),
                              icon: Icons.account_circle_outlined,
                              route: '/settings/account')),
                      _document(
                          'id_card',
                          'Pièce d’identité',
                          Icons.credit_card_outlined,
                          user.kycIdCardUrl,
                          user.kycIdCardExpiresAt),
                      _document(
                          'license',
                          'Permis ou justificatif livreur',
                          Icons.two_wheeler,
                          user.kycLicenseUrl,
                          user.kycLicenseExpiresAt),
                      const ProfileSection(
                          title: 'Besoin d’aide pour votre dossier ?',
                          child: SupportWhatsAppTile(
                              contentPadding: EdgeInsets.zero)),
                    ]),
              ),
      ),
    );
  }
}
