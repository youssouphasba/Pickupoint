import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/countries.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/token_storage.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/utils/error_utils.dart';
import '../../../shared/utils/phone_utils.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({
    super.key,
    this.initialReferralCode,
    this.initialPhone,
    this.initialTrackingCode,
    this.forcePhoneEntry = false,
  });

  final String? initialReferralCode;
  final String? initialPhone;
  final String? initialTrackingCode;
  final bool forcePhoneEntry;

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  String _rawNumber = '';
  String _countryCode = '+221';
  String _initialCountryIso = 'SN';
  bool _isValid = false;
  bool _isLoading = false;
  bool _showPhoneForm = true;
  String? _rememberedPhone;
  String? _rememberedName;

  String get _fullPhone => '$_countryCode$_rawNumber';

  @override
  void initState() {
    super.initState();
    _applyInitialPhone();
    _loadRememberedAccount();
  }

  Future<void> _loadRememberedAccount() async {
    if (widget.forcePhoneEntry || (widget.initialPhone ?? '').trim().isNotEmpty) {
      return;
    }
    final storage = TokenStorage();
    final phone = await storage.getLastPhone();
    if (!mounted || (phone ?? '').trim().isEmpty) return;
    final name = await storage.getLastName();
    setState(() {
      _rememberedPhone = phone!.trim();
      _rememberedName = name?.trim();
      _showPhoneForm = false;
    });
  }

  void _applyInitialPhone() {
    final digits = (widget.initialPhone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;

    if (digits.startsWith('221') && digits.length > 3) {
      _countryCode = '+221';
      _initialCountryIso = 'SN';
      _rawNumber = digits.substring(3);
    } else if (digits.startsWith('33') && digits.length > 2) {
      _countryCode = '+33';
      _initialCountryIso = 'FR';
      _rawNumber = digits.substring(2);
    } else if (digits.startsWith('0') && digits.length == 10) {
      _countryCode = '+33';
      _initialCountryIso = 'FR';
      _rawNumber = digits.substring(1);
    } else {
      _countryCode = '+221';
      _initialCountryIso = 'SN';
      _rawNumber = digits;
    }
    _isValid = _rawNumber.length >= 8;
  }

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

  Future<void> _continueWithPhone(String phone) async {
    setState(() => _isLoading = true);
    try {
      final client = ApiClient();
      final res = await client.checkPhone({'phone': phone});
      final data = res.data as Map<String, dynamic>;

      if (data['exists'] == true && data['has_pin'] == true) {
        if (mounted) {
          context.push('/auth/pin', extra: {'phone': phone});
        }
        return;
      }

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
            if ((widget.initialPhone ?? '').trim().isNotEmpty ||
                (widget.initialTrackingCode ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Text(
                  [
                    'Numéro destinataire détecté.',
                    if ((widget.initialTrackingCode ?? '').trim().isNotEmpty)
                      'Suivi : ${widget.initialTrackingCode!.trim().toUpperCase()}.',
                    'Après connexion, les colis liés à ce numéro seront visibles dans votre compte.',
                  ].join(' '),
                  style: TextStyle(
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            if (!_showPhoneForm && _rememberedPhone != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.green.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.green.shade100,
                          child: Icon(
                            Icons.verified_user_outlined,
                            color: Colors.green.shade800,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (_rememberedName ?? '').isNotEmpty
                                    ? _rememberedName!
                                    : 'Dernier compte utilisé',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                maskPhone(_rememberedPhone!),
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Pour protéger le compte, vous devrez saisir le PIN ou valider le numéro par SMS.',
                      style: TextStyle(
                        color: Colors.green.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: LoadingButton(
                  label: 'Continuer avec ce compte',
                  isLoading: _isLoading,
                  onPressed: () => _continueWithPhone(_rememberedPhone!),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => setState(() => _showPhoneForm = true),
                  child: const Text('Utiliser un autre numéro'),
                ),
              ),
            ] else ...[
              IntlPhoneField(
                decoration: const InputDecoration(
                  labelText: 'Numéro de téléphone',
                  border: OutlineInputBorder(),
                ),
                initialCountryCode: _initialCountryIso,
                initialValue: _rawNumber,
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
                  Icon(Icons.info_outline,
                      size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Denkma est disponible au Sénégal (+221) et en France (+33).',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ],
            const Spacer(),
            if (_showPhoneForm)
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
