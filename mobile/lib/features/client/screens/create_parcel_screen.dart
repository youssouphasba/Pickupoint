import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/relay_point.dart';
import '../providers/client_provider.dart';
import '../../../shared/widgets/loading_button.dart';
import '../widgets/relay_selector_modal.dart';

// ── Enums locaux ───────────────────────────────────────────────────────────────
enum _DestMode { home, relay }
enum _OriginMode { relay, gps }
enum _InitiatedBy { sender, recipient }

class CreateParcelScreen extends ConsumerStatefulWidget {
  const CreateParcelScreen({super.key});

  @override
  ConsumerState<CreateParcelScreen> createState() => _CreateParcelScreenState();
}

class _CreateParcelScreenState extends ConsumerState<CreateParcelScreen> {
  final _pageController = PageController();
  int _currentStep = 0;

  // ── Choix de flux ────────────────────────────────────────────────────────────
  _DestMode   _destMode   = _DestMode.home;
  _OriginMode _originMode = _OriginMode.relay;
  _InitiatedBy _initiatedBy = _InitiatedBy.sender;

  // ── Relais ───────────────────────────────────────────────────────────────────
  RelayPoint? _originRelay;
  RelayPoint? _destinationRelay;

  // ── GPS expéditeur (mode HOME_TO_*) ──────────────────────────────────────────
  double? _originLat;
  double? _originLng;
  double? _originAccuracy;
  bool    _gpsLoading = false;

  // ── Destinataire / Expéditeur (flux inverse) ─────────────────────────────────
  final _recipientNameController  = TextEditingController();
  final _recipientPhoneController = TextEditingController(text: '+221');
  final _senderPhoneController    = TextEditingController(text: '+221');
  final _pickupVoiceNoteController = TextEditingController();
  final _deliveryVoiceNoteController = TextEditingController();

  // ── Adresse domicile destination (relay_to_home / home_to_home) ──────────────
  final _addressLabelController    = TextEditingController();
  final _addressDistrictController = TextEditingController();
  String _addressCity = 'Dakar';

  // ── Étape 3 ──────────────────────────────────────────────────────────────────
  final _weightController = TextEditingController(text: '1.0');
  double _declaredValue  = 10000;
  bool   _hasInsurance   = false;
  bool   _isExpress      = false;
  String _whoPays        = 'sender';   // 'sender' | 'recipient'
  bool   _isQuoteLoading = false;

  // ── Mode de livraison calculé ─────────────────────────────────────────────────
  String get _deliveryMode {
    if (_destMode == _DestMode.home) {
      return _originMode == _OriginMode.relay ? 'relay_to_home' : 'home_to_home';
    } else {
      return _originMode == _OriginMode.relay ? 'relay_to_relay' : 'home_to_relay';
    }
  }

  bool get isReverse => _initiatedBy == _InitiatedBy.recipient;

  @override
  void dispose() {
    _pageController.dispose();
    _recipientNameController.dispose();
    _recipientPhoneController.dispose();
    _senderPhoneController.dispose();
    _pickupVoiceNoteController.dispose();
    _deliveryVoiceNoteController.dispose();
    _addressLabelController.dispose();
    _addressDistrictController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────────
  void _nextStep() {
    if (!_validateCurrentStep()) return;
    if (_currentStep < 2) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentStep++);
    } else {
      _getQuote();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentStep--);
    }
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        final isHomeDelivery = _destMode == _DestMode.home;
        if (isHomeDelivery && _originMode != _OriginMode.gps) {
          _showError('Pour une livraison à domicile, la géolocalisation de l'expéditeur est obligatoire');
          return false;
        }
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
          final who = _initiatedBy == _InitiatedBy.recipient ? 'l\'expéditeur' : 'le destinataire';
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
        return true;
    }
  }

  // ── Capture GPS expéditeur ────────────────────────────────────────────────────
  Future<void> _captureOriginGPS() async {
    setState(() => _gpsLoading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        _showError('Permission GPS refusée. Activez-la dans les paramètres.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));
      setState(() {
        _originLat      = pos.latitude;
        _originLng      = pos.longitude;
        _originAccuracy = pos.accuracy;
      });
    } catch (e) {
      _showError('Impossible d\'obtenir la position GPS.');
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  // ── Devis ────────────────────────────────────────────────────────────────────
  Future<void> _getQuote() async {
    setState(() => _isQuoteLoading = true);
    try {
      final api = ref.read(apiClientProvider);
      final isReverse = _initiatedBy == _InitiatedBy.recipient;
      final authUser  = ref.read(authProvider).value?.user;

      // Destination address (domicile)
      Map<String, dynamic>? deliveryAddress;
      if (_destMode == _DestMode.home) {
        deliveryAddress = {
          'label':    _addressLabelController.text.trim(),
          'district': _addressDistrictController.text.trim().isEmpty
              ? null
              : _addressDistrictController.text.trim(),
          'city': _addressCity,
          'notes': _deliveryVoiceNoteController.text.trim().isEmpty ? null : _deliveryVoiceNoteController.text.trim(),
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
          },
          'city': 'Dakar',
          'notes': _pickupVoiceNoteController.text.trim().isEmpty ? null : _pickupVoiceNoteController.text.trim(),
        };
      }

      final quoteData = {
        'delivery_mode':        _deliveryMode,
        'origin_relay_id':      _originMode == _OriginMode.relay ? _originRelay?.id : null,
        'destination_relay_id': _destMode == _DestMode.relay ? _destinationRelay?.id : null,
        'delivery_address':     deliveryAddress,
        'origin_location':      originLocation,
        'weight_kg':            double.tryParse(_weightController.text) ?? 1.0,
        'is_insured':           _hasInsurance,
        'declared_value':       _declaredValue,
        'is_express':           _isExpress,
        'who_pays':             _whoPays,
        'initiated_by':         isReverse ? 'recipient' : 'sender',
        'pickup_voice_note':     _pickupVoiceNoteController.text.trim().isEmpty ? null : _pickupVoiceNoteController.text.trim(),
        'delivery_voice_note':   _deliveryVoiceNoteController.text.trim().isEmpty ? null : _deliveryVoiceNoteController.text.trim(),
        if (isReverse) 'sender_phone': _senderPhoneController.text.trim(),
        'recipient_name':  isReverse
            ? (authUser?.fullName ?? authUser?.phone ?? '')
            : _recipientNameController.text.trim(),
        'recipient_phone': isReverse
            ? (authUser?.phone ?? '')
            : _recipientPhoneController.text.trim(),
      };

      final res = await api.getQuote(quoteData);
      if (mounted) {
        context.push('/client/quote', extra: {
          'quote':           res.data,
          'formData':        quoteData,
          'recipient_name':  quoteData['recipient_name'],
          'recipient_phone': quoteData['recipient_phone'],
        });
      }
    } catch (e) {
      _showError('Erreur lors du calcul du devis : $e');
    } finally {
      if (mounted) setState(() => _isQuoteLoading = false);
    }
  }

  void _showError(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── Build principal ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    const titles = ['Mode de livraison', 'Destinataire & relais', 'Détails du colis'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_currentStep])),
      body: Column(
        children: [
          _buildStepIndicator(),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: List.generate(3, (i) {
          final isDone    = i < _currentStep;
          final isCurrent = i == _currentStep;
          return Expanded(
            child: Row(children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: isDone || isCurrent
                    ? Theme.of(context).primaryColor
                    : Colors.grey.shade300,
                child: isDone
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text('${i + 1}',
                        style: TextStyle(
                          color: isCurrent ? Colors.white : Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        )),
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
            desc: "Vous êtes l'expéditeur. Un lien GPS peut être envoyé au destinataire.",
            onTap: () => setState(() => _initiatedBy = _InitiatedBy.sender),
          ),
          const SizedBox(height: 10),
          _choiceCard(
            selected: _initiatedBy == _InitiatedBy.recipient,
            icon: Icons.inbox,
            color: const Color(0xFFFF6B00),
            title: "Je veux recevoir un colis",
            desc: "L'expéditeur n'utilise pas l'app. Il recevra un lien pour confirmer son emplacement.",
            onTap: () => setState(() => _initiatedBy = _InitiatedBy.recipient),
          ),

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 20),

          // ── Destination ───────────────────────────
          _sectionTitle(Icons.where_to_vote, isReverse ? 'Vous recevez le colis…' : 'Le colis est livré…'),
          const SizedBox(height: 12),
          _choiceCard(
            selected: _destMode == _DestMode.home,
            icon: Icons.home,
            color: Theme.of(context).primaryColor,
            title: 'À domicile',
            desc: isReverse
                ? 'Le livreur vous livre directement chez vous. En cas d\'absence, redirection vers le relais le plus proche.'
                : 'Le livreur livre directement chez le destinataire. En cas d\'absence, redirection vers le relais le plus proche.',
            onTap: () => setState(() {
              _destMode = _DestMode.home;
              _originMode = _OriginMode.gps;
            }),
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
            onTap: () => setState(() => _destMode = _DestMode.relay),
          ),

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 20),

          // ── Origine ───────────────────────────────
          _sectionTitle(Icons.place, isReverse ? 'L\'expéditeur dépose le colis…' : 'Vous déposez le colis…'),
          const SizedBox(height: 12),
          _choiceCard(
            selected: _originMode == _OriginMode.relay,
            icon: Icons.store_mall_directory,
            color: Theme.of(context).primaryColor,
            title: 'Dans un point relais',
            desc: isReverse
                ? 'L\'expéditeur amènera lui-même le colis au relais de son choix.'
                : 'Vous amenez vous-même le colis au relais de votre choix.',
            onTap: () {
              if (_destMode == _DestMode.home) {
                _showError("Pour livraison domicile, utilisez la géolocalisation GPS de l'expéditeur");
                return;
              }
              setState(() {
                _originMode = _OriginMode.relay;
                _originLat  = null;
              });
            },
          ),
          const SizedBox(height: 10),
          _choiceCard(
            selected: _originMode == _OriginMode.gps,
            icon: Icons.location_on,
            color: Theme.of(context).primaryColor,
            title: isReverse ? 'Le livreur va chez l\'expéditeur' : 'Le livreur vient chez vous',
            desc: isReverse
                ? 'Un livreur ira récupérer le colis à la position de l\'expéditeur.'
                : 'Un livreur vient récupérer le colis à votre position.',
            onTap: () => setState(() => _originMode = _OriginMode.gps),
          ),

          // Bouton GPS si mode sélectionné
          if (_originMode == _OriginMode.gps) ...[
            const SizedBox(height: 16),
            _originLat == null
                ? SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _gpsLoading ? null : _captureOriginGPS,
                      icon: _gpsLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.my_location),
                      label: Text(_gpsLoading ? 'Localisation…' : 'Confirmer ma position'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Position capturée ✅',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          Text(
                            '${_originLat!.toStringAsFixed(5)}, ${_originLng!.toStringAsFixed(5)}'
                            '${_originAccuracy != null ? ' (±${_originAccuracy!.toStringAsFixed(0)} m)' : ''}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ]),
                      ),
                      TextButton(
                        onPressed: _captureOriginGPS,
                        child: const Text('Recapturer'),
                      ),
                    ]),
                  ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Étape 2 : Relais + Destinataire ──────────────────────────────────────────
  Widget _buildStep2() {
    final relaysAsync = ref.watch(relayPointsProvider);
    final isReverse   = _initiatedBy == _InitiatedBy.recipient;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                }
              },
              child: Container(
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
                        _originRelay?.displayName ?? 'Appuyez pour choisir le relais de dépôt *',
                        style: TextStyle(
                          fontSize: 16,
                          color: _originRelay == null ? Colors.grey.shade700 : Colors.black87,
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
                }
              },
              child: Container(
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
                        _destinationRelay?.displayName ?? 'Appuyez pour choisir le relais de destination *',
                        style: TextStyle(
                          fontSize: 16,
                          color: _destinationRelay == null ? Colors.grey.shade700 : Colors.black87,
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

          // ── Adresse indicative (mode domicile) ────────────────────────────
          if (_destMode == _DestMode.home) ...[
            _sectionTitle(Icons.home, 'Zone de livraison'),
            const SizedBox(height: 12),
            TextField(
              controller: _addressLabelController,
              decoration: const InputDecoration(
                labelText: 'Adresse indicative (optionnel)',
                hintText: 'Ex: Sacré-Cœur 3, Villa 42',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.pin_drop),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _addressDistrictController,
              decoration: const InputDecoration(
                labelText: 'Quartier (optionnel)',
                hintText: 'Ex: Plateau, Mermoz…',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.map),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _addressCity,
              decoration: const InputDecoration(
                labelText: 'Ville',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_city),
              ),
              items: ['Dakar', 'Thiès', 'Saint-Louis', 'Ziguinchor', 'Kaolack']
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _addressCity = v ?? 'Dakar'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _deliveryVoiceNoteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Instruction vocale destinataire (optionnel)',
                hintText: 'Ex: entrée derrière la boutique, portail vert',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.mic),
              ),
            ),
            const SizedBox(height: 24),
          ],

          const Divider(),
          const SizedBox(height: 16),

          // ── Destinataire / Expéditeur ─────────────────────────────────────
          _sectionTitle(
            isReverse ? Icons.person_pin : Icons.person,
            isReverse ? 'Informations de l\'expéditeur' : 'Informations du destinataire',
          ),
          const SizedBox(height: 12),


          TextField(
            controller: _recipientNameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: isReverse ? 'Nom de l\'expéditeur *' : 'Nom du destinataire *',
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
          const SizedBox(height: 10),
          TextField(
            controller: _pickupVoiceNoteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Instruction vocale expéditeur (optionnel)',
              hintText: 'Ex: appeler en arrivant, 2e étage',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.record_voice_over),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Valeur déclarée', style: TextStyle(fontWeight: FontWeight.w500)),
              Text(
                '${_declaredValue.toInt()} FCFA',
                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
              ),
            ],
          ),
          Slider(
            value: _declaredValue,
            min: 500,
            max: 500000,
            divisions: 100,
            label: '${_declaredValue.toInt()} FCFA',
            onChanged: (v) => setState(() => _declaredValue = v),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: const Text('Ajouter une assurance', style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(
                _hasInsurance
                    ? 'Colis protégé contre la perte et le vol'
                    : 'Protégez votre colis contre la perte ou le vol',
                style: TextStyle(color: _hasInsurance ? Colors.green : Colors.grey),
              ),
              secondary: Icon(Icons.security, color: _hasInsurance ? Colors.green : Colors.grey),
              value: _hasInsurance,
              onChanged: (v) => setState(() => _hasInsurance = v),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Livraison Express', style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(
                _isExpress
                    ? 'Priorité maximale — livraison le plus vite possible (+40 %)'
                    : 'Activez pour une livraison prioritaire',
                style: TextStyle(color: _isExpress ? const Color(0xFFFF6B00) : Colors.grey),
              ),
              secondary: Icon(Icons.bolt, color: _isExpress ? const Color(0xFFFF6B00) : Colors.grey),
              value: _isExpress,
              onChanged: (v) => setState(() => _isExpress = v),
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
                const Text('Récapitulatif', style: TextStyle(fontWeight: FontWeight.bold)),
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
                      : (_addressLabelController.text.isEmpty ? '—' : _addressLabelController.text),
                ),
                _recapRow(
                  _initiatedBy == _InitiatedBy.recipient ? 'Expéditeur' : 'Destinataire',
                  _recipientNameController.text.isEmpty ? '—' : _recipientNameController.text,
                ),
                _recapRow('Express', _isExpress ? 'Oui (+40 %)' : 'Non'),
                _recapRow('Paiement', _whoPays == 'sender' ? 'Expéditeur' : 'Destinataire'),
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
      'relay_to_home'  => 'Relais → Domicile',
      'home_to_relay'  => 'Domicile → Relais',
      'home_to_home'   => 'Domicile → Domicile',
      _                => _deliveryMode,
    };
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(children: [
      Icon(icon, size: 20, color: Theme.of(context).primaryColor),
      const SizedBox(width: 8),
      Expanded(
        child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? color : Colors.grey.shade300, width: 2),
          borderRadius: BorderRadius.circular(12),
          color: selected ? color.withOpacity(0.05) : null,
        ),
        child: Row(children: [
          Icon(icon, size: 30, color: selected ? color : Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 3),
              Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
          if (selected) Icon(Icons.check_circle, color: color),
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
          child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
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
          border: Border.all(color: selected ? color : Colors.grey.shade300, width: 2),
          borderRadius: BorderRadius.circular(12),
          color: selected ? color.withOpacity(0.05) : null,
        ),
        child: Column(children: [
          Icon(icon, size: 28, color: selected ? color : Colors.grey),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: selected ? color : null)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
          if (selected) ...[
            const SizedBox(height: 6),
            Icon(Icons.check_circle, size: 16, color: color),
          ],
        ]),
      ),
    );
  }

  Widget _retryWidget(String message, ProviderBase provider) {
    return Column(children: [
      Text(message, style: const TextStyle(color: Colors.red)),
      TextButton.icon(
        onPressed: () => ref.invalidate(provider),
        icon: const Icon(Icons.refresh),
        label: const Text('Réessayer'),
      ),
    ]);
  }
}
