import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/auth/auth_provider.dart';
import '../providers/relay_provider.dart';

class ScanInScreen extends ConsumerStatefulWidget {
  const ScanInScreen({super.key});

  @override
  ConsumerState<ScanInScreen> createState() => _ScanInScreenState();
}

class _ScanInScreenState extends ConsumerState<ScanInScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _manualCtrl = TextEditingController();

  bool _isProcessing = false;
  bool _scanPaused   = false;
  bool _isBatchMode  = false;
  final List<String> _batchCodes = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  // ── Entrée commune : caméra ou saisie manuelle ─────────────────────────────
  Future<void> _processCode(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty || _isProcessing) return;

    if (_isBatchMode) {
      if (_batchCodes.contains(trimmed)) {
        _showError('Déjà dans la liste : $trimmed');
        return;
      }
      setState(() {
        _batchCodes.add(trimmed);
      });
      // Petit feedback visuel/sonore ici si possible
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Scanné : $trimmed (${_batchCodes.length})'),
        duration: const Duration(milliseconds: 700),
      ));
      return;
    }

    setState(() { _isProcessing = true; _scanPaused = true; });

    try {
      final api = ref.read(apiClientProvider);
      final res  = await api.trackParcel(trimmed);
      final parcelData = res.data as Map<String, dynamic>;

      final parcelId  = parcelData['parcel_id'] as String? ?? '';
      if (parcelId.isEmpty) {
        _showError('Colis introuvable : $trimmed');
        return;
      }
      final status       = parcelData['status'] as String? ?? '';
      final recipient    = parcelData['recipient_name'] as String? ?? '—';
      final isRedirected = status == 'redirected_to_relay';

      final confirmed = await _showConfirmDialog(
        trackingCode: trimmed,
        recipientName: recipient,
        isRedirected: isRedirected,
      );

      if (confirmed == true) {
        const arriveStatuses = {
          'redirected_to_relay',
          'dropped_at_origin_relay',
          'in_transit',
          'at_destination_relay',
          'out_for_delivery', // H2R : livreur dépose au relais destinataire
        };
        if (isRedirected || arriveStatuses.contains(status)) {
          await api.arriveAtRelay(parcelId);
        } else {
          await api.dropAtRelay(parcelId, {});
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(isRedirected
                ? 'Colis redirigé réceptionné ✅'
                : 'Colis $trimmed réceptionné ✅'),
            backgroundColor: Colors.green,
          ));
          ref.invalidate(relayStockProvider);
        }
      }
    } catch (e) {
      _showError('Erreur : $e');
    } finally {
      if (mounted) setState(() { _isProcessing = false; _scanPaused = false; });
    }
  }

  Future<void> _submitBatch() async {
    if (_batchCodes.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.bulkRelayAction(_batchCodes);
      final data = res.data as Map<String, dynamic>;
      final results = data['results'] as List;

      int successCount = results.where((r) => r['success'] == true).length;
      int failCount = results.length - successCount;

      if (mounted) {
        _showBatchSummary(successCount, failCount, results);
        setState(() {
          _batchCodes.clear();
          _isBatchMode = false;
        });
        ref.invalidate(relayStockProvider);
      }
    } catch (e) {
      _showError('Erreur lors de la validation : $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showBatchSummary(int success, int fail, List results) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Résultat du scan en masse'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$success colis validés avec succès ✅', style: const TextStyle(color: Colors.green)),
            if (fail > 0) ...[
              const SizedBox(height: 8),
              Text('$fail erreurs ❌', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ],
      ),
    );
  }

  // ── Confirmation avant action ──────────────────────────────────────────────
  Future<bool?> _showConfirmDialog({
    required String trackingCode,
    required String recipientName,
    required bool isRedirected,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(isRedirected ? Icons.reply : Icons.download,
              color: isRedirected ? Colors.orange : Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(isRedirected ? 'Colis redirigé' : 'Réceptionner')),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isRedirected) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Text(
                  'Ce colis n\'a pas pu être livré à domicile. Il est redirigé ici.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _infoRow('Code', trackingCode),
            _infoRow('Destinataire', recipientName),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isRedirected ? Colors.orange : Colors.green,
            ),
            child: const Text('Confirmer la réception'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      SizedBox(width: 90,
          child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
      Expanded(child: Text(value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
    ]),
  );

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réceptionner un colis'),
        actions: [
          Row(
            children: [
              const Text('Mode Batch', style: TextStyle(fontSize: 12)),
              Switch(
                value: _isBatchMode,
                onChanged: (v) => setState(() {
                  _isBatchMode = v;
                  if (!v) _batchCodes.clear();
                }),
                activeThumbColor: Colors.white,
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scanner QR'),
            Tab(icon: Icon(Icons.keyboard),        text: 'Saisir le code'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_buildCameraTab(), _buildManualTab()],
      ),
      bottomNavigationBar: _isBatchMode && _batchCodes.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${_batchCodes.length} colis scannés', style: const TextStyle(fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () => setState(() => _batchCodes.clear()),
                          child: const Text('Effacer tout', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _submitBatch,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 16)),
                        child: _isProcessing 
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Valider le lot'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  // ── Onglet 1 : Caméra ─────────────────────────────────────────────────────
  Widget _buildCameraTab() {
    return Stack(children: [
      MobileScanner(
        onDetect: (capture) {
          if (_scanPaused || _isProcessing) return;
          final code = capture.barcodes.firstOrNull?.rawValue;
          if (code != null) _processCode(code);
        },
      ),
      // Viseur
      Center(
        child: Container(
          width: 260, height: 260,
          decoration: BoxDecoration(
            border: Border.all(
              color: _scanPaused ? Colors.orange : Colors.green,
              width: 3,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      if (_isProcessing)
        Container(
          color: Colors.black45,
          child: const Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      Positioned(
        bottom: 48, left: 0, right: 0,
        child: Column(children: [
          const Icon(Icons.qr_code_scanner, color: Colors.white, size: 28),
          const SizedBox(height: 8),
          Text(
            _scanPaused ? 'Traitement…' : 'Scannez le QR affiché sur l\'app client',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold,
              shadows: [Shadow(blurRadius: 4, color: Colors.black)],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'ou utilisez l\'onglet "Saisir le code"',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70, fontSize: 12,
              shadows: [Shadow(blurRadius: 4, color: Colors.black)],
            ),
          ),
        ]),
      ),
    ]);
  }

  // ── Onglet 2 : Saisie manuelle ─────────────────────────────────────────────
  Widget _buildManualTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.blueGrey),
          const SizedBox(height: 24),
          const Text(
            'Entrez le code de suivi du colis',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Demandez au client de dicter le code affiché sur son app (ex: PKP-ABC-1234)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _manualCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Code de suivi *',
              hintText: 'PKP-ABC-1234',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.tag),
            ),
            onSubmitted: (_) => _processCode(_manualCtrl.text),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : () => _processCode(_manualCtrl.text),
            icon: _isProcessing
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: Text(_isProcessing ? 'Recherche…' : 'Réceptionner'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}
