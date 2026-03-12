import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
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
  final LocalAuthentication _auth = LocalAuthentication();
  bool _isLoading = false;
  bool _obscurePin = true;
  bool _canCheckBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final canCheck = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (canCheck) {
        setState(() => _canCheckBiometrics = true);
        _authenticateBiometric();
      }
    } catch (e) {
      debugPrint("Biometric error: $e");
    }
  }

  Future<void> _authenticateBiometric() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Déverrouillez pour vous connecter',
      );

      if (authenticated) {
        // FIXME: Biometric authentication needs a secure way to hold the PIN 
        // or a dedicated backend token exchange endpoint
        if (mounted) _showError('Biométrie temporairement désactivée. Veuillez utiliser le code PIN.');
      }
    } catch (e) {
      debugPrint("Authentication error: $e");
    }
  }

  Future<void> _submit() async {
    final pin = _pinController.text;
    if (pin.length != 4) {
      _showError('Veuillez entrer votre code PIN à 4 chiffres');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).loginPin(widget.phone, pin);
      // AuthNotifier va rediriger automatiquement l'utilisateur
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
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
                  icon: Icon(_obscurePin ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  // TODO: Lancer le flow OTP pour reset le PIN
                  _showError('Fonction de récupération bientôt disponible');
                },
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
            if (_canCheckBiometrics) ...[
              const SizedBox(height: 24),
              Center(
                child: IconButton(
                  icon: const Icon(Icons.fingerprint, size: 50, color: Colors.blue),
                  onPressed: _authenticateBiometric,
                ),
              ),
              const Center(
                child: Text('Utiliser TouchID / FaceID', style: TextStyle(color: Colors.grey)),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
