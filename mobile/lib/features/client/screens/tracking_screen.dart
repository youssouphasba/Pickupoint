import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/parcel.dart';
import '../../../shared/widgets/parcel_status_badge.dart';
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

  Future<void> _track(String code) async {
    if (code.isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final res = await api.trackParcel(code);
      if (mounted) {
        setState(() {
          _parcel = Parcel.fromJson(res.data as Map<String, dynamic>);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Code introuvable ou erreur de connexion.';
          _isLoading = false;
          _parcel = null;
        });
      }
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
      color: Theme.of(context).primaryColor.withOpacity(0.05),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Entrez votre code de tracking (ex: PK-XXXX)',
          suffixIcon: IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _track(_searchController.text.trim()),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        onSubmitted: (v) => _track(v.trim()),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Saisissez un code pour voir le statut.'),
          Text('Le code est envoyé à l\'expéditeur.', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  Widget _buildResult() {
    final parcel = _parcel!;
    final hasId  = parcel.id.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête cliquable si on a un parcel_id (client connecté)
          InkWell(
            onTap: hasId ? () => context.push('/client/parcel/${parcel.id}') : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'CODE: ${parcel.trackingCode}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
          const SizedBox(height: 24),
          const Text(
            'Historique du colis',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          parcel.events.isEmpty
              ? const Text(
                  'Aucun événement enregistré pour l\'instant.',
                  style: TextStyle(color: Colors.grey),
                )
              : TimelineWidget(events: parcel.events),
        ],
      ),
    );
  }
}
