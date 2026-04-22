import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/relay_point.dart';
import '../../../core/models/user.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';
import '../../../shared/widgets/authenticated_avatar.dart';
import '../providers/admin_provider.dart';
import 'admin_parcel_audit_screen.dart';
import '../../../shared/utils/error_utils.dart';

class AdminRelayDetailScreen extends ConsumerWidget {
  const AdminRelayDetailScreen({super.key, required this.relayId});

  final String relayId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(adminRelayDetailProvider(relayId));

    return Scaffold(
      appBar: AppBar(title: const Text('Fiche point relais')),
      body: detailAsync.when(
        data: (data) {
          final relayData = Map<String, dynamic>.from(
            data['relay_point'] as Map<String, dynamic>? ?? const {},
          );
          final relay = RelayPoint.fromJson(relayData);
          final ownerData = data['owner'] as Map<String, dynamic>?;
          final owner = ownerData == null ? null : User.fromJson(ownerData);
          final agents = (data['agents'] as List? ?? const [])
              .map(
                (item) => User.fromJson(Map<String, dynamic>.from(item as Map)),
              )
              .toList();
          final stockSummary = Map<String, dynamic>.from(
            data['stock_summary'] as Map<String, dynamic>? ?? const {},
          );
          final wallet = Map<String, dynamic>.from(
            data['wallet'] as Map<String, dynamic>? ?? const {},
          );
          final recentParcels = List<Map<String, dynamic>>.from(
            data['recent_parcels'] as List? ?? const [],
          );
          final applications = List<Map<String, dynamic>>.from(
            data['applications'] as List? ?? const [],
          );
          final rawAddress = relayData['address'];
          final address = Map<String, dynamic>.from(
            rawAddress is Map<String, dynamic>
                ? rawAddress
                : <String, dynamic>{
                    if (rawAddress is String && rawAddress.trim().isNotEmpty)
                      'label': rawAddress.trim(),
                  },
          );
          final rawGeopin = address['geopin'];
          final geopin = Map<String, dynamic>.from(
            rawGeopin is Map<String, dynamic> ? rawGeopin : const {},
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RelayHeader(
                  relay: relay,
                  relayData: relayData,
                  address: address,
                  geopin: geopin,
                  onCall: () => _callPhone(context, relay.phone),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Stock et capacité',
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricTile(
                        label: 'Capacité',
                        value: '${relay.capacity}',
                      ),
                      _MetricTile(
                        label: 'Charge',
                        value: '${relay.currentStock}',
                      ),
                      _MetricTile(
                        label: 'En attente origine',
                        value: '${stockSummary['pending_origin'] ?? 0}',
                      ),
                      _MetricTile(
                        label: 'Entrants',
                        value: '${stockSummary['incoming'] ?? 0}',
                      ),
                      _MetricTile(
                        label: 'Disponibles',
                        value: '${stockSummary['available'] ?? 0}',
                      ),
                      _MetricTile(
                        label: 'Livrés total',
                        value: '${stockSummary['delivered_total'] ?? 0}',
                      ),
                    ],
                  ),
                ),
                if (applications.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Candidatures et documents',
                    child: Column(
                      children: [
                        for (final application in applications)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ApplicationCard(application: application),
                          ),
                      ],
                    ),
                  ),
                ],
                if (owner != null) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Propriétaire',
                    child: _UserIdentityTile(
                      user: owner,
                      subtitle:
                          'User ID: ${owner.id}\nKYC: ${owner.kycStatus}\nActif: ${owner.isActive ? "Oui" : "Non"}',
                    ),
                  ),
                ],
                if (agents.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Agents liés',
                    child: Column(
                      children: [
                        for (final agent in agents)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _UserIdentityTile(
                              user: agent,
                              subtitle:
                                  'User ID: ${agent.id}\nRole: ${_roleLabel(agent.role)}\nKYC: ${agent.kycStatus}',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (wallet.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Wallet',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoRow(
                          'Wallet ID',
                          _stringOrDash(wallet['wallet_id']),
                        ),
                        _InfoRow(
                          'Solde',
                          formatXof(
                            (wallet['balance'] as num?)?.toDouble() ?? 0.0,
                          ),
                        ),
                        _InfoRow(
                          'En attente',
                          formatXof(
                            (wallet['pending'] as num?)?.toDouble() ?? 0.0,
                          ),
                        ),
                        _InfoRow('Devise', _stringOrDash(wallet['currency'])),
                        _InfoRow('Maj', _formatDateValue(wallet['updated_at'])),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Colis récents',
                  child: recentParcels.isEmpty
                      ? const Text('Aucun colis récent.')
                      : Column(
                          children: [
                            for (final parcel in recentParcels)
                              _RecentParcelTile(parcel: parcel),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text(friendlyError(e))),
      ),
    );
  }

  Future<void> _callPhone(BuildContext context, String phone) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Numéro indisponible.')));
      return;
    }

    final uri = Uri(scheme: 'tel', path: cleanPhone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impossible d ouvrir le composeur.')),
    );
  }
}

class _RelayHeader extends StatelessWidget {
  const _RelayHeader({
    required this.relay,
    required this.relayData,
    required this.address,
    required this.geopin,
    required this.onCall,
  });

  final RelayPoint relay;
  final Map<String, dynamic> relayData;
  final Map<String, dynamic> address;
  final Map<String, dynamic> geopin;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.orange.withValues(alpha: 0.12),
                  child: const Icon(
                    Icons.store,
                    color: Colors.orange,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        relay.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(relay.phone),
                      Text('${relay.city} - ${relay.addressLabel}'),
                      const SizedBox(height: 6),
                      Text(
                        'Relay ID: ${relay.id}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                  label: relay.isVerified ? 'Vérifié' : 'Non vérifié',
                  color: relay.isVerified ? Colors.green : Colors.orange,
                ),
                _StatusChip(
                  label: relay.isActive ? 'Actif' : 'Inactif',
                  color: relay.isActive ? Colors.green : Colors.grey,
                ),
                if (_stringOrDash(relayData['relay_type']) != '--')
                  _StatusChip(
                    label: _stringOrDash(relayData['relay_type']),
                    color: Colors.indigo,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: onCall,
                  icon: const Icon(Icons.call),
                  label: const Text('Appeler'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoRow(
              'Owner user ID',
              _stringOrDash(relayData['owner_user_id']),
            ),
            _InfoRow('Store ID', _stringOrDash(relayData['store_id'])),
            _InfoRow(
              'Reference externe',
              _stringOrDash(relayData['external_ref']),
            ),
            _InfoRow(
              'Adresse',
              _stringOrDash(address['label'] ?? address['district']),
            ),
            _InfoRow('Quartier', _stringOrDash(address['district'])),
            _InfoRow('Ville', _stringOrDash(address['city'])),
            _InfoRow(
              'Geopin',
              '${_stringOrDash(geopin['lat'])}, ${_stringOrDash(geopin['lng'])}',
            ),
            _InfoRow(
              'Rayon',
              _stringOrDash(relayData['coverage_radius_km']) == '--'
                  ? '--'
                  : '${relayData['coverage_radius_km']} km',
            ),
            _InfoRow('Score', _stringOrDash(relayData['score'])),
            _InfoRow('Description', _stringOrDash(relayData['description'])),
            _InfoRow('Cree le', _formatDateValue(relayData['created_at'])),
            _InfoRow(
              'Mis a jour le',
              _formatDateValue(relayData['updated_at']),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 145,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _UserIdentityTile extends ConsumerWidget {
  const _UserIdentityTile({required this.user, required this.subtitle});

  final User user;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoUrl = user.profilePictureUrl;
    final hasPhoto = photoUrl != null && photoUrl.trim().isNotEmpty;
    final documents = [
      _ApplicationDocument(
        label: 'Pièce d’identité',
        url: _stringOrEmpty(user.kycIdCardUrl),
      ),
      _ApplicationDocument(
        label: 'Permis de conduire',
        url: _stringOrEmpty(user.kycLicenseUrl),
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AuthenticatedAvatar(
                imageUrl: hasPhoto ? photoUrl : null,
                radius: 20,
                backgroundColor: Colors.blueGrey.shade50,
                fallback: const Icon(Icons.person, color: Colors.blueGrey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(user.phone),
                    if (user.email != null && user.email!.isNotEmpty)
                      Text(user.email!),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (documents.any((document) => document.url.isNotEmpty)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final document in documents)
                  if (document.url.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _openDocumentPreview(
                        context,
                        ref,
                        document.label,
                        document.url,
                      ),
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(document.label),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ApplicationCard extends ConsumerWidget {
  const _ApplicationCard({required this.application});

  final Map<String, dynamic> application;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = _stringOrEmpty(application['type']);
    final isDriver = type == 'driver';
    final data = Map<String, dynamic>.from(
      application['data'] as Map? ?? const {},
    );
    final documents = [
      _ApplicationDocument(
        label: 'Pièce d’identité',
        url: _stringOrEmpty(data['id_card_url']),
      ),
      _ApplicationDocument(
        label: 'Permis de conduire',
        url: _stringOrEmpty(data['license_url']),
      ),
      _ApplicationDocument(
        label: 'Document commerce',
        url: _stringOrEmpty(data['business_doc_url']),
      ),
      _ApplicationDocument(
        label: 'Registre commerce',
        url: _stringOrEmpty(data['business_reg_url']),
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDriver ? Icons.two_wheeler_outlined : Icons.store_outlined,
                color: isDriver ? Colors.indigo : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isDriver ? 'Candidature livreur' : 'Candidature point relais',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              _StatusChip(
                label: _applicationStatusLabel(application['status']),
                color: _applicationStatusColor(application['status']),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoRow(
            'ID candidature',
            _stringOrDash(application['application_id']),
          ),
          _InfoRow('Utilisateur', _stringOrDash(application['user_name'])),
          _InfoRow('Téléphone', _stringOrDash(application['user_phone'])),
          _InfoRow('Soumise le', _formatDateValue(application['created_at'])),
          _InfoRow('Mise à jour', _formatDateValue(application['updated_at'])),
          if (isDriver) ...[
            _InfoRow('Nom déclaré', _stringOrDash(data['full_name'])),
            _InfoRow('Numéro CNI', _stringOrDash(data['id_card_number'])),
            _InfoRow('Numéro permis', _stringOrDash(data['license_number'])),
            _InfoRow('Véhicule', _stringOrDash(data['vehicle_type'])),
          ] else ...[
            _InfoRow('Nom du commerce', _stringOrDash(data['business_name'])),
            _InfoRow('Adresse', _stringOrDash(data['address_label'])),
            _InfoRow('Ville', _stringOrDash(data['city'])),
            _InfoRow('Registre commerce', _stringOrDash(data['business_reg'])),
            _InfoRow('Horaires', _stringOrDash(data['opening_hours'])),
            if (data['geopin'] is Map)
              _InfoRow('GPS', _formatGeopin(data['geopin'] as Map)),
          ],
          if (_stringOrDash(data['message']) != '--')
            _InfoRow('Message candidat', _stringOrDash(data['message'])),
          if (_stringOrDash(application['admin_notes']) != '--')
            _InfoRow('Note admin', _stringOrDash(application['admin_notes'])),
          const SizedBox(height: 8),
          if (documents.any((document) => document.url.isNotEmpty)) ...[
            const Text(
              'Documents transmis',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final document in documents)
                  if (document.url.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _openDocumentPreview(
                        context,
                        ref,
                        document.label,
                        document.url,
                      ),
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(document.label),
                    ),
              ],
            ),
          ] else
            const Text(
              'Aucun document transmis dans cette candidature.',
              style: TextStyle(color: Colors.blueGrey),
            ),
        ],
      ),
    );
  }
}

class _ApplicationDocument {
  const _ApplicationDocument({required this.label, required this.url});

  final String label;
  final String url;
}

class _RecentParcelTile extends StatelessWidget {
  const _RecentParcelTile({required this.parcel});

  final Map<String, dynamic> parcel;

  @override
  Widget build(BuildContext context) {
    final parcelId = _stringOrDash(parcel['parcel_id']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(_stringOrDash(parcel['tracking_code'])),
        subtitle: Text(
          'Statut: ${_stringOrDash(parcel['status'])}\n'
          'Destinataire: ${_stringOrDash(parcel['recipient_name'])}\n'
          'Maj: ${_formatDateValue(parcel['updated_at'])}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.open_in_new),
          tooltip: 'Audit',
          onPressed: parcelId == '--'
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminParcelAuditScreen(id: parcelId),
                  ),
                ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

String _stringOrDash(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return '--';
  }
  return text;
}

String _stringOrEmpty(dynamic value) {
  return value?.toString().trim() ?? '';
}

String _formatGeopin(Map value) {
  final lat = _stringOrDash(value['lat']);
  final lng = _stringOrDash(value['lng']);
  if (lat == '--' && lng == '--') {
    return '--';
  }
  return '$lat, $lng';
}

String _applicationStatusLabel(dynamic value) {
  switch (_stringOrEmpty(value)) {
    case 'approved':
      return 'Approuvée';
    case 'rejected':
      return 'Refusée';
    case 'pending':
      return 'En attente';
    default:
      return _stringOrDash(value);
  }
}

Color _applicationStatusColor(dynamic value) {
  switch (_stringOrEmpty(value)) {
    case 'approved':
      return Colors.green;
    case 'rejected':
      return Colors.red;
    case 'pending':
      return Colors.orange;
    default:
      return Colors.blueGrey;
  }
}

Future<void> _openDocumentPreview(
  BuildContext context,
  WidgetRef ref,
  String title,
  String url,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<Uint8List>(
            future: ref.read(apiClientProvider).downloadBytes(url),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return Text(
                  friendlyError(snapshot.error ?? 'Document introuvable'),
                );
              }
              return InteractiveViewer(
                child: Image.memory(
                  snapshot.data!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Aperçu non disponible sur mobile pour ce format.',
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
          TextButton(
            onPressed: () async {
              final uri = Uri.tryParse(url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Ouvrir le lien'),
          ),
        ],
      );
    },
  );
}

String _formatDateValue(dynamic value) {
  if (value == null) {
    return '--';
  }
  if (value is DateTime) {
    return formatDate(value);
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return formatDate(parsed);
    }
  }
  return value.toString();
}

String _roleLabel(String role) {
  switch (role) {
    case 'driver':
      return 'Livreur';
    case 'relay_agent':
      return 'Agent relais';
    case 'admin':
      return 'Admin';
    case 'superadmin':
      return 'Super admin';
    default:
      return 'Client';
  }
}
