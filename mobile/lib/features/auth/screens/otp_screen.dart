import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/widgets/otp_input.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  final String? verificationId;
  final String? referralCode;

  const OtpScreen({
    super.key,
    required this.phone,
    this.verificationId,
    this.referralCode,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  bool _isLoading = false;
  int _secondsRemaining = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    setState(() => _secondsRemaining = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _verify(String otp) async {
    setState(() => _isLoading = true);
    try {
      // Firebase OTP verification
      final token =
          await ref.read(authProvider.notifier).verifyFirebaseOtp(otp);

      if (token != null && mounted) {
        context.pushReplacement('/auth/setup', extra: {
          'registration_token': token,
          'referral_code': widget.referralCode,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    if (_secondsRemaining > 0) return;
    try {
      await ref.read(authProvider.notifier).startFirebasePhoneAuth(
        widget.phone,
        onCodeSent: (verificationId) {
          _startTimer();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Code renvoyé')),
            );
          }
        },
        onError: (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error), backgroundColor: Colors.red),
            );
          }
        },
        onAutoVerified: (credential) async {
          try {
            final regToken = await ref
                .read(authProvider.notifier)
                .signInWithFirebaseCredential(credential);
            if (mounted && regToken != null) {
              context.pushReplacement('/auth/setup', extra: {
                'registration_token': regToken,
                'referral_code': widget.referralCode,
              });
            }
          } catch (_) {}
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Validation')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Text(
              'Saisissez le code reçu',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Un code a été envoyé au ${widget.phone}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: const Text(
                'Saisissez les 6 chiffres reçus par SMS.',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            OtpInput(
              onCompleted: _verify,
            ),
            const SizedBox(height: 32),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              TextButton.icon(
                icon: const Icon(Icons.refresh),
                onPressed: _secondsRemaining == 0 ? _resend : null,
                label: Text(
                  _secondsRemaining > 0
                      ? 'Renvoyer le code dans ${_secondsRemaining}s'
                      : 'Renvoyer le code',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
