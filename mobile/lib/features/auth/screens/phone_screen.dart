import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/utils/phone_utils.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phoneController = TextEditingController(text: '+221');
  bool _isLoading = false;

  Future<void> _submit() async {
    // Retirer tous les espaces potentiels insérés par le clavier
    final phone = normalizePhone(_phoneController.text);
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numéro invalide. Format attendu: +221XXXXXXXXX')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ref.read(authProvider.notifier).requestOtp(phone);
      if (mounted) {
        context.push('/auth/otp', extra: phone);
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
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: const Text(
                'Astuce: utilisez votre numéro WhatsApp pour recevoir le code plus facilement.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              autofillHints: const [AutofillHints.telephoneNumber],
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numéro de téléphone',
                hintText: '+221XXXXXXXXX',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
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
