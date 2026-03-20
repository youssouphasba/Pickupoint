import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/loading_button.dart';

class SetupProfileScreen extends ConsumerStatefulWidget {
  final String registrationToken;
  final String? initialReferralCode;

  const SetupProfileScreen({
    super.key,
    required this.registrationToken,
    this.initialReferralCode,
  });

  @override
  ConsumerState<SetupProfileScreen> createState() => _SetupProfileScreenState();
}

class _SetupProfileScreenState extends ConsumerState<SetupProfileScreen> {
  final _nameController = TextEditingController();
  final _referralController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _isLoading = false;
  bool _acceptedLegal = false;
  bool _obscurePin = true;

  @override
  void initState() {
    super.initState();
    final initialReferralCode =
        widget.initialReferralCode?.trim().toUpperCase();
    if (initialReferralCode != null && initialReferralCode.isNotEmpty) {
      _referralController.text = initialReferralCode;
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final pin = _pinController.text;
    final confirmPin = _confirmPinController.text;

    if (name.isEmpty) {
      _showError('Veuillez entrer votre prénom/nom');
      return;
    }
    if (pin.length != 4) {
      _showError('Le code PIN doit contenir exactement 4 chiffres');
      return;
    }
    if (pin != confirmPin) {
      _showError('Les codes PIN ne correspondent pas');
      return;
    }
    if (!_acceptedLegal) {
      _showError(
          'Veuillez accepter les CGU et la Politique de confidentialité');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).completeRegistration(
            token: widget.registrationToken,
            name: name,
            pin: pin,
            referralCode: _referralController.text.trim(),
          );
      // AuthProvider va mettre à jour l'état et GoRouter va rediriger automatiquement.
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _referralController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer mon compte')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dernière étape !',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Comment doit-on vous appeler et quel code secret souhaitez-vous utiliser pour vous connecter ?',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Votre prénom et nom',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _referralController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Code parrainage (optionnel)',
                prefixIcon: Icon(Icons.card_giftcard_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            if ((widget.initialReferralCode ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Le code de parrainage a été prérempli depuis votre lien d’invitation.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 24),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: _obscurePin,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Code PIN (4 chiffres)',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscurePin ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPinController,
              keyboardType: TextInputType.number,
              obscureText: _obscurePin,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Confirmer le code PIN',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _acceptedLegal,
              onChanged: (val) => setState(() => _acceptedLegal = val ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Wrap(
                children: [
                  const Text("J'accepte les "),
                  GestureDetector(
                    onTap: () => context.push('/legal/cgu'),
                    child: Text(
                      "CGU",
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const Text(" et la "),
                  GestureDetector(
                    onTap: () => context.push('/legal/privacy'),
                    child: Text(
                      "Politique",
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: LoadingButton(
                label: 'Terminer l\'inscription',
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
