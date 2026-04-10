import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_endpoints.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/phone_utils.dart';
import '../../../shared/utils/error_utils.dart';

final _applicationsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, status) async {
    final api = ref.watch(apiClientProvider);
    final res = await api.getAdminApplications(status: status);
    final data = res.data as Map<String, dynamic>;
    return (data['applications'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
        .toList();
  },
);

class AdminApplicationsScreen extends ConsumerStatefulWidget {
  const AdminApplicationsScreen({super.key});

  @override
  ConsumerState<AdminApplicationsScreen> createState() =>
      _AdminApplicationsScreenState();
}

class _AdminApplicationsScreenState
    extends ConsumerState<AdminApplicationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Candidatures partenaires'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: 'En attente'),
            Tab(text: 'Approuvees'),
            Tab(text: 'Rejetees'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _ApplicationsList(status: 'pending'),
          _ApplicationsList(status: 'approved'),
          _ApplicationsList(status: 'rejected'),
        ],
      ),
    );
  }
}

class _ApplicationsList extends ConsumerWidget {
  const _ApplicationsList({required this.status});

  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appsAsync = ref.watch(_applicationsProvider(status));

    return appsAsync.when(
      data: (apps) {
        if (apps.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 12),
                Text(
                  switch (status) {
                    'approved' => 'Aucune candidature approuvee',
                    'rejected' => 'Aucune candidature rejetee',
                    _ => 'Aucune candidature en attente',
                  },
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_applicationsProvider(status));
            await ref.read(_applicationsProvider(status).future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: apps.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ApplicationCard(app: apps[i]),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, __) => Center(child: Text(friendlyError(e))),
    );
  }
}

class _ApplicationCard extends ConsumerWidget {
  const _ApplicationCard({required this.app});

  final Map<String, dynamic> app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = app['type']?.toString() ?? 'relay';
    final status = app['status']?.toString() ?? 'pending';
    final data = _asMap(app['data']);
    final authState = ref.watch(authProvider).valueOrNull;
    final accessToken = authState?.accessToken;
    final phone = app['user_phone']?.toString() ?? '-';
    final name = app['user_name']?.toString() ?? phone;
    final appId = app['application_id']?.toString() ?? '';
    final userId = app['user_id']?.toString() ?? '';
    final isDriver = type == 'driver';
    final color = isDriver ? Colors.blue : Colors.orange;
    final icon = isDriver ? Icons.delivery_dining : Icons.storefront_outlined;
    final createdAt = _formatDate(app['created_at']);
    final updatedAt = _formatDate(app['updated_at']);
    final message = _stringValue(data['message']);
    final adminNotes = _stringValue(app['admin_notes']);
    final idCardUrl = userId.isNotEmpty
        ? ApiEndpoints.adminUserKyc(userId, 'id_card')
        : _stringValue(data['id_card_url']);
    final licenseUrl = userId.isNotEmpty
        ? ApiEndpoints.adminUserKyc(userId, 'license')
        : _stringValue(data['license_url']);
    final geoLabel = _geopinLabel(data['geopin']);
    final geoMapUrl = _geopinMapUrl(data['geopin']);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isDriver
                        ? 'Candidature livreur'
                        : 'Candidature point relais',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                _StatusBadge(status: status),
              ],
            ),
            const Divider(height: 20),
            _row(Icons.person_outline, 'Candidat', name),
            _row(Icons.phone_outlined, 'Telephone', maskPhone(phone)),
            _row(Icons.tag_outlined, 'Dossier', appId),
            _row(Icons.schedule_outlined, 'Soumise le', createdAt),
            if (status != 'pending')
              _row(Icons.update_outlined, 'Traitee le', updatedAt),
            if (isDriver) ...[
              _row(Icons.badge_outlined, 'CNI',
                  _stringOrDash(data['id_card_number'])),
              _row(Icons.credit_card_outlined, 'Permis',
                  _stringOrDash(data['license_number'])),
              _row(Icons.two_wheeler_outlined, 'Vehicule',
                  _stringOrDash(data['vehicle_type'])),
            ] else ...[
              _row(Icons.store_outlined, 'Boutique',
                  _stringOrDash(data['business_name'])),
              _row(
                Icons.location_on_outlined,
                'Adresse',
                _composeRelayAddress(data),
              ),
              if (geoLabel != null)
                _row(Icons.gps_fixed, 'Position GPS', geoLabel),
              _row(Icons.access_time_outlined, 'Horaires',
                  _stringOrDash(data['opening_hours'])),
              if (_stringValue(data['business_reg']).isNotEmpty)
                _row(Icons.business_outlined, 'Registre commerce',
                    _stringValue(data['business_reg'])),
            ],
            if (message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            if (adminNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Note admin : $adminNotes',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _call(context, phone),
                  icon: const Icon(Icons.phone, size: 16),
                  label: const Text('Appeler'),
                  style:
                      OutlinedButton.styleFrom(foregroundColor: Colors.green),
                ),
                if (geoMapUrl != null)
                  OutlinedButton.icon(
                    onPressed: () => _openExternal(context, geoMapUrl),
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('Voir position'),
                  ),
                if (idCardUrl.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: accessToken == null || accessToken.isEmpty
                        ? null
                        : () => _previewDocument(
                              context,
                              accessToken,
                              idCardUrl,
                              title: 'Piece d identite',
                            ),
                    icon: const Icon(Icons.badge_outlined, size: 16),
                    label: const Text('Piece ID'),
                  ),
                if (licenseUrl.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: accessToken == null || accessToken.isEmpty
                        ? null
                        : () => _previewDocument(
                              context,
                              accessToken,
                              licenseUrl,
                              title: 'Permis / justificatif',
                            ),
                    icon: const Icon(Icons.credit_card_outlined, size: 16),
                    label: const Text('Permis'),
                  ),
                if (status == 'pending')
                  OutlinedButton.icon(
                    onPressed: () => _showRejectDialog(context, ref, appId),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Rejeter'),
                    style:
                        OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  ),
                if (status == 'pending')
                  ElevatedButton.icon(
                    onPressed: () =>
                        _showApproveDialog(context, ref, appId, type),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Approuver'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
              ],
            ),
            if (status == 'pending' &&
                idCardUrl.isEmpty &&
                licenseUrl.isEmpty &&
                geoMapUrl == null) ...[
              const SizedBox(height: 12),
              const Text(
                'Aucune piece ni position jointe. Verifiez au minimum les informations saisies avant validation.',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _call(BuildContext context, String phone) async {
    await _openUri(
      context,
      Uri(scheme: 'tel', path: phone),
      errorMessage: 'Impossible d ouvrir le composeur telephonique',
    );
  }

  Future<void> _openExternal(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lien invalide')),
      );
      return;
    }
    await _openUri(
      context,
      uri,
      errorMessage: 'Impossible d ouvrir le lien',
    );
  }

  Future<void> _previewDocument(
    BuildContext context,
    String accessToken,
    String url, {
    required String title,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Image.network(
                  url,
                  headers: {'Authorization': 'Bearer $accessToken'},
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) {
                      return child;
                    }
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.broken_image_outlined,
                            size: 40,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Impossible d afficher l image directement.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => _openExternal(context, url),
                            icon: const Icon(Icons.open_in_browser_outlined),
                            label: const Text('Ouvrir le lien'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUri(
    BuildContext context,
    Uri uri, {
    required String errorMessage,
  }) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errorMessage)),
    );
  }

  void _showApproveDialog(
    BuildContext ctx,
    WidgetRef ref,
    String id,
    String type,
  ) {
    final notesCtrl = TextEditingController();
    showDialog<void>(
      context: ctx,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Text(type == 'driver' ? 'Approuver livreur' : 'Approuver relais'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              type == 'driver'
                  ? 'L utilisateur deviendra livreur et aura acces aux missions.'
                  : 'L utilisateur deviendra agent relais et un point relais sera cree automatiquement.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Note interne (optionnel)',
                border: OutlineInputBorder(),
                isDense: true,
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
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final api = ref.read(apiClientProvider);
                await api.approveApplication(
                  id,
                  notes: notesCtrl.text.trim().isEmpty
                      ? null
                      : notesCtrl.text.trim(),
                );
                _refreshAllLists(ref);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Candidature approuvee'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(friendlyError(e)),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(BuildContext ctx, WidgetRef ref, String id) {
    final notesCtrl = TextEditingController();
    showDialog<void>(
      context: ctx,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cancel, color: Colors.red),
            SizedBox(width: 8),
            Text('Rejeter la candidature'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Indiquez la raison pour informer le candidat.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Raison du rejet (optionnel)',
                border: OutlineInputBorder(),
                isDense: true,
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
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final api = ref.read(apiClientProvider);
                await api.rejectApplication(
                  id,
                  notes: notesCtrl.text.trim().isEmpty
                      ? null
                      : notesCtrl.text.trim(),
                );
                _refreshAllLists(ref);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Candidature rejetee'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(friendlyError(e)),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Rejeter'),
          ),
        ],
      ),
    );
  }

  void _refreshAllLists(WidgetRef ref) {
    ref.invalidate(_applicationsProvider('pending'));
    ref.invalidate(_applicationsProvider('approved'));
    ref.invalidate(_applicationsProvider('rejected'));
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return const {};
  }

  static String _stringValue(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  static String _stringOrDash(dynamic value) {
    final text = _stringValue(value);
    return text.isEmpty ? '-' : text;
  }

  static String _composeRelayAddress(Map<String, dynamic> data) {
    final address = _stringValue(data['address_label']);
    final city = _stringValue(data['city']);
    if (address.isEmpty && city.isEmpty) {
      return '-';
    }
    if (address.isEmpty) {
      return city;
    }
    if (city.isEmpty) {
      return address;
    }
    return '$address, $city';
  }

  static String _formatDate(dynamic rawValue) {
    final parsed = DateTime.tryParse(_stringValue(rawValue));
    if (parsed == null) {
      return 'Inconnue';
    }
    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }

  static String? _geopinLabel(dynamic rawGeopin) {
    final coords = _extractLatLng(rawGeopin);
    if (coords == null) {
      return null;
    }
    final (lat, lng) = coords;
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  static String? _geopinMapUrl(dynamic rawGeopin) {
    final coords = _extractLatLng(rawGeopin);
    if (coords == null) {
      return null;
    }
    final (lat, lng) = coords;
    return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  }

  static (double, double)? _extractLatLng(dynamic rawGeopin) {
    final geopin = _asMap(rawGeopin);
    final lat = _toDouble(geopin['lat']);
    final lng = _toDouble(geopin['lng']);
    if (lat == null || lng == null) {
      return null;
    }
    return (lat, lng);
  }

  static double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'approved' => ('Approuve', Colors.green),
      'rejected' => ('Rejete', Colors.red),
      _ => ('En attente', Colors.orange),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
