import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/loading_button.dart';

class PinLoginScreen extends ConsumerStatefulWidget {
  final String phone;

  const PinLoginScreen({super.key, required this.phone});

  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen> {
  final _pinController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePin = true;

  Future<void> _submit() async {
    final pin = _pinController.text;
    if (pin.length != 4) {
      _showError('Veuillez entrer votre code PIN à 4 chiffres');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).loginPin(widget.phone, pin);
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startResetPinFlow() async {
    // Étape 1 : demander un OTP
    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).requestOtp(widget.phone);
      if (mounted) {
        _showResetPinDialog();
      }
    } catch (e) {
      if (mounted) _showError('Impossible d\'envoyer le code : $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showResetPinDialog() {
    final otpController = TextEditingController();
    final newPinController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Réinitialiser le PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Un code de vérification a été envoyé au ${widget.phone}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Code OTP',
                  prefixIcon: Icon(Icons.sms),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Nouveau code PIN',
                  prefixIcon: Icon(Icons.lock_reset),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () {
                      otpController.dispose();
                      newPinController.dispose();
                      Navigator.pop(ctx);
                    },
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final otp = otpController.text.trim();
                      final newPin = newPinController.text.trim();
                      if (otp.length < 4 || newPin.length != 4) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('Remplissez tous les champs'),
                              backgroundColor: Colors.red),
                        );
                        return;
                      }
                      setDialogState(() => isSubmitting = true);
                      try {
                        await ref.read(apiClientProvider).resetPin({
                          'phone': widget.phone,
                          'otp': otp,
                          'new_pin': newPin,
                        });
                        otpController.dispose();
                        newPinController.dispose();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'PIN réinitialisé ! Connectez-vous avec votre nouveau code.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSubmitting = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                                content: Text('Erreur : $e'),
                                backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connexion')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ravi de vous revoir !',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Compte: ${widget.phone}',
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: _obscurePin,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Code secret (PIN)',
                hintText: '----',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscurePin ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _startResetPinFlow,
                child: const Text('Code oublié ?'),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: LoadingButton(
                label: 'Se connecter',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
