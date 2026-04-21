import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/parcel.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/widgets/parcel_status_badge.dart';
import '../../../shared/widgets/authenticated_avatar.dart';
import '../../../shared/widgets/state_feedback.dart';
import '../../../shared/widgets/timeline_widget.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key, this.code});

  final String? code;

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  final _searchController = TextEditingController();
  Parcel? _parcel;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.code != null) {
      _searchController.text = widget.code!;
      _track(widget.code!);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _track(String code) async {
    if (code.isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final res = await api.trackParcel(code);
      if (!mounted) return;
      setState(() {
        _parcel = Parcel.fromJson(res.data as Map<String, dynamic>);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Code introuvable ou erreur de connexion.';
        _isLoading = false;
        _parcel = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi de colis')),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _parcel != null
                        ? _buildResult()
                        : _buildEmptyState(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Entrez votre code de suivi',
          suffixIcon: IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _track(_searchController.text.trim()),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (value) => _track(value.trim()),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const EmptyStateView(
      icon: Icons.search_off,
      title: 'Saisissez un code de suivi',
      subtitle:
          'Le code de suivi est partagé au moment de la création du colis.',
    );
  }

  Widget _buildError() {
    return ErrorStateView(
      message: _error!,
      onRetry: _searchController.text.trim().isNotEmpty
          ? () => _track(_searchController.text.trim())
          : null,
    );
  }

  Widget _buildResult() {
    final parcel = _parcel!;
    final hasId = parcel.id.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: hasId
                ? () => context.push('/client/parcel/${parcel.id}')
                : null,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          parcel.trackingCode,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _modeLabel(parcel.deliveryMode),
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ParcelStatusBadge(status: parcel.status),
                  if (hasId) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, color: Colors.blue),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _InfoCard(
            title: 'Résumé',
            children: [
              _infoRow('Expéditeur', parcel.senderName ?? 'Non communiqué'),
              _infoRow(
                  'Destinataire', parcel.recipientName ?? 'Non communiqué'),
              if ((parcel.destinationAddress ?? '').isNotEmpty)
                _infoRow('Destination', parcel.destinationAddress!),
              if (parcel.totalPrice != null)
                _infoRow('Montant', formatXof(parcel.totalPrice!)),
              if (parcel.paymentStatus != null)
                _infoRow('Paiement', _paymentLabel(parcel)),
              if (parcel.etaText != null) _infoRow('ETA', parcel.etaText!),
              if (parcel.distanceText != null)
                _infoRow('Distance restante', parcel.distanceText!),
            ],
          ),
          if (parcel.driverName != null ||
              parcel.driverPhotoUrl != null ||
              parcel.etaText != null) ...[
            const SizedBox(height: 16),
            _buildDriverCard(parcel),
          ],
          const SizedBox(height: 24),
          const Text(
            'Historique du colis',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          parcel.events.isEmpty
              ? const Text(
                  'Aucun evenement enregistre pour l instant.',
                  style: TextStyle(color: Colors.grey),
                )
              : TimelineWidget(events: parcel.events),
        ],
      ),
    );
  }

  Widget _buildDriverCard(Parcel parcel) {
    final photoUrl = parcel.driverPhotoUrl;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Row(
        children: [
          AuthenticatedAvatar(
            imageUrl: photoUrl,
            radius: 22,
            backgroundColor: Colors.white,
            fallback: const Icon(Icons.delivery_dining),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Livreur en charge',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  parcel.driverName ?? 'Livreur assigné',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (parcel.etaText != null)
                  Text(
                    parcel.etaText!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  static String _modeLabel(String mode) {
    switch (mode) {
      case 'relay_to_relay':
        return 'Relais vers relais';
      case 'relay_to_home':
        return 'Relais vers domicile';
      case 'home_to_relay':
        return 'Domicile vers relais';
      case 'home_to_home':
        return 'Domicile vers domicile';
      default:
        return mode;
    }
  }

  static String _paymentLabel(Parcel parcel) {
    if (parcel.whoPays == 'recipient' && parcel.paymentStatus != 'paid') {
      return 'contre-remboursement';
    }
    return parcel.paymentStatus ?? '-';
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}
