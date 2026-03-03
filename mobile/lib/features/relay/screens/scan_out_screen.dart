import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/auth/auth_provider.dart';
import '../providers/relay_provider.dart';

/// Deux étapes :
///   1. Trouver le colis (QR ou saisie manuelle) — ignorée si parcel pré-rempli
///   2. Entrer le PIN (text + scanner QR)
enum _OutStep { findParcel, enterPin }

class ScanOutScreen extends ConsumerStatefulWidget {
  const ScanOutScreen({
    super.key,
    this.prefilledParcelId,
    this.prefilledTrackingCode,
    this.prefilledRecipientName,
    this.prefilledRecipientPhone,
  });

  /// Rempli depuis relay_home → "Remettre au destinataire" (saute l'étape 1)
  final String? prefilledParcelId;
  final String? prefilledTrackingCode;
  final String? prefilledRecipientName;
  final String? prefilledRecipientPhone;

  @override
  ConsumerState<ScanOutScreen> createState() => _ScanOutScreenState();
}

class _ScanOutScreenState extends ConsumerState<ScanOutScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late _OutStep _step;

  // Données colis résolues
  String? _parcelId;
  String? _trackingCode;
  String? _recipientName;
  String? _recipientPhone;

  final _manualTrackingCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  bool _isProcessing = false;
  bool _scanPaused = false; // pour l'onglet caméra (étape 1)

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);

    if (widget.prefilledParcelId != null) {
      _parcelId       = widget.prefilledParcelId;
      _trackingCode   = widget.prefilledTrackingCode;
      _recipientName  = widget.prefilledRecipientName;
      _recipientPhone = widget.prefilledRecipientPhone;
      _step           = _OutStep.enterPin;
    } else {
      _step = _OutStep.findParcel;
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _manualTrackingCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  // ─── Étape 1 : résoudre le code de suivi ─────────────────────────────────
  Future<void> _resolveCode(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty || _isProcessing) return;

    setState(() { _isProcessing = true; _scanPaused = true; });
    try {
      final api  = ref.read(apiClientProvider);
      final res  = await api.trackParcel(trimmed);
      final data = res.data as Map<String, dynamic>;
      final id   = data['parcel_id'] as String? ?? '';

      if (id.isEmpty) {
        _showError('Colis introuvable : $trimmed');
        return;
      }
      if (mounted) {
        setState(() {
          _parcelId       = id;
          _trackingCode   = trimmed;
          _recipientName  = data['recipient_name']  as String? ?? '—';
          _recipientPhone = data['recipient_phone'] as String? ?? '—';
          _step           = _OutStep.enterPin;
          _pinCtrl.clear();
        });
      }
    } catch (e) {
      _showError('Erreur : $e');
    } finally {
      if (mounted) setState(() { _isProcessing = false; _scanPaused = false; });
    }
  }

  // ─── Étape 2 : valider la remise avec le PIN ──────────────────────────────
  Future<void> _confirmHandout() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length != 4) {
      _showError('Le code PIN doit contenir exactement 4 chiffres');
      return;
    }
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.handout(_parcelId!, {'proof_type': 'pin', 'pin_code': pin});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Colis remis au destinataire ✅'),
          backgroundColor: Colors.green,
        ));
        ref.invalidate(relayStockProvider);
        ref.invalidate(relayHistoryProvider);
        Navigator.pop(context);
      }
    } catch (e) {
      _showError('Erreur : $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ─── Scanner QR pour remplir le PIN ──────────────────────────────────────
  void _openPinScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PinScannerSheet(
        onPinDetected: (pin) {
          Navigator.pop(ctx);
          setState(() => _pinCtrl.text = pin);
        },
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) =>
      _step == _OutStep.enterPin ? _buildPinStep() : _buildFindParcelStep();

  // ── Étape 1 : trouver le colis ─────────────────────────────────────────────
  Widget _buildFindParcelStep() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remettre un colis'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scanner QR'),
            Tab(icon: Icon(Icons.keyboard),         text: 'Saisir le code'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_buildCameraTab(), _buildManualTab()],
      ),
    );
  }

  Widget _buildCameraTab() {
    return Stack(children: [
      MobileScanner(
        onDetect: (capture) {
          if (_scanPaused || _isProcessing) return;
          final code = capture.barcodes.firstOrNull?.rawValue;
          if (code != null) _resolveCode(code);
        },
      ),
      Center(
        child: Container(
          width: 260, height: 260,
          decoration: BoxDecoration(
            border: Border.all(
              color: _scanPaused ? Colors.blue : Colors.orange,
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

  Widget _buildManualTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.upload_outlined, size: 64, color: Colors.blueGrey),
          const SizedBox(height: 24),
          const Text(
            'Entrez le code de suivi du colis',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Le client vous dicte le code affiché sur son app (ex : PKP-ABC-1234)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _manualTrackingCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Code de suivi *',
              hintText: 'PKP-ABC-1234',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.tag),
            ),
            onSubmitted: (_) => _resolveCode(_manualTrackingCtrl.text),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : () => _resolveCode(_manualTrackingCtrl.text),
            icon: _isProcessing
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search),
            label: Text(_isProcessing ? 'Recherche…' : 'Chercher le colis'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  // ── Étape 2 : saisie / scan du PIN ────────────────────────────────────────
  Widget _buildPinStep() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmer la remise'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.prefilledParcelId != null) {
              // Pré-rempli depuis le bottom sheet → simple retour arrière
              Navigator.pop(context);
            } else {
              // Retour à l'étape 1
              setState(() {
                _step = _OutStep.findParcel;
                _pinCtrl.clear();
              });
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Carte récapitulatif colis ──────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.inventory_2_outlined, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Colis à remettre',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _infoRow('Code',         _trackingCode   ?? '—'),
                  _infoRow('Destinataire', _recipientName  ?? '—'),
                  _infoRow('Téléphone',    _recipientPhone ?? '—'),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── PIN ────────────────────────────────────────────────────
            const Text(
              'Code PIN du destinataire',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Demandez au client son code PIN à 4 chiffres affiché sur son application.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              autofocus: widget.prefilledParcelId != null,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 12,
              ),
              decoration: InputDecoration(
                labelText: 'Code PIN (4 chiffres)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline),
                counterText: '',
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.green.shade700, width: 2),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Scanner QR du client pour remplir le PIN ───────────────
            OutlinedButton.icon(
              onPressed: _openPinScanner,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scanner le QR code PIN du client'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                foregroundColor: Colors.blueGrey,
              ),
            ),

            const SizedBox(height: 32),

            // ── Bouton confirmer ───────────────────────────────────────
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _confirmHandout,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline),
              label: Text(_isProcessing ? 'Validation…' : 'Valider la remise'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 90,
          child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ]),
    );
  }
}

// ─── Bottom sheet caméra pour scanner le PIN (4 chiffres) ────────────────────
class _PinScannerSheet extends StatefulWidget {
  const _PinScannerSheet({required this.onPinDetected});
  final void Function(String pin) onPinDetected;

  @override
  State<_PinScannerSheet> createState() => _PinScannerSheetState();
}

class _PinScannerSheetState extends State<_PinScannerSheet> {
  bool _detected = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.58,
      child: Column(
        children: [
          // Poignée
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'Scanner le code PIN',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Demandez au client d\'afficher son QR code PIN sur son application.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    if (_detected) return;
                    final raw = (capture.barcodes.firstOrNull?.rawValue ?? '').trim();
                    // On accepte uniquement un code à 4 chiffres
                    if (RegExp(r'^\d{4}$').hasMatch(raw)) {
                      setState(() => _detected = true);
                      widget.onPinDetected(raw);
                    }
                  },
                ),
                Center(
                  child: Container(
                    width: 200, height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _detected ? Colors.green : Colors.orange,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (_detected)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Icon(Icons.check_circle, color: Colors.green, size: 72),
                    ),
                  ),
                Positioned(
                  bottom: 16, left: 0, right: 0,
                  child: Text(
                    _detected ? 'PIN détecté ✅' : 'Cadrez le QR code PIN du client',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 13,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
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
