import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
              .map((item) =>
                  User.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList();
          final stockSummary = Map<String, dynamic>.from(
            data['stock_summary'] as Map<String, dynamic>? ?? const {},
          );
          final wallet = Map<String, dynamic>.from(
            data['wallet'] as Map<String, dynamic>? ?? const {},
          );
          final recentParcels = List<Map<String, dynamic>>.from(
              data['recent_parcels'] as List? ?? const []);
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
                  title: 'Stock et capacite',
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricTile(
                        label: 'Capacite',
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
                        label: 'Livres total',
                        value: '${stockSummary['delivered_total'] ?? 0}',
                      ),
                    ],
                  ),
                ),
                if (owner != null) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Proprietaire',
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
                    title: 'Agents lies',
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
                            'Wallet ID', _stringOrDash(wallet['wallet_id'])),
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
                  title: 'Colis recents',
                  child: recentParcels.isEmpty
                      ? const Text('Aucun colis recent.')
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numero indisponible.')),
      );
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
                  child:
                      const Icon(Icons.store, color: Colors.orange, size: 28),
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
                  label: relay.isVerified ? 'Verifie' : 'Non verifie',
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
                'Owner user ID', _stringOrDash(relayData['owner_user_id'])),
            _InfoRow('Store ID', _stringOrDash(relayData['store_id'])),
            _InfoRow(
                'Reference externe', _stringOrDash(relayData['external_ref'])),
            _InfoRow('Adresse',
                _stringOrDash(address['label'] ?? address['district'])),
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
                'Mis a jour le', _formatDateValue(relayData['updated_at'])),
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
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
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

class _UserIdentityTile extends StatelessWidget {
  const _UserIdentityTile({
    required this.user,
    required this.subtitle,
  });

  final User user;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final photoUrl = user.profilePictureUrl;
    final hasPhoto = photoUrl != null && photoUrl.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
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
    );
  }
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
                      builder: (context) =>
                          AdminParcelAuditScreen(id: parcelId),
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
