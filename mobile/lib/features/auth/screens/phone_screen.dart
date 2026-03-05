import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/loading_button.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phoneController = TextEditingController(text: '+221');
  bool _isLoading = false;
  bool _acceptedLegal = false;

  Future<void> _submit() async {
    // Retirer tous les espaces potentiels insérés par le clavier
    final phone = _phoneController.text.replaceAll(' ', '');
    // On s'assure juste que c'est un numéro non vide.
    // L'API s'occupera de la vraie validation si besoin.
    if (phone.isEmpty || phone.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer un numéro valide')),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    // Si déjà accepté, on passe l'info. Sinon, on bloque (ou on force le check avant).
    if (!_acceptedLegal) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veuillez accepter les CGU et la Politique')),
        );
      }
      return;
    }

    try {
      await ref.read(authProvider.notifier).requestOtp(phone);
      if (mounted) {
        context.push('/auth/otp', extra: {
          'phone': phone,
          'accepted_legal': _acceptedLegal,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connexion')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bienvenue sur PickuPoint',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Entrez votre numéro de téléphone pour recevoir un code de validation.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numéro de téléphone',
                hintText: '+221XXXXXXXXX',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
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
                    onTap: () => context.push('/legal/privacy_policy'),
                    child: Text(
                      "Politique de confidentialité",
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
            const Spacer(),
            LoadingButton(
              label: 'Recevoir mon code',
              isLoading: _isLoading,
              onPressed: _submit,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
