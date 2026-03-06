import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/phone_utils.dart';
import '../../../shared/widgets/loading_button.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phoneController = TextEditingController(text: '+221');
  bool _isLoading = false;

  Future<void> _submit() async {
    final phone = normalizePhone(_phoneController.text.trim());
    if (phone.isEmpty || phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Numéro invalide. Format attendu : +221 77 XXX XX XX'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final client = ApiClient();
      final res = await client.checkPhone({'phone': phone});
      final data = res.data as Map<String, dynamic>;

      if (data['exists'] == true && data['has_pin'] == true) {
        if (mounted) {
          context.push('/auth/pin', extra: {'phone': phone});
        }
      } else {
        // Le compte n'existe pas ou n'a pas fini son inscription PIN.
        // On envoie un OTP.
        await ref.read(authProvider.notifier).requestOtp(phone);
        if (mounted) {
          context.push('/auth/otp', extra: {'phone': phone});
        }
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
      appBar: AppBar(title: const Text('Connexion ou Inscription')),
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
              'Entrez votre numéro pour recevoir un code de vérification.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numéro de téléphone',
                hintText: '+221 77 XXX XX XX',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Astuce : vous pouvez saisir votre numéro local (77 XXX XX XX) ou international (+221…).',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: LoadingButton(
                label: 'Recevoir mon code',
                isLoading: _isLoading,
                onPressed: _submit,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
