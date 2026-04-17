import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/countries.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/utils/error_utils.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key, this.initialReferralCode});

  final String? initialReferralCode;

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  String _rawNumber = '';
  String _countryCode = '+221';
  bool _isValid = false;
  bool _isLoading = false;

  String get _fullPhone => '$_countryCode$_rawNumber';

  Future<void> _submit() async {
    if (!_isValid || _rawNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Numéro invalide pour le pays sélectionné.'),
        ),
      );
      return;
    }
    final phone = _fullPhone;

    setState(() => _isLoading = true);

    try {
      // D'abord vérifier si l'utilisateur a un PIN configuré
      final client = ApiClient();
      final res = await client.checkPhone({'phone': phone});
      final data = res.data as Map<String, dynamic>;

      if (data['exists'] == true && data['has_pin'] == true) {
        // Utilisateur existant avec PIN → écran PIN
        if (mounted) {
          context.push('/auth/pin', extra: {'phone': phone});
        }
        return;
      }

      // Sinon → Firebase Phone Auth (envoie le SMS)
      await ref.read(authProvider.notifier).startFirebasePhoneAuth(
        phone,
        onCodeSent: (verificationId) {
          if (mounted) {
            context.push('/auth/otp', extra: {
              'phone': phone,
              'verificationId': verificationId,
              'referral_code': widget.initialReferralCode,
            });
          }
        },
        onError: (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur : $error')),
            );
          }
        },
        onAutoVerified: (credential) async {
          // Auto-vérification Android — connecter directement
          try {
            final regToken = await ref
                .read(authProvider.notifier)
                .signInWithFirebaseCredential(credential);
            if (mounted && regToken != null) {
              context.pushReplacement('/auth/setup', extra: {
                'registration_token': regToken,
                'referral_code': widget.initialReferralCode,
              });
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(friendlyError(e))),
              );
            }
          }
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
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
              'Bienvenue sur Denkma',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Entrez votre numéro pour recevoir un code de vérification.',
              style: TextStyle(color: Colors.grey),
            ),
            if ((widget.initialReferralCode ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade100),
                ),
                child: Text(
                  'Code parrainage détecté : ${widget.initialReferralCode!.trim().toUpperCase()}',
                  style: TextStyle(
                    color: Colors.green.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            IntlPhoneField(
              decoration: const InputDecoration(
                labelText: 'Numéro de téléphone',
                border: OutlineInputBorder(),
              ),
              initialCountryCode: 'SN',
              countries: countries
                  .where((country) => const {'SN', 'FR'}.contains(country.code))
                  .toList(),
              invalidNumberMessage: 'Numéro invalide',
              disableLengthCheck: false,
              onChanged: (PhoneNumber phone) {
                setState(() {
                  _rawNumber = phone.number;
                  _countryCode = phone.countryCode;
                  _isValid = phone.isValidNumber();
                });
              },
              onCountryChanged: (country) {
                setState(() {
                  _countryCode = '+${country.dialCode}';
                });
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Denkma est disponible au Sénégal (+221) et en France (+33).',
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
