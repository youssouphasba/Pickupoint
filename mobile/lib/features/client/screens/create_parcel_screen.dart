import 'dart:io';

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/location/fresh_position_helper.dart';
import '../../../core/models/relay_point.dart';
import '../../../core/models/user.dart';
import '../models/create_parcel_prefill.dart';
import '../providers/create_parcel_prefill_provider.dart';
import '../providers/client_provider.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/map_picker_modal.dart';
import '../widgets/relay_selector_modal.dart';
import '../../../shared/utils/error_utils.dart';

// ── Enums locaux ───────────────────────────────────────────────────────────────
enum _DestMode { home, relay }

enum _OriginMode { relay, gps }

enum _InitiatedBy { sender, recipient }

class CreateParcelScreen extends ConsumerStatefulWidget {
  const CreateParcelScreen({super.key, this.prefill});

  final CreateParcelPrefill? prefill;

  @override
  ConsumerState<CreateParcelScreen> createState() => _CreateParcelScreenState();
}

class _CreateParcelScreenState extends ConsumerState<CreateParcelScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  final _originSectionKey = GlobalKey();
  final _destinationSectionKey = GlobalKey();
  final _routeSummaryKey = GlobalKey();
  final _step2PrimaryActionKey = GlobalKey();
  final _step2DestinationRelayKey = GlobalKey();
  final _step2RecipientInfoKey = GlobalKey();

  // ── Choix de flux ────────────────────────────────────────────────────────────
  _DestMode _destMode = _DestMode.home;
  _OriginMode _originMode = _OriginMode.gps;
  _InitiatedBy _initiatedBy = _InitiatedBy.sender;

  // ── Relais ───────────────────────────────────────────────────────────────────
  RelayPoint? _originRelay;
  RelayPoint? _destinationRelay;

  // ── GPS expéditeur (mode HOME_TO_*) ──────────────────────────────────────────
  double? _originLat;
  double? _originLng;
  double? _originAccuracy;
  String? _originAddress;
  bool _originAddressLoading = false;
  bool _originWasAdjusted = false;
  bool _gpsLoading = false;

  // ── Destinataire / Expéditeur (flux inverse) ─────────────────────────────────
  final _recipientNameController = TextEditingController();
  final _recipientPhoneController = TextEditingController(text: '+221');
  final _senderPhoneController = TextEditingController(text: '+221');
  bool _contactsLoading = false;

  // ── Adresse domicile destination (relay_to_home / home_to_home) ──────────────
  final _addressLabelController = TextEditingController();
  final _addressDistrictController = TextEditingController();
  final _addressCityController = TextEditingController();

  // ── Étape 3 ──────────────────────────────────────────────────────────────────
  final _weightController = TextEditingController(text: '1.0');
  final _declaredValueController = TextEditingController();
  final _pickupNoteController = TextEditingController();
  bool _isExpress = false;
  String _whoPays = 'sender'; // 'sender' | 'recipient'
  bool _isQuoteLoading = false;
  File? _parcelPhoto;
  String? _prefillExternalRef;
  String? _prefillDescription;

  // ── Mode de livraison calculé ─────────────────────────────────────────────────
  String get _deliveryMode {
    if (_destMode == _DestMode.home) {
      return _originMode == _OriginMode.relay
          ? 'relay_to_home'
          : 'home_to_home';
    } else {
      return _originMode == _OriginMode.relay
          ? 'relay_to_relay'
          : 'home_to_relay';
    }
  }

  @override
  void initState() {
    super.initState();
    _applyPrefill();
  }

  void _applyPrefill() {
    final prefill = widget.prefill;
    if (prefill == null || !prefill.hasData) {
      return;
    }
    if ((prefill.source ?? '').trim().toLowerCase() == 'stockman') {
      _originMode = _OriginMode.gps;
    }
    final recipientName = (prefill.recipientName ?? '').trim();
    if (recipientName.isNotEmpty) {
      _recipientNameController.text = recipientName;
    }
    final recipientPhone = (prefill.recipientPhone ?? '').trim();
    if (recipientPhone.isNotEmpty) {
      _recipientPhoneController.text = recipientPhone;
    }
    final addressLabel = (prefill.deliveryAddressLabel ?? '').trim();
    if (addressLabel.isNotEmpty) {
      _addressLabelController.text = addressLabel;
      _destMode = _DestMode.home;
    }
    final addressDistrict = (prefill.deliveryAddressDistrict ?? '').trim();
    if (addressDistrict.isNotEmpty) {
      _addressDistrictController.text = addressDistrict;
      _destMode = _DestMode.home;
    }
    final addressCity = (prefill.deliveryAddressCity ?? '').trim();
    if (addressCity.isNotEmpty) {
      _addressCityController.text = addressCity;
      _destMode = _DestMode.home;
    }
    if (prefill.declaredValue != null && prefill.declaredValue! > 0) {
      _declaredValueController.text = prefill.declaredValue!
          .toStringAsFixed(prefill.declaredValue! % 1 == 0 ? 0 : 2);
    }
    _prefillExternalRef = (prefill.externalRef ?? '').trim().isEmpty
        ? null
        : prefill.externalRef!.trim();
    _prefillDescription = (prefill.description ?? '').trim().isEmpty
        ? null
        : prefill.description!.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(pendingCreateParcelPrefillProvider.notifier).state = null;
    });
  }

  bool get isReverse => _initiatedBy == _InitiatedBy.recipient;

  double? _declaredValue() {
    final raw = _declaredValueController.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    final normalized = raw.replaceAll(' ', '').replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }

  Future<void> _pickRecipientFromContacts() async {
    if (_contactsLoading) return;
    setState(() => _contactsLoading = true);

    try {
      final permission = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      final isGranted = permission == PermissionStatus.granted ||
          permission == PermissionStatus.limited;

      if (!isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Autorisez l’accès aux contacts pour choisir un destinataire.',
            ),
            action: SnackBarAction(
              label: 'Réglages',
              onPressed: FlutterContacts.permissions.openSettings,
            ),
          ),
        );
        return;
      }

      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone},
      );
      contacts.sort(
        (a, b) => (a.displayName ?? '').toLowerCase().compareTo(
              (b.displayName ?? '').toLowerCase(),
            ),
      );

      if (!mounted) return;
      setState(() => _contactsLoading = false);

      final selection = await showModalBottomSheet<_ContactSelection>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ContactPickerSheet(contacts: contacts),
      );
      if (selection == null || !mounted) return;

      setState(() {
        if (selection.name.isNotEmpty) {
          _recipientNameController.text = selection.name;
        }
        _recipientPhoneController.text = _cleanContactPhone(selection.phone);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d’ouvrir les contacts pour le moment.'),
        ),
      );
    } finally {
      if (mounted && _contactsLoading) {
        setState(() => _contactsLoading = false);
      }
    }
  }

  String _cleanContactPhone(String phone) {
    final cleaned = phone.trim().replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('00')) {
      return '+${cleaned.substring(2)}';
    }
    return cleaned;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _recipientNameController.dispose();
    _recipientPhoneController.dispose();
    _senderPhoneController.dispose();
    _addressLabelController.dispose();
    _addressDistrictController.dispose();
    _addressCityController.dispose();
    _weightController.dispose();
    _declaredValueController.dispose();
    _pickupNoteController.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────────
  void _nextStep() {
    if (!_validateCurrentStep()) return;
    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ).then((_) {
        if (_currentStep == 1) _scrollTo(_step2PrimaryActionKey);
      });
      setState(() => _currentStep++);
    } else {
      _getQuote();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentStep--);
    }
  }

  void _scrollTo(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.12,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (_originMode == _OriginMode.gps && _originLat == null) {
          _showError('Veuillez capturer votre position GPS');
          return false;
        }
        return true;
      case 1:
        if (_originMode == _OriginMode.relay && _originRelay == null) {
          _showError('Veuillez choisir un point relais de départ');
          return false;
        }
        if (_destMode == _DestMode.relay && _destinationRelay == null) {
          _showError('Veuillez choisir un point relais d\'arrivée');
          return false;
        }
        // if (_destMode == _DestMode.home && _addressLabelController.text.trim().isEmpty) {
        //   _showError('Veuillez saisir une adresse de livraison indicative');
        //   return false;
        // }
        if (_recipientNameController.text.trim().isEmpty) {
          final who = _initiatedBy == _InitiatedBy.recipient
              ? 'l\'expéditeur'
              : 'le destinataire';
          _showError('Veuillez saisir le nom de $who');
          return false;
        }
        if (_initiatedBy == _InitiatedBy.sender &&
            _recipientPhoneController.text.trim().length < 10) {
          _showError('Numéro de téléphone invalide');
          return false;
        }
        if (_initiatedBy == _InitiatedBy.recipient &&
            _senderPhoneController.text.trim().length < 10) {
          _showError('Numéro de téléphone de l\'expéditeur invalide');
          return false;
        }
        return true;
      default:
        if (_parcelPhoto == null) {
          _showError('Veuillez prendre une photo du colis');
          return false;
        }
        return true;
    }
  }

  Future<void> _takeParcelPhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (image == null) return;
    setState(() => _parcelPhoto = File(image.path));
  }

  // ── Capture GPS expéditeur ────────────────────────────────────────────────────
  Future<void> _captureOriginGPS() async {
    setState(() => _gpsLoading = true);
    try {
      final pos = await FreshPositionHelper.getStrictFreshPosition(
        context: 'la création de la course',
      );
      setState(() {
        _originLat = pos.latitude;
        _originLng = pos.longitude;
        _originAccuracy = pos.accuracy;
        _originAddress = null;
        _originWasAdjusted = false;
      });
      _scrollTo(_destinationSectionKey);
      await _loadOriginAddress(pos.latitude, pos.longitude);
    } catch (e) {
      _showError(friendlyError(e));
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _loadOriginAddress(double lat, double lng) async {
    if (!mounted) return;
    setState(() => _originAddressLoading = true);
    try {
      final response =
          await ref.read(apiClientProvider).reverseGeocode(lat, lng);
      final rawData = response.data;
      final data = rawData is Map ? Map<String, dynamic>.from(rawData) : null;
      final rawAddress = data?['address'];
      final address = rawAddress is Map
          ? Map<String, dynamic>.from(rawAddress)
          : null;
      final formatted = address?['formatted_address']?.toString().trim();
      if (mounted && formatted != null && formatted.isNotEmpty) {
        setState(() => _originAddress = formatted);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _originAddressLoading = false);
    }
  }

  Future<void> _editOriginPosition() async {
    if (_originLat == null || _originLng == null) return;
    final result = await showModalBottomSheet<MapPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MapPickerModal(
        title: 'Vérifier la position de collecte',
        initialPosition: LatLng(_originLat!, _originLng!),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _originLat = result.position.latitude;
      _originLng = result.position.longitude;
      _originAccuracy = null;
      _originAddress = result.address;
      _originAddressLoading = true;
      _originWasAdjusted = true;
    });
    await _loadOriginAddress(result.position.latitude, result.position.longitude);
  }

  // ── Devis ────────────────────────────────────────────────────────────────────
  Future<void> _getQuote() async {
    setState(() => _isQuoteLoading = true);
    try {
      final api = ref.read(apiClientProvider);
      final isReverse = _initiatedBy == _InitiatedBy.recipient;
      final authUser = ref.read(authProvider).value?.user;

      // Destination address (domicile)
      Map<String, dynamic>? deliveryAddress;
      if (_destMode == _DestMode.home) {
        deliveryAddress = {
          'label': _addressLabelController.text.trim(),
          'district': _addressDistrictController.text.trim().isEmpty
              ? null
              : _addressDistrictController.text.trim(),
          if (_addressCityController.text.trim().isNotEmpty)
            'city': _addressCityController.text.trim(),
        };
      }

      // Origin location GPS (HOME_TO_*)
      Map<String, dynamic>? originLocation;
      if (_originMode == _OriginMode.gps && _originLat != null) {
        originLocation = {
          'geopin': {
            'lat': _originLat,
            'lng': _originLng,
            'accuracy': _originAccuracy,
          }
        };
      }

      final declaredValue = _declaredValue();
      final quoteData = {
        'delivery_mode': _deliveryMode,
        'origin_relay_id':
            _originMode == _OriginMode.relay ? _originRelay?.id : null,
        'destination_relay_id':
            _destMode == _DestMode.relay ? _destinationRelay?.id : null,
        'delivery_address': deliveryAddress,
        'origin_location': originLocation,
        'weight_kg': double.tryParse(_weightController.text) ?? 1.0,
        if (declaredValue != null) 'declared_value': declaredValue,
        'is_express': _isExpress,
        'who_pays': _whoPays,
        'initiated_by': isReverse ? 'recipient' : 'sender',
        if (_parcelPhoto != null) 'parcel_photo_path': _parcelPhoto!.path,
        if (_pickupNoteController.text.trim().isNotEmpty)
          'pickup_voice_note': _pickupNoteController.text.trim(),
        if (isReverse) 'sender_phone': _senderPhoneController.text.trim(),
        'recipient_name': isReverse
            ? (authUser?.fullName ?? authUser?.phone ?? '')
            : _recipientNameController.text.trim(),
        'recipient_phone': isReverse
            ? (authUser?.phone ?? '')
            : _recipientPhoneController.text.trim(),
      };
      final createPayload = {
        ...quoteData,
        if ((_prefillExternalRef ?? '').isNotEmpty)
          'external_ref': _prefillExternalRef,
        if ((_prefillDescription ?? '').isNotEmpty)
          'description': _prefillDescription,
      };

      final res = await api.getQuote(quoteData);
      if (mounted) {
        context.push('/client/quote', extra: {
          'quote': res.data,
          'formData': createPayload,
          'recipient_name': quoteData['recipient_name'],
          'recipient_phone': quoteData['recipient_phone'],
        });
      }
    } catch (e) {
      _showError(friendlyError(e));
    } finally {
      if (mounted) setState(() => _isQuoteLoading = false);
    }
  }

  void _showError(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── Build principal ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    const titles = [
      'Mode de livraison',
      'Destinataire & relais',
      'Détails du colis'
    ];
    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Text(
            titles[_currentStep],
            key: ValueKey(_currentStep),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildStepIndicator(),
          if (widget.prefill?.hasData == true)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.local_shipping_outlined,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Commande Stockman importée',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if ((_prefillExternalRef ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Référence : $_prefillExternalRef',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [_buildStep1(), _buildStep2(), _buildStep3()],
            ),
          ),
          _buildBottomButtons(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    const labels = ['Trajet', 'Coordonnées', 'Colis'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          Row(
            children: List.generate(3, (i) {
              final isDone = i < _currentStep;
              final isCurrent = i == _currentStep;
              return Expanded(
                child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone || isCurrent
                          ? Theme.of(context).primaryColor
                          : Colors.grey.shade300,
                    ),
                    child: isDone
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: isCurrent ? Colors.white : Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  if (i < 2)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i < _currentStep
                            ? Theme.of(context).primaryColor
                            : Colors.grey.shade300,
                      ),
                    ),
                ]),
              );
            }),
          ),
          const SizedBox(height: 5),
          Row(
            children: List.generate(
              labels.length,
              (i) => Expanded(
                child: Text(
                  labels[i],
                  textAlign: i == 0
                      ? TextAlign.left
                      : i == labels.length - 1
                          ? TextAlign.right
                          : TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        i == _currentStep ? FontWeight.w700 : FontWeight.w400,
                    color: i <= _currentStep
                        ? Theme.of(context).primaryColor
                        : Colors.grey,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Row(children: [
        if (_currentStep > 0) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: _previousStep,
              child: const Text('Retour'),
            ),
          ),
          const SizedBox(width: 16),
        ],
        Expanded(
          flex: 2,
          child: LoadingButton(
            label: _currentStep == 2 ? 'Voir le devis' : 'Suivant',
            isLoading: _isQuoteLoading,
            onPressed: _nextStep,
          ),
        ),
      ]),
    );
  }

  String _routeSummaryText() {
    final origin = _originMode == _OriginMode.gps ? 'Domicile' : 'Point relais';
    final destination =
        _destMode == _DestMode.home ? 'Domicile' : 'Point relais';
    return '$origin → $destination';
  }

  Widget _buildRouteSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Votre trajet',
            style: TextStyle(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _routeSummaryText(),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          const Text(
            'Choisissez où le livreur récupère le colis et où le destinataire le reçoit.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeDeliveryHelp(bool isReverse) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isReverse
                  ? 'Pour recevoir le colis à domicile, votre nom et votre numéro suffisent. Vous pourrez confirmer votre position ensuite.'
                  : 'Pour livrer à domicile, le nom et le numéro du destinataire suffisent. Vous pouvez l’appeler ou lui demander de confirmer sa position dans l’application ou via le lien WhatsApp reçu.',
              style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }

  // ── Étape 1 : Destination + Origine ──────────────────────────────────────────
  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Qui initie ? ──────────────────────────
          _sectionTitle(Icons.swap_horiz, 'Quelle est votre situation ?'),
          const SizedBox(height: 12),
          _choiceCard(
            selected: _initiatedBy == _InitiatedBy.sender,
            icon: Icons.send,
            color: Theme.of(context).primaryColor,
            title: "J'envoie un colis",
            desc:
                "Vous êtes l'expéditeur. Vous pouvez appeler le destinataire ou lui demander de confirmer sa position dans l'application ou via le lien WhatsApp reçu.",
            onTap: () {
              setState(() => _initiatedBy = _InitiatedBy.sender);
              _scrollTo(_originSectionKey);
            },
          ),
          const SizedBox(height: 10),
          _choiceCard(
            selected: _initiatedBy == _InitiatedBy.recipient,
            icon: Icons.inbox,
            color: const Color(0xFFFF6B00),
            title: "Je veux recevoir un colis",
            desc:
                "L'expéditeur n'utilise pas l'app. Il recevra un lien pour confirmer son emplacement.",
            onTap: () {
              setState(() => _initiatedBy = _InitiatedBy.recipient);
              _scrollTo(_originSectionKey);
            },
          ),

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 20),

          // ── Origine ───────────────────────────────
          KeyedSubtree(
            key: _originSectionKey,
            child: _sectionTitle(
              Icons.place,
              isReverse
                  ? 'L\'expéditeur dépose le colis…'
                  : 'Le livreur récupère le colis…',
            ),
          ),
          const SizedBox(height: 12),
          _choiceCard(
            selected: _originMode == _OriginMode.gps,
            icon: Icons.location_on,
            color: Theme.of(context).primaryColor,
            title:
                isReverse ? 'Le livreur va chez l\'expéditeur' : 'À domicile',
            desc: isReverse
                ? 'Un livreur ira récupérer le colis à la position de l\'expéditeur.'
                : 'Un livreur vient récupérer le colis à votre position.',
            onTap: () {
              setState(() => _originMode = _OriginMode.gps);
              _scrollTo(_destinationSectionKey);
            },
          ),
          const SizedBox(height: 10),
          _choiceCard(
            selected: _originMode == _OriginMode.relay,
            icon: Icons.store_mall_directory,
            color: Theme.of(context).primaryColor,
            title: 'Dans un point relais',
            desc: isReverse
                ? 'L\'expéditeur amènera lui-même le colis au relais de son choix.'
                : 'Vous amenez vous-même le colis au relais de votre choix.',
            onTap: () {
              setState(() {
                _originMode = _OriginMode.relay;
                _originLat = null;
              });
              _scrollTo(_destinationSectionKey);
            },
          ),

          // Bouton GPS si mode sélectionné
          if (_originMode == _OriginMode.gps) ...[
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: _originLat == null
                  ? SizedBox(
                      key: const ValueKey('capture-position'),
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _gpsLoading ? null : _captureOriginGPS,
                        icon: _gpsLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.my_location),
                        label: Text(_gpsLoading
                            ? 'Localisation…'
                            : 'Détecter ma position'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    )
                  : Container(
                      key: const ValueKey('position-captured'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Colors.green),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Position capturée',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green)),
                                    if (_originAddressLoading)
                                      const Text(
                                        'Recherche de l’adresse…',
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.grey),
                                      )
                                    else
                                      Text(
                                        _originAddress ??
                                            'Adresse indisponible',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black87,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _originWasAdjusted
                                          ? 'Position ajustée sur la carte'
                                          : _originAccuracy != null
                                              ? 'Précision estimée : ±${_originAccuracy!.toStringAsFixed(0)} m'
                                              : 'Coordonnées GPS enregistrées',
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.grey),
                                    ),
                                    ExpansionTile(
                                      tilePadding: EdgeInsets.zero,
                                      childrenPadding: EdgeInsets.zero,
                                      dense: true,
                                      title: const Text(
                                        'Voir les coordonnées GPS',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      children: [
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            '${_originLat!.toStringAsFixed(6)}, ${_originLng!.toStringAsFixed(6)}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _editOriginPosition,
                                icon: const Icon(Icons.map_outlined, size: 17),
                                label: const Text('Voir / modifier la carte'),
                              ),
                              TextButton(
                                onPressed: _captureOriginGPS,
                                child: const Text('Recapturer'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ],
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 20),

          // ── Destination ───────────────────────────
          KeyedSubtree(
            key: _destinationSectionKey,
            child: _sectionTitle(
              Icons.where_to_vote,
              isReverse ? 'Vous recevez le colis…' : 'Le colis est livré…',
            ),
          ),
          const SizedBox(height: 12),
          _choiceCard(
            selected: _destMode == _DestMode.home,
            icon: Icons.home,
            color: Theme.of(context).primaryColor,
            title: 'À domicile',
            desc: isReverse
                ? 'Le livreur vous livre directement chez vous. En cas d\'absence, redirection vers le relais le plus proche.'
                : 'Le nom et le numéro du destinataire suffisent. Vous pouvez l’appeler ou lui demander de confirmer sa position dans l’application ou via le lien WhatsApp reçu.',
            onTap: () {
              setState(() => _destMode = _DestMode.home);
              _scrollTo(_routeSummaryKey);
            },
          ),
          const SizedBox(height: 10),
          _choiceCard(
            selected: _destMode == _DestMode.relay,
            icon: Icons.store,
            color: Theme.of(context).primaryColor,
            title: 'En point relais',
            desc: isReverse
                ? 'Vous récupérez le colis au point relais de votre choix.'
                : 'Le destinataire récupère le colis au point relais que vous choisissez pour lui.',
            onTap: () {
              setState(() => _destMode = _DestMode.relay);
              _scrollTo(_routeSummaryKey);
            },
          ),
          const SizedBox(height: 20),
          KeyedSubtree(key: _routeSummaryKey, child: _buildRouteSummary()),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Étape 2 : Relais + Destinataire ──────────────────────────────────────────
  Widget _buildStep2() {
    final isReverse = _initiatedBy == _InitiatedBy.recipient;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFavoriteSelector(),
          if (_destMode == _DestMode.home) ...[
            _buildHomeDeliveryHelp(isReverse),
            const SizedBox(height: 20),
          ],
          const SizedBox(height: 24),

          // ── Relais de départ (uniquement si mode relais) ──────────────────
          if (_originMode == _OriginMode.relay) ...[
            _sectionTitle(Icons.location_on, 'Relais de départ'),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final selected = await showModalBottomSheet<RelayPoint>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const RelaySelectorModal(),
                );
                if (selected != null) {
                  setState(() => _originRelay = selected);
                  _scrollTo(_destMode == _DestMode.relay
                      ? _step2DestinationRelayKey
                      : _step2RecipientInfoKey);
                }
              },
              child: Container(
                key: _originMode == _OriginMode.relay
                    ? _step2PrimaryActionKey
                    : null,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.store, color: Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _originRelay?.displayName ??
                            'Appuyez pour choisir le relais de dépôt *',
                        style: TextStyle(
                          fontSize: 16,
                          color: _originRelay == null
                              ? Colors.grey.shade700
                              : Colors.black87,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Relais de destination (mode relay) ────────────────────────────
          if (_destMode == _DestMode.relay) ...[
            _sectionTitle(Icons.store_mall_directory, 'Relais d\'arrivée'),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final selected = await showModalBottomSheet<RelayPoint>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const RelaySelectorModal(),
                );
                if (selected != null) {
                  setState(() => _destinationRelay = selected);
                  _scrollTo(_step2RecipientInfoKey);
                }
              },
              child: Container(
                key: _originMode == _OriginMode.relay
                    ? _step2DestinationRelayKey
                    : _destMode == _DestMode.relay
                        ? _step2PrimaryActionKey
                        : null,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.store_mall_directory, color: Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _destinationRelay?.displayName ??
                            'Appuyez pour choisir le relais de destination *',
                        style: TextStyle(
                          fontSize: 16,
                          color: _destinationRelay == null
                              ? Colors.grey.shade700
                              : Colors.black87,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          const Divider(),
          const SizedBox(height: 16),

          // ── Destinataire / Expéditeur ─────────────────────────────────────
          _sectionTitle(
            isReverse ? Icons.person_pin : Icons.person,
            isReverse
                ? 'Informations de l\'expéditeur'
                : 'Informations du destinataire',
          ),
          const SizedBox(height: 12),

          if (!isReverse && _destMode == _DestMode.home) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _contactsLoading ? null : _pickRecipientFromContacts,
                icon: _contactsLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.contacts_outlined),
                label: Text(
                  _contactsLoading
                      ? 'Chargement des contacts…'
                      : 'Choisir dans les contacts',
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          TextField(
            key: _originMode == _OriginMode.relay ||
                    _destMode == _DestMode.relay
                ? _step2RecipientInfoKey
                : _step2PrimaryActionKey,
            controller: _recipientNameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: isReverse
                  ? 'Nom de l\'expéditeur *'
                  : 'Nom du destinataire *',
              hintText: isReverse ? 'Ex: Moussa Diop' : 'Ex: Anta Diallo',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),

          if (isReverse)
            TextField(
              controller: _senderPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone de l\'expéditeur *',
                hintText: '+221XXXXXXXXX',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            )
          else
            TextField(
              controller: _recipientPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone du destinataire *',
                hintText: '+221XXXXXXXXX',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Étape 3 : Détails du colis ────────────────────────────────────────────────
  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.inventory_2, 'Caractéristiques du colis'),
          const SizedBox(height: 24),
          TextField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Poids estimé (kg) *',
              hintText: 'Ex: 1.5',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.monitor_weight),
              suffixText: 'kg',
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _declaredValueController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valeur du colis (optionnel)',
              hintText: 'Ex: 10000',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.inventory_rounded),
              suffixText: 'XOF',
            ),
          ),
          const SizedBox(height: 12),
          ref.watch(expressEnabledProvider).maybeWhen(
                data: (enabled) => enabled
                    ? Card(
                        child: SwitchListTile(
                          title: const Text('Livraison Express',
                              style: TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(
                            _isExpress
                                ? 'Priorité maximale — livraison le plus vite possible (+30 %)'
                                : 'Activez pour une livraison prioritaire',
                            style: TextStyle(
                                color: _isExpress
                                    ? const Color(0xFFFF6B00)
                                    : Colors.grey),
                          ),
                          secondary: Icon(Icons.bolt,
                              color: _isExpress
                                  ? const Color(0xFFFF6B00)
                                  : Colors.grey),
                          value: _isExpress,
                          onChanged: (v) => setState(() => _isExpress = v),
                        ),
                      )
                    : const SizedBox.shrink(),
                orElse: () => const SizedBox.shrink(),
              ),
          const SizedBox(height: 20),
          _sectionTitle(
              Icons.edit_note, 'Instructions pour le livreur (optionnel)'),
          const SizedBox(height: 12),
          TextField(
            controller: _pickupNoteController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Instructions de collecte',
              hintText:
                  'Ex: Appeler avant de venir, code portail 1234, 3e étage…',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.note_alt_outlined),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle(Icons.photo_camera_outlined, 'Photo du colis *'),
          const SizedBox(height: 12),
          InkWell(
            onTap: _takeParcelPhoto,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _parcelPhoto == null
                      ? Colors.blueGrey.shade200
                      : Colors.green.shade300,
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _parcelPhoto == null
                        ? Container(
                            width: 72,
                            height: 72,
                            color: Colors.white,
                            child: const Icon(
                              Icons.add_a_photo_outlined,
                              color: Colors.blueGrey,
                            ),
                          )
                        : Image.file(
                            _parcelPhoto!,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _parcelPhoto == null
                              ? 'Prendre une photo'
                              : 'Photo ajoutée',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _parcelPhoto == null
                              ? 'Elle sera visible par l\'expéditeur, le destinataire et l\'admin.'
                              : 'Appuyez pour reprendre la photo.',
                          style: const TextStyle(
                            color: Colors.blueGrey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _parcelPhoto == null
                        ? Icons.chevron_right
                        : Icons.check_circle,
                    color: _parcelPhoto == null
                        ? Colors.blueGrey
                        : Colors.green.shade700,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle(Icons.payment, 'Qui règle la livraison ?'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _payerCard(
                selected: _whoPays == 'sender',
                icon: Icons.send,
                title: "L'expéditeur",
                subtitle: 'Vous payez à la création',
                onTap: () => setState(() => _whoPays = 'sender'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _payerCard(
                selected: _whoPays == 'recipient',
                icon: Icons.inbox,
                title: 'Le destinataire',
                subtitle: 'Paiement à la réception (contre-remboursement)',
                onTap: () => setState(() => _whoPays = 'recipient'),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          // Récapitulatif
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Récapitulatif',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _recapRow('Mode', _deliveryModeLabel()),
                _recapRow(
                  'Départ',
                  _originMode == _OriginMode.relay
                      ? (_originRelay?.name ?? '—')
                      : (_originLat != null ? 'Ma position GPS ✅' : '—'),
                ),
                _recapRow(
                  'Arrivée',
                  _destMode == _DestMode.relay
                      ? (_destinationRelay?.name ?? '—')
                      : (_addressLabelController.text.isEmpty
                          ? '—'
                          : _addressLabelController.text),
                ),
                _recapRow(
                  _initiatedBy == _InitiatedBy.recipient
                      ? 'Expéditeur'
                      : 'Destinataire',
                  _recipientNameController.text.isEmpty
                      ? '—'
                      : _recipientNameController.text,
                ),
                if (_isExpress) _recapRow('Express', 'Oui (+30 %)'),
                _recapRow('Paiement',
                    _whoPays == 'sender' ? 'Expéditeur' : 'Destinataire'),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Helpers UI ────────────────────────────────────────────────────────────────
  String _deliveryModeLabel() {
    return switch (_deliveryMode) {
      'relay_to_relay' => 'Relais → Relais',
      'relay_to_home' => 'Relais → Domicile',
      'home_to_relay' => 'Domicile → Relais',
      'home_to_home' => 'Domicile → Domicile',
      _ => _deliveryMode,
    };
  }

  Future<void> _onFavoriteTap(FavoriteAddress fav) async {
    if (_currentStep != 1) return;
    if (_originMode != _OriginMode.gps) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Les favoris servent à indiquer votre point de départ. Choisissez "Domicile" comme origine.'),
        ),
      );
      return;
    }

    setState(() {
      _originLat = fav.lat;
      _originLng = fav.lng;
      _originAccuracy = 0;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Favori "${fav.name}" appliqué à l\'origine')),
    );
  }

  Widget _buildFavoriteSelector() {
    final user = ref.watch(authProvider).valueOrNull?.user;
    final favorites = user?.favoriteAddresses ?? [];
    if (favorites.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(Icons.bookmark_outline, 'Utiliser un favori'),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: favorites.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final fav = favorites[index];
              return InkWell(
                onTap: () => _onFavoriteTap(fav),
                child: Container(
                  width: 140,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.place, color: Colors.blue, size: 20),
                      const SizedBox(height: 4),
                      Text(
                        fav.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        fav.address,
                        style:
                            const TextStyle(fontSize: 10, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        const Divider(),
      ],
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(children: [
      Icon(icon, size: 20, color: Theme.of(context).primaryColor),
      const SizedBox(width: 8),
      Expanded(
        child: Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    ]);
  }

  Widget _choiceCard({
    required bool selected,
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected ? color : Colors.grey.shade300, width: 2),
          borderRadius: BorderRadius.circular(12),
          color: selected ? color.withValues(alpha: 0.05) : null,
        ),
        child: Row(children: [
          AnimatedScale(
            scale: selected ? 1.08 : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Icon(
              icon,
              size: 30,
              color: selected ? color : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 3),
              Text(desc,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
          SizedBox(
            width: 24,
            height: 24,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: child,
              ),
              child: selected
                  ? Icon(
                      Icons.check_circle,
                      key: const ValueKey('selected'),
                      color: color,
                    )
                  : const SizedBox(
                      key: ValueKey('unselected'),
                      width: 24,
                      height: 24,
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _recapRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ),
        Expanded(
          child: Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ),
      ]),
    );
  }

  Widget _payerCard({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final color = Theme.of(context).primaryColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected ? color : Colors.grey.shade300, width: 2),
          borderRadius: BorderRadius.circular(12),
          color: selected ? color.withValues(alpha: 0.05) : null,
        ),
        child: Column(children: [
          Icon(icon, size: 28, color: selected ? color : Colors.grey),
          const SizedBox(height: 6),
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: selected ? color : null)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center),
          if (selected) ...[
            const SizedBox(height: 6),
            Icon(Icons.check_circle, size: 16, color: color),
          ],
        ]),
      ),
    );
  }
}

class _ContactSelection {
  const _ContactSelection({required this.name, required this.phone});

  final String name;
  final String phone;
}

class _ContactPickerSheet extends StatefulWidget {
  const _ContactPickerSheet({required this.contacts});

  final List<Contact> contacts;

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  final _searchController = TextEditingController();
  late final List<_ContactSelection> _entries;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _entries = [
      for (final contact in widget.contacts)
        for (final phone in contact.phones)
          if (phone.number.trim().isNotEmpty)
            _ContactSelection(
              name: (contact.displayName ?? '').trim(),
              phone: phone.number.trim(),
            ),
    ];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final filtered = query.isEmpty
        ? _entries
        : _entries.where((entry) {
            final searchablePhone =
                entry.phone.replaceAll(RegExp(r'[^\d+]'), '');
            final searchableQuery = query.replaceAll(RegExp(r'[^\d+]'), '');
            return entry.name.toLowerCase().contains(query) ||
                (searchableQuery.isNotEmpty &&
                    searchablePhone.contains(searchableQuery));
          }).toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Choisir un destinataire',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: const InputDecoration(
                hintText: 'Rechercher un nom ou un numéro',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aucun contact avec un numéro de téléphone.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      final initial = entry.name.isEmpty
                          ? '#'
                          : entry.name.characters.first.toUpperCase();
                      return ListTile(
                        leading: CircleAvatar(child: Text(initial)),
                        title: Text(
                          entry.name.isEmpty ? 'Contact sans nom' : entry.name,
                        ),
                        subtitle: Text(entry.phone),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
