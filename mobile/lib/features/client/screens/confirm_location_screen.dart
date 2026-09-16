import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/location/fresh_position_helper.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/map_picker_modal.dart';
import '../../../shared/widgets/success_celebration.dart';
import '../../../shared/feedback/action_feedback.dart';

class ConfirmLocationScreen extends ConsumerStatefulWidget {
  const ConfirmLocationScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<ConfirmLocationScreen> createState() =>
      _ConfirmLocationScreenState();
}

class _ConfirmLocationScreenState extends ConsumerState<ConfirmLocationScreen> {
  bool _isSubmitting = false;
  bool _confirmed = false;
  String? _error;
  double? _pendingLat;
  double? _pendingLng;
  double? _pendingAccuracy;
  String? _pendingAddress;
  bool _pendingWasAdjusted = false;

  Future<void> _prepareLocation() async {
    if (_isSubmitting || _confirmed) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final position = await FreshPositionHelper.getStrictFreshPosition(
        context: 'la préparation de la confirmation de votre position',
      );
      setState(() {
        _pendingLat = position.latitude;
        _pendingLng = position.longitude;
        _pendingAccuracy = position.accuracy;
        _pendingAddress = null;
        _pendingWasAdjusted = false;
        _isSubmitting = false;
      });
      try {
        final response = await ref.read(apiClientProvider).reverseGeocode(
              position.latitude,
              position.longitude,
            );
        final data = response.data as Map<String, dynamic>?;
        final address = data?['address'] as Map<String, dynamic>?;
        final formatted = address?['formatted_address']?.toString().trim();
        if (mounted && formatted != null && formatted.isNotEmpty) {
          setState(() => _pendingAddress = formatted);
        }
      } catch (_) {}
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = friendlyError(error);
      });
    }
  }

  Future<void> _confirmLocation() async {
    if (_isSubmitting || _confirmed || _pendingLat == null || _pendingLng == null) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ref.read(apiClientProvider).confirmLocationByToken(
        widget.token,
        {
          'lat': _pendingLat,
          'lng': _pendingLng,
          'accuracy': _pendingAccuracy,
        },
      );
      if (!mounted) return;
      setState(() {
        _confirmed = true;
        _isSubmitting = false;
      });
      await ActionFeedback.confirm();
      if (mounted) {
        showSuccessCelebration(context, message: 'Position confirmée');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = friendlyError(error);
      });
    }
  }

  Future<void> _editLocation() async {
    if (_pendingLat == null || _pendingLng == null) return;
    final result = await showModalBottomSheet<MapPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MapPickerModal(
        title: 'Vérifier votre position',
        initialPosition: LatLng(_pendingLat!, _pendingLng!),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _pendingLat = result.position.latitude;
      _pendingLng = result.position.longitude;
      _pendingAccuracy = null;
      _pendingAddress = result.address;
      _pendingWasAdjusted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmer ma position')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Image.asset('assets/logo_transparent.png', height: 130),
              const SizedBox(height: 28),
              Text(
                _confirmed ? 'Position confirmée' : 'Votre colis Denkma',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                _confirmed
                    ? 'Le livreur pourra vous trouver à cette position.'
                    : 'Vérifiez la position détectée avant de la confirmer.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              if (_confirmed)
                const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 72,
                )
              else ...[
                if (_pendingLat != null && _pendingLng != null)
                  _buildPendingLocationCard(),
                LoadingButton(
                  label: _pendingLat == null
                      ? 'Détecter ma position'
                      : 'Confirmer cette position',
                  isLoading: _isSubmitting,
                  onPressed: _pendingLat == null
                      ? _prepareLocation
                      : _confirmLocation,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingLocationCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Position détectée',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(_pendingAddress?.isNotEmpty == true
              ? _pendingAddress!
              : 'Adresse indisponible'),
          const SizedBox(height: 4),
          Text(
            _pendingWasAdjusted
                ? 'Position ajustée sur la carte'
                : _pendingAccuracy != null
                    ? 'Précision estimée : ±${_pendingAccuracy!.toStringAsFixed(0)} m'
                    : 'Coordonnées GPS enregistrées',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _editLocation,
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Voir / modifier la carte'),
          ),
        ],
      ),
    );
  }
}
