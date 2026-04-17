import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/utils/error_utils.dart';

/// Écran de candidature partenariat (devenir livreur ou point relais).
class PartnershipScreen extends ConsumerStatefulWidget {
  const PartnershipScreen({super.key});

  @override
  ConsumerState<PartnershipScreen> createState() => _PartnershipScreenState();
}

class _PartnershipScreenState extends ConsumerState<PartnershipScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
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
        title: const Text('Devenir partenaire'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.delivery_dining), text: 'Livreur'),
            Tab(icon: Icon(Icons.store), text: 'Point Relais'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _DriverApplicationForm(),
          _RelayApplicationForm(),
        ],
      ),
    );
  }
}

// ── Formulaire Livreur ───────────────────────────────────────────────────────
class _DriverApplicationForm extends ConsumerStatefulWidget {
  const _DriverApplicationForm();

  @override
  ConsumerState<_DriverApplicationForm> createState() =>
      _DriverApplicationFormState();
}

class _DriverApplicationFormState
    extends ConsumerState<_DriverApplicationForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _cniCtrl = TextEditingController();
  final _licCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  String _vehicle = 'moto';
  bool _loading = false;
  File? _idCardFile;
  File? _licenseFile;
  String? _idCardUrl;
  String? _licenseUrl;

  final _picker = ImagePicker();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cniCtrl.dispose();
    _licCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          // Intro
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Devenez livreur Denkma',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.blue)),
                  SizedBox(height: 6),
                  Text(
                    'Livrez des colis à votre rythme et gagnez de l\'argent. '
                    'Nous vérifierons votre permis et votre identité avant validation.',
                    style: TextStyle(fontSize: 13, color: Colors.blueGrey),
                  ),
                ]),
          ),
          const SizedBox(height: 24),
          _field(_nameCtrl, 'Nom complet *', Icons.person,
              validator: _required),
          const SizedBox(height: 16),
          _field(_cniCtrl, 'Numéro CNI (carte d\'identité) *', Icons.badge,
              validator: _required),
          const SizedBox(height: 16),
          _field(_licCtrl, 'Numéro de permis de conduire *', Icons.credit_card,
              validator: _required),
          const SizedBox(height: 16),
          // Type de véhicule
          DropdownButtonFormField<String>(
            initialValue: _vehicle,
            decoration: const InputDecoration(
              labelText: 'Type de véhicule *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.directions_car),
            ),
            items: const [
              DropdownMenuItem(value: 'moto', child: Text('Moto')),
              DropdownMenuItem(value: 'car', child: Text('Voiture')),
              DropdownMenuItem(value: 'van', child: Text('Camionnette')),
              DropdownMenuItem(
                  value: 'tricycle', child: Text('Tricycle / Jakarta')),
            ],
            onChanged: (v) => setState(() => _vehicle = v!),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _msgCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Message (optionnel)',
              hintText:
                  'Parlez-nous de votre expérience, votre quartier de prédilection…',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.message),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          const Text('Documents (KYC) *',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _docPicker(
            label: 'Photo CNI (Recto/Verso)',
            file: _idCardFile,
            onTap: () => _pickDoc('id_card'),
          ),
          const SizedBox(height: 12),
          _docPicker(
            label: 'Photo Permis de conduire',
            file: _licenseFile,
            onTap: () => _pickDoc('license'),
          ),
          const SizedBox(height: 28),
          LoadingButton(
            label: 'Envoyer ma candidature',
            isLoading: _loading,
            onPressed: _submit,
            color: Colors.blue,
          ),
        ]),
      ),
    );
  }

  Widget _docPicker(
      {required String label, File? file, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: file == null ? Colors.grey.shade50 : Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color:
                  file == null ? Colors.grey.shade300 : Colors.green.shade300),
        ),
        child: Row(
          children: [
            Icon(
              file == null ? Icons.upload_file : Icons.check_circle,
              color: file == null ? Colors.grey : Colors.green,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                  Text(
                    file == null
                        ? 'Cliquer pour choisir'
                        : 'Fichier sélectionné : ${file.path.split('/').last}',
                    style: TextStyle(
                        fontSize: 11,
                        color:
                            file == null ? Colors.grey : Colors.green.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDoc(String type) async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        if (type == 'id_card') {
          _idCardFile = File(pickedFile.path);
        } else {
          _licenseFile = File(pickedFile.path);
        }
      });
    }
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_idCardFile == null || _licenseFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Veuillez uploader la CNI et le Permis'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);

      // 1. Upload des docs d'abord
      final idRes = await api.uploadKyc(_idCardFile!, 'id_card');
      _idCardUrl = idRes.data['doc_url'];

      final licRes = await api.uploadKyc(_licenseFile!, 'license');
      _licenseUrl = licRes.data['doc_url'];

      // 2. Soumission candidature
      await api.applyDriver({
        'full_name': _nameCtrl.text.trim(),
        'id_card_number': _cniCtrl.text.trim(),
        'license_number': _licCtrl.text.trim(),
        'vehicle_type': _vehicle,
        'id_card_url': _idCardUrl,
        'license_url': _licenseUrl,
        'message': _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
      });
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Row(children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Candidature envoyée'),
            ]),
            content: const Text(
              'Votre dossier a été transmis à l\'équipe Denkma. '
              'Nous vous contacterons par téléphone dans les 48h pour vérifier vos pièces.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ── Formulaire Point Relais ──────────────────────────────────────────────────
class _RelayApplicationForm extends ConsumerStatefulWidget {
  const _RelayApplicationForm();

  @override
  ConsumerState<_RelayApplicationForm> createState() =>
      _RelayApplicationFormState();
}

class _RelayApplicationFormState extends ConsumerState<_RelayApplicationForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _cityCtrl = TextEditingController(text: 'Dakar');
  final _regCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController(text: 'Lun-Sam 8h-20h');
  final _msgCtrl = TextEditingController();
  LatLng? _selectedLocation;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _cityCtrl.dispose();
    _regCtrl.dispose();
    _hoursCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ouvrez un Point Relais',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.orange)),
                  SizedBox(height: 6),
                  Text(
                    'Accueillez des colis dans votre boutique et gagnez une commission par colis. '
                    'Un agent Denkma visitera votre local avant validation.',
                    style: TextStyle(fontSize: 13, color: Colors.brown),
                  ),
                ]),
          ),
          const SizedBox(height: 24),
          _field(_nameCtrl, 'Nom de la boutique / du local *', Icons.storefront,
              validator: _required),
          const SizedBox(height: 16),
          _field(_addrCtrl, 'Adresse (quartier, rue…) *', Icons.location_on,
              validator: _required),
          const SizedBox(height: 16),
          _field(_cityCtrl, 'Ville *', Icons.location_city,
              validator: _required),
          const SizedBox(height: 16),
          _field(
              _regCtrl, 'Numéro Registre Commerce (optionnel)', Icons.business),
          const SizedBox(height: 16),
          _field(_hoursCtrl, 'Horaires d\'ouverture *', Icons.access_time,
              validator: _required),
          const SizedBox(height: 16),
          TextFormField(
            controller: _msgCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Message (optionnel)',
              hintText: 'Décrivez votre local, sa capacité de stockage…',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.message),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          // Sélection Location GPS
          InkWell(
            onTap: _pickLocation,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _selectedLocation == null
                    ? Colors.grey.shade50
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _selectedLocation == null
                        ? Colors.grey.shade300
                        : Colors.green.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    _selectedLocation == null
                        ? Icons.add_location_alt
                        : Icons.location_on,
                    color:
                        _selectedLocation == null ? Colors.grey : Colors.green,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedLocation == null
                              ? 'Définir l\'emplacement sur la carte *'
                              : 'Emplacement défini',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _selectedLocation == null
                                ? Colors.black87
                                : Colors.green.shade700,
                          ),
                        ),
                        if (_selectedLocation != null)
                          Text(
                            'Lat: ${_selectedLocation!.latitude.toStringAsFixed(5)}, Lng: ${_selectedLocation!.longitude.toStringAsFixed(5)}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          // Note GPS
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 16, color: Colors.grey),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Une position précise aide les chauffeurs et clients à vous trouver.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send),
            label: Text(_loading ? 'Envoi…' : 'Envoyer ma candidature'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.orange,
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _pickLocation() async {
    LatLng initialPos = const LatLng(14.6928, -17.4467); // Dakar
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      initialPos = LatLng(pos.latitude, pos.longitude);
    } catch (_) {}

    if (!mounted) return;

    final LatLng? picked = await showDialog<LatLng>(
      context: context,
      builder: (ctx) {
        LatLng tempPos = initialPos;
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Position du Point Relais'),
            contentPadding: EdgeInsets.zero,
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition:
                        CameraPosition(target: initialPos, zoom: 15),
                    onCameraMove: (cam) => tempPos = cam.target,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(
                          () => EagerGestureRecognizer()),
                    },
                  ),
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 35),
                      child:
                          Icon(Icons.location_on, color: Colors.red, size: 40),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annuler')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, tempPos),
                child: const Text('Confirmer cette position'),
              ),
            ],
          );
        });
      },
    );

    if (!mounted) return;
    if (picked != null) {
      setState(() => _selectedLocation = picked);
    }
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Veuillez définir l\'emplacement sur la carte'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.applyRelay({
        'business_name': _nameCtrl.text.trim(),
        'address_label': _addrCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'business_reg':
            _regCtrl.text.trim().isEmpty ? null : _regCtrl.text.trim(),
        'opening_hours': _hoursCtrl.text.trim(),
        'message': _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
        'geopin': {
          'lat': _selectedLocation!.latitude,
          'lng': _selectedLocation!.longitude,
        },
      });
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Row(children: [
              Icon(Icons.check_circle, color: Colors.orange),
              SizedBox(width: 8),
              Text('Candidature envoyée'),
            ]),
            content: const Text(
              'Votre dossier a été transmis. Un agent Denkma visitera votre local '
              'pour vérifier l\'emplacement et les conditions de stockage.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
