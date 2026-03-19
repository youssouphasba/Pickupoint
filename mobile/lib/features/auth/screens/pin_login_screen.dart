import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/loading_button.dart';

class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key, required this.phone});

  final String phone;

  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen> {
  final _pinController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePin = true;
  bool _resetDialogOpen = false;

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.length != 4) {
      _showError('Veuillez entrer votre code PIN a 4 chiffres');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).loginPin(widget.phone, pin);
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startResetPinFlow() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await fb.FirebaseAuth.instance.setLanguageCode('fr');
      await fb.FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) {
          if (!mounted || _resetDialogOpen) return;
          _resetDialogOpen = true;
          _openResetDialog(autoCredential: credential);
        },
        verificationFailed: (error) {
          if (!mounted) return;
          _showError(error.message ?? 'Verification impossible.');
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted || _resetDialogOpen) return;
          _resetDialogOpen = true;
          _openResetDialog(verificationId: verificationId);
        },
        codeAutoRetrievalTimeout: (_) {},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification lancee. Entrez le code recu ou choisissez votre nouveau PIN.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Impossible de lancer la verification : $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openResetDialog({
    String? verificationId,
    fb.PhoneAuthCredential? autoCredential,
  }) {
    final otpController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    bool obscure = true;
    bool isSubmitting = false;
    String? errorText;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Reinitialiser le PIN'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  autoCredential != null
                      ? 'Votre numero a ete verifie automatiquement. Choisissez un nouveau code PIN.'
                      : 'Un code de verification a ete envoye au ${widget.phone}.',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                if (verificationId != null) ...[
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Code SMS',
                      prefixIcon: Icon(Icons.sms_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: newPinController,
                  keyboardType: TextInputType.number,
                  obscureText: obscure,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Nouveau code PIN',
                    prefixIcon: const Icon(Icons.lock_reset_outlined),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setDialogState(() => obscure = !obscure),
                      icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPinController,
                  keyboardType: TextInputType.number,
                  obscureText: obscure,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Confirmer le code PIN',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final smsCode = otpController.text.trim();
                      final newPin = newPinController.text.trim();
                      final confirmPin = confirmPinController.text.trim();

                      if (verificationId != null && smsCode.length != 6) {
                        setDialogState(
                          () => errorText =
                              'Entrez les 6 chiffres recus par SMS.',
                        );
                        return;
                      }
                      if (newPin.length != 4) {
                        setDialogState(
                          () => errorText =
                              'Le nouveau PIN doit contenir 4 chiffres.',
                        );
                        return;
                      }
                      if (newPin != confirmPin) {
                        setDialogState(
                          () => errorText =
                              'Les deux codes PIN ne correspondent pas.',
                        );
                        return;
                      }

                      setDialogState(() {
                        errorText = null;
                        isSubmitting = true;
                      });
                      try {
                        final credential = autoCredential ??
                            fb.PhoneAuthProvider.credential(
                              verificationId: verificationId!,
                              smsCode: smsCode,
                            );
                        final userCredential = await fb.FirebaseAuth.instance
                            .signInWithCredential(credential);
                        final idToken =
                            await userCredential.user?.getIdToken(true);
                        if (idToken == null) {
                          throw Exception(
                            'Impossible de valider votre verification.',
                          );
                        }
                        await ref.read(apiClientProvider).resetPinWithFirebase({
                          'id_token': idToken,
                          'new_pin': newPin,
                        });
                        await fb.FirebaseAuth.instance.signOut();
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'PIN reinitialise. Connectez-vous avec votre nouveau code.',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        await fb.FirebaseAuth.instance.signOut();
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          isSubmitting = false;
                          errorText = e.toString();
                        });
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Valider'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      otpController.dispose();
      newPinController.dispose();
      confirmPinController.dispose();
      _resetDialogOpen = false;
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
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
                    _obscurePin ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePin = !_obscurePin),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _startResetPinFlow,
                child: const Text('Code oublie ?'),
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
