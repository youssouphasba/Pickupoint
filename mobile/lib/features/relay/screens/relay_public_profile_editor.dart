import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/relay_point.dart';
import '../../../shared/profile/profile_widgets.dart';
import '../../../shared/profile/unsaved_changes_guard.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/widgets/map_picker_modal.dart';
import '../../../shared/widgets/relay_opening_hours_editor.dart';
import '../../../shared/widgets/support_whatsapp_tile.dart';
import '../../client/providers/client_provider.dart';
import '../providers/relay_provider.dart';

class RelayPublicProfileEditor extends ConsumerStatefulWidget {
  const RelayPublicProfileEditor({super.key});

  @override
  ConsumerState<RelayPublicProfileEditor> createState() =>
      _RelayPublicProfileEditorState();
}

class _RelayPublicProfileEditorState
    extends ConsumerState<RelayPublicProfileEditor> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  RelayPoint? _relay;
  Map<String, dynamic> _hours = normalizeRelayOpeningHours(null);
  LatLng? _position;
  String? _snapshot;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _allowExit = false;
  bool _confirmingExit = false;

  String get _draft => jsonEncode({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'description': _description.text.trim(),
        'address': _address.text.trim(),
        'city': _city.text.trim(),
        'district': _district.text.trim(),
        'lat': _position?.latitude,
        'lng': _position?.longitude,
        'hours': _hours,
      });

  bool get _dirty => _snapshot != null && _snapshot != _draft;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _name,
      _phone,
      _description,
      _address,
      _city,
      _district
    ]) {
      controller.addListener(_changed);
    }
    _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _phone,
      _description,
      _address,
      _city,
      _district
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final relay = await ref.read(relayPointProfileProvider.future);
      if (!mounted) return;
      if (relay == null) {
        setState(() => _error =
            'Aucun point relais n’est rattaché à votre compte. Contactez le support.');
        return;
      }
      _relay = relay;
      _name.text = relay.name;
      _phone.text = relay.phone;
      _description.text = relay.description ?? '';
      _address.text = relay.addressLabel;
      _city.text = relay.city;
      _district.text = relay.district ?? '';
      _position = relay.lat != null && relay.lng != null
          ? LatLng(relay.lat!, relay.lng!)
          : null;
      _hours = normalizeRelayOpeningHours(relay.openingHours);
      _snapshot = _draft;
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickLocation() async {
    final result = await showModalBottomSheet<MapPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MapPickerModal(
          title: 'Emplacement du point relais', initialPosition: _position),
    );
    if (result == null || !mounted) return;
    setState(() {
      _position = result.position;
      if (result.address?.trim().isNotEmpty == true) {
        _address.text = result.address!.trim();
      }
    });
  }

  Future<void> _save() async {
    if (_saving || _relay == null || !_form.currentState!.validate()) return;
    if (!_hours.values
        .any((entry) => entry is Map && entry['enabled'] == true)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Sélectionnez au moins un jour et ses horaires d’ouverture.')));
      return;
    }
    if (_position == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Confirmez l’emplacement précis du relais sur la carte.')));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final point = _relay!;
      final addressChanged = _address.text.trim() != point.addressLabel ||
          _city.text.trim() != point.city ||
          _district.text.trim() != (point.district ?? '') ||
          _position?.latitude != point.lat ||
          _position?.longitude != point.lng;
      final response =
          await ref.read(apiClientProvider).updateRelayPoint(point.id, {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'description': _description.text.trim(),
        'opening_hours': _hours,
        if (addressChanged)
          'address': {
            'label': _address.text.trim(),
            'city': _city.text.trim(),
            'district': _district.text.trim(),
            if (point.addressNotes != null) 'notes': point.addressNotes,
            'geopin': {
              'lat': _position!.latitude,
              'lng': _position!.longitude,
              'source': 'manual'
            },
          },
      });
      if (!mounted) return;
      final saved =
          RelayPoint.fromJson(Map<String, dynamic>.from(response.data as Map));
      _relay = saved;
      _name.text = saved.name;
      _phone.text = saved.phone;
      _description.text = saved.description ?? '';
      _address.text = saved.addressLabel;
      _city.text = saved.city;
      _district.text = saved.district ?? '';
      _position = saved.lat != null && saved.lng != null
          ? LatLng(saved.lat!, saved.lng!)
          : null;
      _hours = normalizeRelayOpeningHours(saved.openingHours);
      _snapshot = _draft;
      ref.invalidate(relayPointProfileProvider);
      ref.invalidate(relayPointsProvider);
      ref.invalidate(relayPerformanceProvider);
      ref.invalidate(relayStockProvider);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Fiche publique enregistrée. Les clients verront ces informations lorsque le relais sera validé et activé.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    if (_saving || _confirmingExit) return;
    _confirmingExit = true;
    final confirmed = await confirmDiscardChanges(context);
    _confirmingExit = false;
    if (!confirmed || !mounted) return;
    setState(() => _allowExit = true);
    Navigator.pop(context);
  }

  Widget _field(TextEditingController controller, String label,
          {int? maxLength,
          bool required = false,
          TextInputType? keyboardType,
          ValueChanged<String>? onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: controller,
          enabled: !_saving,
          maxLength: maxLength,
          keyboardType: keyboardType,
          onChanged: onChanged,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          validator: (value) => required && (value?.trim().isEmpty ?? true)
              ? 'Ce champ est obligatoire.'
              : null,
        ),
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _allowExit || (!_dirty && !_saving),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          appBar: AppBar(
              title: const Text('Ma fiche publique'),
              actions: const [SupportWhatsAppButton()]),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ListView(padding: const EdgeInsets.all(16), children: [
                      ProfileSection(
                          child: ProfileNotice(
                              message: _error!,
                              onRetry: () {
                                ref.invalidate(relayPointProfileProvider);
                                _load();
                              })),
                      const SupportWhatsAppTile(),
                    ])
                  : Form(
                      key: _form,
                      child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ProfileSection(
                                    title:
                                        'Informations visibles par les clients',
                                    subtitle:
                                        'Le téléphone de contact ci-dessous est public. Il ne change pas votre numéro de connexion.',
                                    child: Column(children: [
                                      _field(_name, 'Nom du relais',
                                          required: true, maxLength: 120),
                                      _field(_phone,
                                          'Téléphone de contact du relais',
                                          required: true,
                                          maxLength: 32,
                                          keyboardType: TextInputType.phone),
                                      _field(_description,
                                          'Instructions et accès (facultatif)',
                                          maxLength: 1000),
                                    ])),
                                ProfileSection(
                                    title: 'Adresse et emplacement',
                                    subtitle:
                                        'La position précise sert aux clients et aux livreurs. Après modification de l’adresse, confirmez son emplacement sur la carte.',
                                    child: Column(children: [
                                      _field(_address, 'Adresse du relais',
                                          required: true,
                                          maxLength: 240,
                                          onChanged: (_) =>
                                              setState(() => _position = null)),
                                      _field(_city, 'Ville',
                                          required: true,
                                          maxLength: 120,
                                          onChanged: (_) =>
                                              setState(() => _position = null)),
                                      _field(_district, 'Quartier (facultatif)',
                                          maxLength: 120),
                                      OutlinedButton.icon(
                                          onPressed:
                                              _saving ? null : _pickLocation,
                                          icon: const Icon(Icons.map_outlined),
                                          label: Text(_position == null
                                              ? 'Définir l’emplacement sur la carte'
                                              : 'Emplacement défini · modifier sur la carte')),
                                    ])),
                                ProfileSection(
                                    title: 'Mes jours et horaires',
                                    subtitle:
                                        'Ces horaires déterminent l’affichage ouvert/fermé et la disponibilité du relais pour les nouveaux colis.',
                                    child: IgnorePointer(
                                        ignoring: _saving,
                                        child: RelayOpeningHoursEditor(
                                            value: _hours,
                                            onChanged: (value) => setState(
                                                () => _hours = value)))),
                                FilledButton(
                                    onPressed:
                                        _saving || !_dirty ? null : _save,
                                    child: Text(_saving
                                        ? 'Enregistrement…'
                                        : 'Enregistrer ma fiche publique')),
                                const SizedBox(height: 20),
                                const SupportWhatsAppTile(),
                              ]))),
        ),
      );
}
