import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/relay_point.dart';
import '../../../core/models/user.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';
import '../providers/admin_provider.dart';
import 'admin_parcel_audit_screen.dart';
import 'admin_relay_detail_screen.dart';
import 'admin_user_history_screen.dart';

class AdminUserDetailScreen extends ConsumerWidget {
  const AdminUserDetailScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(adminUserDetailProvider(userId));

    return Scaffold(
      appBar: AppBar(title: const Text('Fiche utilisateur')),
      body: detailAsync.when(
        data: (data) {
          final userData = Map<String, dynamic>.from(
            data['user'] as Map<String, dynamic>? ?? const {},
          );
          final user = User.fromJson(userData);
          final summary = Map<String, dynamic>.from(
            data['summary'] as Map<String, dynamic>? ?? const {},
          );
          final linkedRelayData = data['linked_relay'] as Map<String, dynamic>?;
          final linkedRelay = linkedRelayData == null
              ? null
              : RelayPoint.fromJson(linkedRelayData);
          final wallet = Map<String, dynamic>.from(
            data['wallet'] as Map<String, dynamic>? ?? const {},
          );
          final activeMission = Map<String, dynamic>.from(
            data['active_mission'] as Map<String, dynamic>? ?? const {},
          );
          final lastMission = Map<String, dynamic>.from(
            data['last_mission'] as Map<String, dynamic>? ?? const {},
          );
          final lastSession = Map<String, dynamic>.from(
            data['last_session'] as Map<String, dynamic>? ?? const {},
          );
          final recentEvents = List<Map<String, dynamic>>.from(
              data['recent_events'] as List? ?? const []);
          final referral = Map<String, dynamic>.from(
            data['referral'] as Map<String, dynamic>? ?? const {},
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IdentityHeader(
                  user: user,
                  createdAt: userData['created_at'],
                  updatedAt: userData['updated_at'],
                  acceptedLegalAt: userData['accepted_legal_at'],
                  onCall: () => _callPhone(context, user.phone),
                  onOpenHistory: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AdminUserHistoryScreen(
                        userId: user.id,
                        userName: user.name,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Resume',
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricTile(
                        label: 'Colis envoyes',
                        value: '${summary['parcels_sent'] ?? 0}',
                      ),
                      _MetricTile(
                        label: 'Colis recus',
                        value: '${summary['parcels_received'] ?? 0}',
                      ),
                      _MetricTile(
                        label: 'Missions',
                        value: '${summary['missions_count'] ?? 0}',
                      ),
                      _MetricTile(
                        label: 'Sessions actives',
                        value: '${summary['active_sessions'] ?? 0}',
                      ),
                    ],
                  ),
                ),
                if (user.isDriver) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Performance livreur',
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _MetricTile(
                          label: 'Livraisons',
                          value: '${user.deliveriesCompleted}',
                        ),
                        _MetricTile(
                          label: 'Note moyenne',
                          value: user.averageRating.toStringAsFixed(1),
                        ),
                        _MetricTile(
                          label: 'Gains cumules',
                          value: formatXof(user.totalEarned),
                        ),
                        _MetricTile(
                          label: 'Disponible',
                          value: user.isAvailable ? 'Oui' : 'Non',
                        ),
                      ],
                    ),
                  ),
                ],
                if (linkedRelay != null) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Point relais lie',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              AdminRelayDetailScreen(relayId: linkedRelay.id),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  Colors.orange.withValues(alpha: 0.12),
                              child:
                                  const Icon(Icons.store, color: Colors.orange),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    linkedRelay.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                      '${linkedRelay.city} - ${linkedRelay.addressLabel}'),
                                  Text(linkedRelay.phone),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
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
                if (activeMission.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Mission active',
                    child: _MissionSummaryCard(
                      mission: activeMission,
                      onOpenAudit: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AdminParcelAuditScreen(
                            id: _stringOrDash(activeMission['parcel_id']),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (lastMission.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Derniere mission',
                    child: _MissionSummaryCard(
                      mission: lastMission,
                      onOpenAudit: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AdminParcelAuditScreen(
                            id: _stringOrDash(lastMission['parcel_id']),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (lastSession.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Derniere session',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoRow('User ID', user.id),
                        _InfoRow('Creee le',
                            _formatDateValue(lastSession['created_at'])),
                        _InfoRow('Expire le',
                            _formatDateValue(lastSession['expires_at'])),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Parrainage',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(
                        'Code',
                        _stringOrDash(referral['code']),
                      ),
                      _InfoRow(
                        'Acces effectif',
                        (referral['effective_enabled'] as bool? ?? false)
                            ? 'Actif'
                            : 'Desactive',
                      ),
                      _InfoRow(
                        'Override',
                        _referralOverrideLabel(referral['enabled_override']),
                      ),
                      _InfoRow(
                        'Bonus',
                        formatXof(
                          (referral['bonus_xof'] as num?)?.toDouble() ?? 0.0,
                        ),
                      ),
                      _InfoRow(
                        'Filleuls',
                        '${referral['referrals_count'] ?? 0}',
                      ),
                      _InfoRow(
                        'Bonus deja credite',
                        (referral['referral_credited'] as bool? ?? false)
                            ? 'Oui'
                            : 'Non',
                      ),
                      if (referral['referred_by_user'] is Map<String, dynamic>)
                        _InfoRow(
                          'Parrain',
                          _stringOrDash(
                            (referral['referred_by_user']
                                as Map<String, dynamic>)['name'],
                          ),
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('Heriter'),
                            onPressed: () => _updateReferralAccess(
                              context,
                              ref,
                              user.id,
                              null,
                            ),
                          ),
                          ActionChip(
                            label: const Text('Forcer actif'),
                            onPressed: () => _updateReferralAccess(
                              context,
                              ref,
                              user.id,
                              true,
                            ),
                          ),
                          ActionChip(
                            label: const Text('Forcer inactif'),
                            onPressed: () => _updateReferralAccess(
                              context,
                              ref,
                              user.id,
                              false,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Evenements recents',
                  child: recentEvents.isEmpty
                      ? const Text('Aucun evenement recent.')
                      : Column(
                          children: [
                            for (final event in recentEvents)
                              _EventTile(event: event),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Erreur: $e')),
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

  Future<void> _updateReferralAccess(
    BuildContext context,
    WidgetRef ref,
    String userId,
    bool? enabledOverride,
  ) async {
    try {
      await ref
          .read(apiClientProvider)
          .setUserReferralAccess(userId, enabledOverride);
      ref.invalidate(adminUserDetailProvider(userId));
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acces parrainage mis a jour')),
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _referralOverrideLabel(dynamic override) {
    if (override == null) {
      return 'Herite du parametre global';
    }
    return (override as bool) ? 'Force actif' : 'Force inactif';
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({
    required this.user,
    required this.createdAt,
    required this.updatedAt,
    required this.acceptedLegalAt,
    required this.onCall,
    required this.onOpenHistory,
  });

  final User user;
  final dynamic createdAt;
  final dynamic updatedAt;
  final dynamic acceptedLegalAt;
  final VoidCallback onCall;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final photoUrl = user.profilePictureUrl;
    final hasPhoto = photoUrl != null && photoUrl.trim().isNotEmpty;

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
                  radius: 30,
                  backgroundColor: Colors.blueGrey.shade50,
                  backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
                  child: hasPhoto
                      ? null
                      : const Icon(Icons.person,
                          size: 30, color: Colors.blueGrey),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(user.phone),
                      if (user.email != null && user.email!.isNotEmpty)
                        Text(user.email!),
                      const SizedBox(height: 6),
                      Text(
                        'User ID: ${user.id}',
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
                _StatusChip(label: _roleLabel(user.role), color: Colors.indigo),
                _StatusChip(
                  label: user.isActive ? 'Actif' : 'Inactif',
                  color: user.isActive ? Colors.green : Colors.grey,
                ),
                _StatusChip(
                  label: user.isBanned ? 'Banni' : 'Non banni',
                  color: user.isBanned ? Colors.red : Colors.green,
                ),
                _StatusChip(
                  label: 'KYC ${user.kycStatus}',
                  color: _kycColor(user.kycStatus),
                ),
                if (user.isDriver)
                  _StatusChip(
                    label: user.isAvailable ? 'Disponible' : 'Indisponible',
                    color: user.isAvailable ? Colors.green : Colors.orange,
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
                OutlinedButton.icon(
                  onPressed: onOpenHistory,
                  icon: const Icon(Icons.history),
                  label: const Text('Historique'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoRow('Legal accepte', user.acceptedLegal ? 'Oui' : 'Non'),
            _InfoRow('Legal accepte le', _formatDateValue(acceptedLegalAt)),
            _InfoRow('Cree le', _formatDateValue(createdAt)),
            _InfoRow('Mis a jour le', _formatDateValue(updatedAt)),
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

class _MissionSummaryCard extends StatelessWidget {
  const _MissionSummaryCard({
    required this.mission,
    required this.onOpenAudit,
  });

  final Map<String, dynamic> mission;
  final VoidCallback onOpenAudit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow('Mission ID', _stringOrDash(mission['mission_id'])),
          _InfoRow('Parcel ID', _stringOrDash(mission['parcel_id'])),
          _InfoRow('Statut', _stringOrDash(mission['status'])),
          _InfoRow('Collecte', _stringOrDash(mission['pickup_label'])),
          _InfoRow('Livraison', _stringOrDash(mission['delivery_label'])),
          _InfoRow('Assignee le', _formatDateValue(mission['assigned_at'])),
          _InfoRow('Maj', _formatDateValue(mission['updated_at'])),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onOpenAudit,
              icon: const Icon(Icons.search),
              label: const Text('Ouvrir audit colis'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
            _stringOrDash(event['event_type']),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('Colis: ${_stringOrDash(event['parcel_id'])}'),
          Text('Date: ${_formatDateValue(event['created_at'])}'),
          if (_stringOrDash(event['notes']) != '--')
            Text('Notes: ${_stringOrDash(event['notes'])}'),
        ],
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
            width: 120,
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

Color _kycColor(String status) {
  switch (status) {
    case 'approved':
      return Colors.green;
    case 'pending':
      return Colors.orange;
    case 'rejected':
      return Colors.red;
    default:
      return Colors.grey;
  }
}
