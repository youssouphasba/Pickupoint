import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/relay_point.dart';
import '../../../core/models/user.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/utils/date_format.dart';
import '../../../shared/widgets/authenticated_avatar.dart';
import '../providers/admin_provider.dart';
import 'admin_parcel_audit_screen.dart';
import 'admin_relay_detail_screen.dart';
import 'admin_user_history_screen.dart';
import '../../../shared/utils/error_utils.dart';

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
          final walletFinancialSummary = Map<String, dynamic>.from(
            wallet['financial_summary'] as Map? ?? const {},
          );
          final recentTransactions = List<Map<String, dynamic>>.from(
            walletFinancialSummary['recent_transactions'] as List? ?? const [],
          );
          final applications = List<Map<String, dynamic>>.from(
            data['applications'] as List? ?? const [],
          );
          final referral = Map<String, dynamic>.from(
            data['referral'] as Map<String, dynamic>? ?? const {},
          );
          final sponsoredReferrals = Map<String, dynamic>.from(
            referral['sponsored_referrals'] as Map? ?? const {},
          );
          final kycDocuments = <Map<String, String>>[
            {
              'label': "Piece d'identite (recto + verso)",
              'url': _stringOrEmpty(userData['kyc_id_card_url']),
            },
            {
              'label': 'Permis de conduire (recto + verso)',
              'url': _stringOrEmpty(userData['kyc_license_url']),
            },
          ].where((document) => document['url']!.isNotEmpty).toList();

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
                  onOpenSupport: () =>
                      _openWhatsappSupport(context, ref, user.id, user.phone),
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
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'KYC',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _StatusChip(
                            label: _kycStatusLabel(user.kycStatus),
                            color: _kycColor(user.kycStatus),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              user.isDriver
                                  ? "Pour un livreur, la piece d'identite et le permis sont requis avant validation."
                                  : "L'utilisateur peut transmettre ses pieces plus tard depuis son profil.",
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (kycDocuments.isEmpty)
                        const Text(
                          'Aucun document KYC transmis pour le moment.',
                          style: TextStyle(color: Colors.grey),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final document in kycDocuments)
                              OutlinedButton.icon(
                                onPressed: () => _openDocumentPreview(
                                  context,
                                  ref,
                                  document['label']!,
                                  document['url']!,
                                ),
                                icon: const Icon(Icons.visibility_outlined),
                                label: Text(document['label']!),
                              ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: kycDocuments.isEmpty
                                ? null
                                : () => _moderateKyc(
                                      context,
                                      ref,
                                      user,
                                      status: 'verified',
                                    ),
                            icon: const Icon(Icons.verified_user_outlined),
                            label: const Text('Verifier'),
                          ),
                          OutlinedButton.icon(
                            onPressed: kycDocuments.isEmpty
                                ? null
                                : () => _moderateKyc(
                                      context,
                                      ref,
                                      user,
                                      status: 'rejected',
                                    ),
                            icon: const Icon(Icons.block_outlined),
                            label: const Text('Refuser'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Résumé',
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricTile(
                        label: 'Colis envoyés',
                        value: '${summary['parcels_sent'] ?? 0}',
                      ),
                      _MetricTile(
                        label: 'Colis reçus',
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
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Actions admin',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _callPhone(context, user.phone),
                            icon: const Icon(Icons.call_outlined),
                            label: const Text('Appeler'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _openWhatsappSupport(
                              context,
                              ref,
                              user.id,
                              user.phone,
                            ),
                            icon: const Icon(Icons.support_agent_outlined),
                            label: const Text('Support WhatsApp'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AdminUserHistoryScreen(
                                  userId: user.id,
                                  userName: user.name,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.history_outlined),
                            label: const Text('Historique'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _resetUserPin(context, ref, user),
                            icon: const Icon(Icons.password_outlined),
                            label: const Text('Réinitialiser PIN'),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  user.isBanned ? Colors.green : Colors.red,
                            ),
                            onPressed: () => _toggleBan(context, ref, user),
                            icon: Icon(
                              user.isBanned
                                  ? Icons.check_circle_outline
                                  : Icons.block_outlined,
                            ),
                            label: Text(user.isBanned ? 'Débannir' : 'Bannir'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Changement de rôle et liaison relais : Admin > Utilisateurs > menu actions sur la liste.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
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
                          label: 'Gains cumulés',
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
                    title: 'Point relais lié',
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
                              backgroundColor: Colors.orange.withValues(
                                alpha: 0.12,
                              ),
                              child: const Icon(
                                Icons.store,
                                color: Colors.orange,
                              ),
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
                                    '${linkedRelay.city} - ${linkedRelay.addressLabel}',
                                  ),
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
                if (walletFinancialSummary.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Finances livreur',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoRow(
                          'Commission pr\u00e9lev\u00e9e',
                          formatXof(
                            ((walletFinancialSummary['commissions']
                                            as Map?)?['wallet_hold_xof']
                                        as num?)
                                    ?.toDouble() ??
                                0,
                          ),
                        ),
                        _InfoRow(
                          'Commission en dette',
                          formatXof(
                            ((walletFinancialSummary['commissions']
                                            as Map?)?['driver_debt_xof']
                                        as num?)
                                    ?.toDouble() ??
                                0,
                          ),
                        ),
                        _InfoRow(
                          'Commission offerte',
                          formatXof(
                            ((walletFinancialSummary['commissions']
                                            as Map?)?['platform_sponsored_xof']
                                        as num?)
                                    ?.toDouble() ??
                                0,
                          ),
                        ),
                        _InfoRow(
                          'Retraits en attente',
                          '${(walletFinancialSummary['payouts'] as Map?)?['pending_count'] ?? 0} - ${formatXof((((walletFinancialSummary['payouts'] as Map?)?['pending_xof'] as num?)?.toDouble()) ?? 0)}',
                        ),
                        _InfoRow(
                          'Retraits valid\u00e9s',
                          '${(walletFinancialSummary['payouts'] as Map?)?['approved_count'] ?? 0} - ${formatXof((((walletFinancialSummary['payouts'] as Map?)?['approved_xof'] as num?)?.toDouble()) ?? 0)}',
                        ),
                        _InfoRow(
                          'Retraits refus\u00e9s',
                          '${(walletFinancialSummary['payouts'] as Map?)?['rejected_count'] ?? 0} - ${formatXof((((walletFinancialSummary['payouts'] as Map?)?['rejected_xof'] as num?)?.toDouble()) ?? 0)}',
                        ),
                        if (recentTransactions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Mouvements r\u00e9cents',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          for (final tx in recentTransactions)
                            _TimelineTile(
                              item: {
                                'kind': tx['tx_type'],
                                'title': tx['description'] ?? tx['tx_type'],
                                'subtitle': tx['reference'],
                                'occurred_at': tx['created_at'],
                                'amount': tx['amount'],
                              },
                            ),
                        ],
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
                        _InfoRow(
                          'Creee le',
                          _formatDateValue(lastSession['created_at']),
                        ),
                        _InfoRow(
                          'Expire le',
                          _formatDateValue(lastSession['expires_at']),
                        ),
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
                      _InfoRow('Code', _stringOrDash(referral['code'])),
                      _InfoRow(
                        'Acces effectif',
                        (referral['effective_enabled'] as bool? ?? false)
                            ? 'Actif'
                            : 'Desactive',
                      ),
                      _InfoRow(
                        'Peut parrainer',
                        (referral['can_sponsor'] as bool? ?? false)
                            ? 'Oui'
                            : 'Non',
                      ),
                      _InfoRow(
                        'Peut etre parraine',
                        (referral['can_be_referred'] as bool? ?? false)
                            ? 'Oui'
                            : 'Non',
                      ),
                      _InfoRow(
                        'Override',
                        _referralOverrideLabel(referral['enabled_override']),
                      ),
                      Builder(
                        builder: (_) {
                          final rc = Map<String, dynamic>.from(
                            referral['role_config'] as Map? ?? const {},
                          );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _InfoRow(
                                'Bonus parrain',
                                formatXof(
                                  (rc['sponsor_bonus_xof'] as num?)
                                          ?.toDouble() ??
                                      0.0,
                                ),
                              ),
                              _InfoRow(
                                'Bonus filleul',
                                formatXof(
                                  (rc['referred_bonus_xof'] as num?)
                                          ?.toDouble() ??
                                      0.0,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      _InfoRow(
                        'Regle saisie',
                        _stringOrDash(referral['apply_rule']),
                      ),
                      _InfoRow(
                        'Regle prime',
                        _stringOrDash(referral['reward_rule']),
                      ),
                      _InfoRow(
                        'Lien actif',
                        _stringOrDash(referral['referral_url']),
                      ),
                      _InfoRow(
                        'Filleuls',
                        '${referral['referrals_count'] ?? 0}',
                      ),
                      const SizedBox(height: 8),
                      _SponsoredReferralList(
                        summary: sponsoredReferrals,
                        userId: user.id,
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

  Future<void> _openWhatsappSupport(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String phone,
  ) async {
    final cleanPhone = phone.trim();
    try {
      final response = await ref
          .read(apiClientProvider)
          .startWhatsappSupport(userId: userId);
      final data = Map<String, dynamic>.from(response.data as Map);
      final conversation = Map<String, dynamic>.from(
        data['conversation'] as Map? ?? const {},
      );
      final conversationId = conversation['conversation_id']?.toString() ?? '';
      if (!context.mounted) {
        return;
      }
      final query = conversationId.isNotEmpty
          ? '?c=${Uri.encodeComponent(conversationId)}'
          : cleanPhone.isEmpty
              ? ''
              : '?q=${Uri.encodeComponent(cleanPhone)}';
      context.push('/admin/support$query');
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
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
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _moderateKyc(
    BuildContext context,
    WidgetRef ref,
    User user, {
    required String status,
  }) async {
    String? reason;
    if (status == 'rejected') {
      reason = await _askAdminReason(
        context: context,
        title: 'Refuser le KYC',
        helper:
            "Explique pourquoi les pieces de ${user.name} ne sont pas valides.",
        confirmLabel: 'Refuser',
        confirmColor: Colors.red,
      );
      if (reason == null) {
        return;
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Verifier le KYC'),
          content: Text(
            'Confirmer la validation KYC de ${user.name} ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Verifier'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }

    try {
      await ref.read(apiClientProvider).moderateUserKyc(
            user.id,
            status: status,
            reason: reason,
          );
      ref.invalidate(adminUsersProvider);
      ref.invalidate(adminUserDetailProvider(user.id));
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'verified' ? 'KYC verifie.' : 'KYC refuse.',
          ),
          backgroundColor: status == 'verified' ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  String _referralOverrideLabel(dynamic override) {
    if (override == null) {
      return 'Herite du parametre global';
    }
    return (override as bool) ? 'Force actif' : 'Force inactif';
  }

  Future<void> _resetUserPin(
    BuildContext context,
    WidgetRef ref,
    User user,
  ) async {
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String? errorText;

    final payload = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Réinitialiser le PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'Nouveau PIN',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'Confirmer',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motif',
                  border: OutlineInputBorder(),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final pin = pinCtrl.text.trim();
                final confirm = confirmCtrl.text.trim();
                final reason = reasonCtrl.text.trim();
                if (pin.length != 4 || int.tryParse(pin) == null) {
                  setDialogState(
                    () => errorText = 'Le PIN doit contenir 4 chiffres.',
                  );
                  return;
                }
                if (pin != confirm) {
                  setDialogState(
                    () => errorText = 'Les deux PIN diffèrent.',
                  );
                  return;
                }
                if (reason.length < 3) {
                  setDialogState(
                    () => errorText = 'Indique un motif.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, {'pin': pin, 'reason': reason});
              },
              child: const Text('Réinitialiser'),
            ),
          ],
        ),
      ),
    );

    pinCtrl.dispose();
    confirmCtrl.dispose();
    reasonCtrl.dispose();
    if (payload == null) {
      return;
    }

    try {
      await ref.read(apiClientProvider).resetUserPin(
            user.id,
            newPin: payload['pin']!,
            reason: payload['reason']!,
          );
      ref.invalidate(adminUserDetailProvider(user.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN utilisateur réinitialisé.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleBan(
    BuildContext context,
    WidgetRef ref,
    User user,
  ) async {
    final reason = await _askAdminReason(
      context: context,
      title: user.isBanned
          ? 'Confirmer le débannissement'
          : 'Confirmer le bannissement',
      helper: user.isBanned
          ? 'Explique pourquoi tu lèves la suspension de ${user.name}.'
          : 'Explique pourquoi tu suspends le compte de ${user.name}.',
      confirmLabel: user.isBanned ? 'Débannir' : 'Bannir',
      confirmColor: user.isBanned ? Colors.green : Colors.red,
    );

    if (reason == null) {
      return;
    }

    try {
      final api = ref.read(apiClientProvider);
      if (user.isBanned) {
        await api.unbanUser(user.id, reason: reason);
      } else {
        await api.banUser(user.id, reason: reason);
      }
      ref.invalidate(adminUsersProvider);
      ref.invalidate(adminUserDetailProvider(user.id));
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            user.isBanned
                ? 'Utilisateur débanni avec succès.'
                : 'Utilisateur banni avec succes.',
          ),
          backgroundColor: user.isBanned ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  Future<String?> _askAdminReason({
    required BuildContext context,
    required String title,
    required String helper,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final controller = TextEditingController();
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(helper),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Motif',
                  hintText: 'Exemple: fraude, documents invalides, correction',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final value = controller.text.trim();
                if (value.length < 3) {
                  setDialogState(
                    () =>
                        errorText = 'Saisis un motif d au moins 3 caracteres.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    return result;
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({
    required this.user,
    required this.createdAt,
    required this.updatedAt,
    required this.acceptedLegalAt,
    required this.onCall,
    required this.onOpenSupport,
    required this.onOpenHistory,
  });

  final User user;
  final dynamic createdAt;
  final dynamic updatedAt;
  final dynamic acceptedLegalAt;
  final VoidCallback onCall;
  final VoidCallback onOpenSupport;
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
                AuthenticatedAvatar(
                  imageUrl: hasPhoto ? photoUrl : null,
                  radius: 30,
                  backgroundColor: Colors.blueGrey.shade50,
                  fallback: const Icon(
                    Icons.person,
                    size: 30,
                    color: Colors.blueGrey,
                  ),
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
                  onPressed: onOpenSupport,
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('Support WhatsApp'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenHistory,
                  icon: const Icon(Icons.history),
                  label: const Text('Historique'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _InfoRow('Légal accepté', user.acceptedLegal ? 'Oui' : 'Non'),
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

class _SponsoredReferralList extends ConsumerWidget {
  const _SponsoredReferralList({
    required this.summary,
    required this.userId,
  });

  final Map<String, dynamic> summary;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = (summary['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SmallReferralMetric('Total', '${summary['total'] ?? 0}'),
              _SmallReferralMetric(
                'En attente',
                '${summary['pending_rewards'] ?? 0}',
              ),
              _SmallReferralMetric('Payes', '${summary['rewarded'] ?? 0}'),
              _SmallReferralMetric(
                'Bonus',
                formatXof(
                  (summary['total_sponsor_bonus_xof'] as num?)?.toDouble() ??
                      0.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text(
              'Aucun filleul inscrit.',
              style: TextStyle(color: Colors.grey),
            )
          else
            for (final item in items.take(8))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _stringOrDash(item['referred_name']),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${item['reward_metric_count'] ?? 0} / ${item['reward_count'] ?? 1} objectif',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _StatusChip(
                          label: _referralStatusLabel(item['status']),
                          color: _referralStatusColor(item['status']),
                        ),
                      ],
                    ),
                    if (item['status']?.toString() == 'qualified' &&
                        (item['referral_id']?.toString().trim().isNotEmpty ??
                            false))
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Valider paiement'),
                          onPressed: () => _confirmPayment(context, ref, item),
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _confirmPayment(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> item,
  ) async {
    final referralId = item['referral_id']?.toString().trim() ?? '';
    if (referralId.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Valider le paiement ?'),
        content: Text(
          "Confirmer que le paiement parrainage de ${_stringOrDash(item['referred_name'])} a été effectué.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(apiClientProvider).confirmReferralPayment(referralId);
      ref.invalidate(adminUserDetailProvider(userId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paiement parrainage validé')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  static String _stringOrDash(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  static String _referralStatusLabel(dynamic status) {
    switch (status?.toString()) {
      case 'rewarded':
        return 'Paye';
      case 'qualified':
        return 'Qualifie';
      case 'qualified_no_bonus':
        return 'Sans bonus';
      default:
        return 'En cours';
    }
  }

  static Color _referralStatusColor(dynamic status) {
    switch (status?.toString()) {
      case 'rewarded':
        return Colors.green;
      case 'qualified':
        return Colors.blue;
      case 'qualified_no_bonus':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }
}

class _SmallReferralMetric extends StatelessWidget {
  const _SmallReferralMetric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _MissionSummaryCard extends StatelessWidget {
  const _MissionSummaryCard({required this.mission, required this.onOpenAudit});

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

class _ApplicationCard extends ConsumerWidget {
  const _ApplicationCard({required this.application});

  final Map<String, dynamic> application;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = Map<String, dynamic>.from(
      application['data'] as Map? ?? const {},
    );
    final type = _stringOrDash(application['type']);
    final isDriver = type == 'driver';
    final documents = isDriver
        ? <_ApplicationDocument>[
            _ApplicationDocument(
              label: 'Pièce d’identité',
              url: _stringOrEmpty(data['id_card_url']),
            ),
            _ApplicationDocument(
              label: 'Permis de conduire',
              url: _stringOrEmpty(data['license_url']),
            ),
          ]
        : <_ApplicationDocument>[];

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
          if (documents.any((document) => document.url.isNotEmpty)) ...[
            const SizedBox(height: 8),
            const Text(
              'Documents',
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
          ],
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

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final amount = item['amount'] as num?;
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
            _stringOrDash(item['title'] ?? item['kind']),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          if (_stringOrDash(item['subtitle']) != '--')
            Text(_stringOrDash(item['subtitle'])),
          Text('Type: ${_stringOrDash(item['kind'])}'),
          Text('Date: ${_formatDateValue(item['occurred_at'])}'),
          if (amount != null) Text('Montant: ${formatXof(amount.toDouble())}'),
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

String _kycStatusLabel(String status) {
  switch (status) {
    case 'verified':
      return 'Verifie';
    case 'pending':
      return 'En attente';
    case 'rejected':
      return 'Refuse';
    default:
      return 'Non fourni';
  }
}
