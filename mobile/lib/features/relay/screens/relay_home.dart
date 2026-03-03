import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/parcel.dart';
import '../../../shared/widgets/parcel_status_badge.dart';
import '../../../shared/widgets/account_switcher.dart';
import '../providers/relay_provider.dart';
import '../../../shared/utils/date_format.dart';

class RelayHome extends ConsumerWidget {
  const RelayHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user         = ref.watch(authProvider).valueOrNull?.user;
    final stockAsync   = ref.watch(relayStockProvider);
    final historyAsync = ref.watch(relayHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(user?.name ?? 'Mon Relais'),
        actions: [
          const AccountSwitcherButton(),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/relay/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(relayStockProvider);
          ref.invalidate(relayHistoryProvider);
        },
        child: stockAsync.when(
          data: (parcels) {
            final pending = parcels.where((p) => p.status == 'redirected_to_relay').toList();
            final inStock = parcels.where((p) => p.status != 'redirected_to_relay').toList();
            final history = historyAsync.valueOrNull ?? [];

            if (parcels.isEmpty && history.isEmpty) return _buildEmptyState();

            return ListView(
              children: [
                if (pending.isNotEmpty) ...[
                  _buildSectionHeader(
                    context,
                    icon: Icons.reply,
                    label: '${pending.length} colis redirigé(s) — à réceptionner',
                    color: Colors.orange,
                    bg: Colors.orange.shade50,
                  ),
                  ...pending.map((p) => _buildPendingCard(context, p)),
                  const SizedBox(height: 8),
                ],
                _buildSectionHeader(
                  context,
                  icon: Icons.inventory,
                  label: '${inStock.length} colis en stock',
                  color: Colors.blue,
                  bg: Colors.blue.shade50,
                ),
                if (inStock.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Stock vide', style: TextStyle(color: Colors.grey))),
                  )
                else
                  ...inStock.map((p) => _buildStockCard(context, ref, p)),

                // ── Historique des colis remis ───────────────────────
                if (history.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildSectionHeader(
                    context,
                    icon: Icons.history,
                    label: '${history.length} colis remis (historique)',
                    color: Colors.grey.shade600,
                    bg: Colors.grey.shade100,
                  ),
                  ...history.map((p) => _buildHistoryCard(context, p)),
                ],

                const SizedBox(height: 100),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, __) => Center(child: Text('Erreur: $e')),
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'scanIn',
            onPressed: () => context.push('/relay/scan-in'),
            label: const Text('Réceptionner'),
            icon: const Icon(Icons.download),
            backgroundColor: Colors.green,
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'scanOut',
            onPressed: () => context.push('/relay/scan-out'),
            label: const Text('Remettre Client'),
            icon: const Icon(Icons.upload),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: bg,
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _buildPendingCard(BuildContext context, Parcel p) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade300, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.reply, color: Colors.orange, size: 16),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Redirigé après échec de livraison',
                    style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w500)),
              ),
              ParcelStatusBadge(status: p.status),
            ]),
            const SizedBox(height: 8),
            Text('Code : ${p.trackingCode}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text('Destinataire : ${p.recipientName ?? '—'}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/relay/scan-in'),
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('Scanner pour confirmer la réception'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Carte standard — cliquable pour voir les détails
  Widget _buildStockCard(BuildContext context, WidgetRef ref, Parcel p) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined, color: Colors.blueGrey),
        title: Text(p.trackingCode,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(p.recipientName ?? '—'),
        trailing: ParcelStatusBadge(status: p.status),
        onTap: () => _showParcelDetail(context, ref, p),
      ),
    );
  }

  void _showParcelDetail(BuildContext context, WidgetRef ref, Parcel p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RelayParcelDetailSheet(parcel: p),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Aucun colis en stock',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('Utilisez le bouton "Réceptionner" pour scanner un colis.'),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, Parcel p) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      color: Colors.grey.shade50,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade50,
          child: Icon(Icons.check_circle_outline, color: Colors.green.shade600, size: 20),
        ),
        title: Text(p.trackingCode,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(p.recipientName ?? '—',
            style: const TextStyle(fontSize: 12)),
        trailing: Text(
          formatDate(p.createdAt),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ),
    );
  }
}

// ─── Bottom sheet détail colis (vue relais) ───────────────────────────────────
class _RelayParcelDetailSheet extends ConsumerStatefulWidget {
  const _RelayParcelDetailSheet({required this.parcel});
  final Parcel parcel;

  @override
  ConsumerState<_RelayParcelDetailSheet> createState() => _RelayParcelDetailSheetState();
}

class _RelayParcelDetailSheetState extends ConsumerState<_RelayParcelDetailSheet> {
  bool    _loadingCode = false;
  String? _pickupCode;          // null = pas encore chargé

  String _modeLabel(String mode) => switch (mode) {
    'relay_to_relay' => 'Relais → Relais',
    'relay_to_home'  => 'Relais → Domicile',
    'home_to_relay'  => 'Domicile → Relais',
    'home_to_home'   => 'Domicile → Domicile',
    _                => mode,
  };

  @override
  Widget build(BuildContext context) {
    final p   = widget.parcel;
    final fmt = DateFormat('d MMM yyyy à HH:mm', 'fr_FR');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          // Poignée
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // En-tête
          Row(children: [
            Expanded(
              child: Text(p.trackingCode,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            ParcelStatusBadge(status: p.status),
          ]),
          const SizedBox(height: 4),
          Text('Créé le ${fmt.format(p.createdAt.toLocal())}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),

          const Divider(height: 28),

          // ── Informations colis ───────────────────────────────────────────
          _sectionTitle('Colis'),
          _infoRow(Icons.local_shipping_outlined, 'Mode', _modeLabel(p.deliveryMode)),
          if (p.weightKg != null)
            _infoRow(Icons.scale_outlined, 'Poids', '${p.weightKg} kg'),
          if (p.declaredValue != null)
            _infoRow(Icons.attach_money, 'Valeur déclarée',
                '${p.declaredValue!.toStringAsFixed(0)} XOF'),
          _infoRow(Icons.verified_user_outlined, 'Assurance',
              p.hasInsurance ? 'Oui' : 'Non'),
          if (p.totalPrice != null)
            _infoRow(Icons.receipt_outlined, 'Frais de port',
                '${p.totalPrice!.toStringAsFixed(0)} XOF'),

          const Divider(height: 28),

          // ── Destinataire ─────────────────────────────────────────────────
          _sectionTitle('Destinataire'),
          _infoRow(Icons.person_outline, 'Nom', p.recipientName ?? '—'),
          _infoRow(Icons.phone_outlined, 'Téléphone', p.recipientPhone ?? '—'),
          if (p.destinationAddress != null)
            _infoRow(Icons.location_on_outlined, 'Adresse', p.destinationAddress!),

          const Divider(height: 28),

          // ── Code livreur (uniquement si en attente de ramassage) ─────────
          if (p.status == 'dropped_at_origin_relay') ...[
            _sectionTitle('Code de collecte livreur'),
            const Text(
              'Le livreur vient récupérer ce colis. Donnez-lui ce code ou montrez-le.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),

            if (_pickupCode == null) ...[
              // Bouton pour charger le code
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loadingCode ? null : _fetchPickupCode,
                  icon: _loadingCode
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.lock_open_outlined),
                  label: Text(_loadingCode ? 'Chargement…' : 'Afficher le code livreur'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ] else ...[
              // ── Code affiché inline dans le bottom sheet ─────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Column(children: [
                  const Text(
                    'Le livreur scanne le QR ou saisit le code.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  // QR Code
                  Container(
                    padding: const EdgeInsets.all(10),
                    color: Colors.white,
                    child: QrImageView(
                      data: _pickupCode!,
                      version: QrVersions.auto,
                      size: 160,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.indigo,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.indigo,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Code numérique
                  Text(
                    _pickupCode!,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 10,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _pickupCode!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copié ✅')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copier le code'),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 8),
          ],

          // ── Bouton remettre au client ─────────────────────────────────────
          if (p.status == 'available_at_relay') ...[
            const Divider(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Fermer le bottom sheet d'abord
                  Navigator.pop(context);
                  // Naviguer directement à l'étape PIN (parcel déjà connu)
                  context.push('/relay/scan-out', extra: {
                    'parcelId':       p.id,
                    'trackingCode':   p.trackingCode,
                    'recipientName':  p.recipientName  ?? '—',
                    'recipientPhone': p.recipientPhone ?? '—',
                  });
                },
                icon: const Icon(Icons.upload),
                label: const Text('Remettre au destinataire'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _fetchPickupCode() async {
    setState(() => _loadingCode = true);
    try {
      final api = ref.read(apiClientProvider);
      final res  = await api.getParcelCodes(widget.parcel.id);
      final data = res.data as Map<String, dynamic>;
      final code = data['pickup_code'] as String?;
      if (mounted) {
        if (code == null || code.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Code introuvable — vérifiez que le colis est bien au statut "Déposé au relais"'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          setState(() => _pickupCode = code);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingCode = false);
    }
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
  );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Icon(icon, size: 18, color: Colors.grey),
      const SizedBox(width: 10),
      SizedBox(
        width: 100,
        child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
      ),
      Expanded(
        child: Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    ]),
  );
}
