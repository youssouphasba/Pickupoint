import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/widgets/loading_button.dart';

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
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
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

class _DriverApplicationForm extends ConsumerStatefulWidget {
  const _DriverApplicationForm();

  @override
  ConsumerState<_DriverApplicationForm> createState() =>
      _DriverApplicationFormState();
}

enum _DriverDocSlot {
  profilePhoto,
  idCardFront,
  idCardBack,
  licenseFront,
  licenseBack,
}

class _DriverApplicationFormState
    extends ConsumerState<_DriverApplicationForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _cniCtrl = TextEditingController();
  final _licCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _picker = ImagePicker();

  String _vehicle = 'moto';
  bool _loading = false;
  File? _profilePhotoFile;
  File? _idCardFrontFile;
  File? _idCardBackFile;
  File? _licenseFrontFile;
  File? _licenseBackFile;
  String? _idCardUrl;
  String? _licenseUrl;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
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
                  Text(
                    'Devenez livreur Denkma',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Livrez des colis a votre rythme et gagnez de l argent. '
                    'Nous verifierons votre permis et votre identite avant validation.',
                    style: TextStyle(fontSize: 13, color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Photo de profil *',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cette photo sera visible par les clients et verifiee par l administration avant activation des missions.',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
            const SizedBox(height: 12),
            _simpleDocPicker(
              label: _hasProfilePhoto
                  ? 'Photo de profil deja ajoutee'
                  : 'Ajouter une photo de profil',
              file: _profilePhotoFile,
              onTap: () => _pickDoc(_DriverDocSlot.profilePhoto),
            ),
            const SizedBox(height: 24),
            _field(_nameCtrl, 'Nom complet *', Icons.person,
                validator: _required),
            const SizedBox(height: 16),
            _field(_cniCtrl, 'Numero CNI (carte d identite) *', Icons.badge,
                validator: _required),
            const SizedBox(height: 16),
            _field(
                _licCtrl, 'Numero de permis de conduire *', Icons.credit_card,
                validator: _required),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _vehicle,
              decoration: const InputDecoration(
                labelText: 'Type de vehicule *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.directions_car),
              ),
              items: const [
                DropdownMenuItem(value: 'moto', child: Text('Moto')),
                DropdownMenuItem(value: 'car', child: Text('Voiture')),
                DropdownMenuItem(value: 'van', child: Text('Camionnette')),
                DropdownMenuItem(
                  value: 'tricycle',
                  child: Text('Tricycle / Jakarta'),
                ),
              ],
              onChanged: (value) => setState(() => _vehicle = value!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _msgCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Message (optionnel)',
                hintText:
                    'Parlez-nous de votre experience, votre quartier de predilection...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.message),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Documents (KYC) *',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Text(
                'Ajoutez le recto et le verso de votre CNI puis de votre permis. '
                'Chaque piece est fusionnee proprement avant envoi pour la verification.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
            ),
            const SizedBox(height: 12),
            _documentSection(
              title: 'Carte d identite',
              subtitle:
                  'Le recto et le verso doivent etre nets, complets et bien cadres.',
              frontLabel: 'Recto',
              backLabel: 'Verso',
              frontGuideAsset: 'assets/kyc_guides/id_card_front.jpg',
              backGuideAsset: 'assets/kyc_guides/id_card_back.jpg',
              frontFile: _idCardFrontFile,
              backFile: _idCardBackFile,
              onPickFront: () => _pickDoc(_DriverDocSlot.idCardFront),
              onPickBack: () => _pickDoc(_DriverDocSlot.idCardBack),
            ),
            const SizedBox(height: 12),
            _documentSection(
              title: 'Permis de conduire',
              subtitle:
                  'Le numero, les dates et les categories doivent rester lisibles.',
              frontLabel: 'Recto',
              backLabel: 'Verso',
              frontGuideAsset: 'assets/kyc_guides/license_front.jpg',
              backGuideAsset: 'assets/kyc_guides/license_back.jpg',
              frontFile: _licenseFrontFile,
              backFile: _licenseBackFile,
              onPickFront: () => _pickDoc(_DriverDocSlot.licenseFront),
              onPickBack: () => _pickDoc(_DriverDocSlot.licenseBack),
            ),
            const SizedBox(height: 28),
            LoadingButton(
              label: 'Envoyer ma candidature',
              isLoading: _loading,
              onPressed: _submit,
              color: Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _simpleDocPicker({
    required String label,
    File? file,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: file == null ? Colors.grey.shade50 : Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: file == null ? Colors.grey.shade300 : Colors.green.shade300,
          ),
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
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    file == null
                        ? 'Cliquer pour choisir'
                        : 'Fichier selectionne : ${_fileName(file)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: file == null ? Colors.grey : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _documentSection({
    required String title,
    required String subtitle,
    required String frontLabel,
    required String backLabel,
    required String frontGuideAsset,
    required String backGuideAsset,
    required File? frontFile,
    required File? backFile,
    required VoidCallback onPickFront,
    required VoidCallback onPickBack,
  }) {
    return Container(
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
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final vertical = constraints.maxWidth < 720;
              final frontWidget = _guidedDocPicker(
                label: frontLabel,
                guideAsset: frontGuideAsset,
                file: frontFile,
                onTap: onPickFront,
              );
              final backWidget = _guidedDocPicker(
                label: backLabel,
                guideAsset: backGuideAsset,
                file: backFile,
                onTap: onPickBack,
              );
              if (vertical) {
                return Column(
                  children: [
                    frontWidget,
                    const SizedBox(height: 12),
                    backWidget,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: frontWidget),
                  const SizedBox(width: 12),
                  Expanded(child: backWidget),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _guidedDocPicker({
    required String label,
    required String guideAsset,
    required File? file,
    required VoidCallback onTap,
  }) {
    final selected = file != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? Colors.green.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.green.shade300 : Colors.grey.shade300,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.photo_camera_back_outlined,
                  color: selected ? Colors.green : Colors.blueGrey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        selected ? Colors.green.shade100 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    selected ? 'Ajoute' : 'Exemple',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.green.shade800
                          : Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1.58,
                child: selected
                    ? Image.file(file, fit: BoxFit.cover)
                    : Image.asset(guideAsset, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              selected
                  ? _fileName(file)
                  : 'Ajoutez une photo nette, bien cadree et sans reflet fort.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.green.shade800 : Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onTap,
                icon: Icon(selected ? Icons.refresh : Icons.upload_file),
                label: Text(selected ? 'Remplacer' : 'Choisir la photo'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDoc(_DriverDocSlot slot) async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) {
      return;
    }
    final file = File(pickedFile.path);
    setState(() {
      switch (slot) {
        case _DriverDocSlot.profilePhoto:
          _profilePhotoFile = file;
          break;
        case _DriverDocSlot.idCardFront:
          _idCardFrontFile = file;
          break;
        case _DriverDocSlot.idCardBack:
          _idCardBackFile = file;
          break;
        case _DriverDocSlot.licenseFront:
          _licenseFrontFile = file;
          break;
        case _DriverDocSlot.licenseBack:
          _licenseBackFile = file;
          break;
      }
    });
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    String? Function(String?)? validator,
  }) {
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

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Champ obligatoire' : null;

  bool get _hasProfilePhoto {
    final url = ref.read(authProvider).valueOrNull?.user?.profilePictureUrl;
    return url != null && url.trim().isNotEmpty;
  }

  String _fileName(File file) => file.path.split(RegExp(r'[\\/]')).last;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!_hasProfilePhoto && _profilePhotoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez ajouter une photo de profil'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_idCardFrontFile == null ||
        _idCardBackFile == null ||
        _licenseFrontFile == null ||
        _licenseBackFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Veuillez ajouter le recto et le verso de chaque document'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    File? mergedIdCardFile;
    File? mergedLicenseFile;

    try {
      final api = ref.read(apiClientProvider);

      if (_profilePhotoFile != null) {
        await api.uploadAvatar(_profilePhotoFile!);
        await ref.read(authProvider.notifier).fetchMe();
      }

      mergedIdCardFile = await _mergeDocumentSides(
        front: _idCardFrontFile!,
        back: _idCardBackFile!,
        prefix: 'driver_id_card',
      );
      mergedLicenseFile = await _mergeDocumentSides(
        front: _licenseFrontFile!,
        back: _licenseBackFile!,
        prefix: 'driver_license',
      );

      final idRes = await api.uploadKyc(mergedIdCardFile, 'id_card');
      _idCardUrl = idRes.data['doc_url'];

      final licRes = await api.uploadKyc(mergedLicenseFile, 'license');
      _licenseUrl = licRes.data['doc_url'];

      await api.applyDriver({
        'full_name': _nameCtrl.text.trim(),
        'id_card_number': _cniCtrl.text.trim(),
        'license_number': _licCtrl.text.trim(),
        'vehicle_type': _vehicle,
        'id_card_url': _idCardUrl,
        'license_url': _licenseUrl,
        'message': _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
      });

      if (!mounted) {
        return;
      }

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Candidature envoyee'),
            ],
          ),
          content: const Text(
            'Votre dossier a ete transmis a l equipe Denkma. '
            'Nous vous contacterons par telephone dans les 48h pour verifier vos pieces.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (mounted) {
        context.go('/client/profile');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      try {
        await mergedIdCardFile?.delete();
      } catch (_) {}
      try {
        await mergedLicenseFile?.delete();
      } catch (_) {}
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<File> _mergeDocumentSides({
    required File front,
    required File back,
    required String prefix,
  }) async {
    final frontBytes = await front.readAsBytes();
    final backBytes = await back.readAsBytes();
    final decodedFront = img.decodeImage(frontBytes);
    final decodedBack = img.decodeImage(backBytes);
    if (decodedFront == null || decodedBack == null) {
      throw Exception('Impossible de lire une des images du document');
    }

    final frontImage = img.bakeOrientation(decodedFront);
    final backImage = img.bakeOrientation(decodedBack);
    final targetHeight =
        frontImage.height > backImage.height ? frontImage.height : backImage.height;
    final normalizedFront = frontImage.height == targetHeight
        ? frontImage
        : img.copyResize(frontImage, height: targetHeight);
    final normalizedBack = backImage.height == targetHeight
        ? backImage
        : img.copyResize(backImage, height: targetHeight);

    const gap = 24;
    const padding = 24;
    final canvas = img.Image(
      width:
          normalizedFront.width + normalizedBack.width + gap + (padding * 2),
      height: targetHeight + (padding * 2),
      numChannels: 3,
    );
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(canvas, normalizedFront, dstX: padding, dstY: padding);
    img.compositeImage(
      canvas,
      normalizedBack,
      dstX: padding + normalizedFront.width + gap,
      dstY: padding,
    );

    final directory = await getTemporaryDirectory();
    final output = File(
      '${directory.path}${Platform.pathSeparator}${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await output.writeAsBytes(img.encodeJpg(canvas, quality: 90), flush: true);
    return output;
  }
}

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
    LatLng initialPos = const LatLng(14.6928, -17.4467);
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
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
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
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (mounted) {
          context.go('/client/profile');
        }
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
