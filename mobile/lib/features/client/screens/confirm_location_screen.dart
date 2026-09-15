import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/location/fresh_position_helper.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/widgets/loading_button.dart';
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

  Future<void> _confirmLocation() async {
    if (_isSubmitting || _confirmed) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final position = await FreshPositionHelper.getStrictFreshPosition(
        context: 'la confirmation de votre position',
      );
      await ref.read(apiClientProvider).confirmLocationByToken(
        widget.token,
        {
          'lat': position.latitude,
          'lng': position.longitude,
          'accuracy': position.accuracy,
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
                    : 'Confirmez votre position actuelle pour permettre la livraison.',
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
              else
                LoadingButton(
                  label: 'Confirmer ma position',
                  isLoading: _isSubmitting,
                  onPressed: _confirmLocation,
                ),
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
}
