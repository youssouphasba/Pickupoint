import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/user.dart';
import '../profile/profile_widgets.dart';
import '../profile/unsaved_changes_guard.dart';
import '../utils/error_utils.dart';
import '../widgets/authenticated_avatar.dart';
import '../widgets/support_whatsapp_tile.dart';

class AccountDetailsScreen extends ConsumerStatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  ConsumerState<AccountDetailsScreen> createState() =>
      _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends ConsumerState<AccountDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  late final TextEditingController _bio;
  late String _savedEmail;
  late String _savedBio;
  bool _saving = false;
  bool _uploading = false;
  bool _confirmingExit = false;
  bool _allowExit = false;
  bool _initialized = false;

  bool get _dirty =>
      _email.text.trim() != _savedEmail || _bio.text.trim() != _savedBio;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).valueOrNull?.user;
    _savedEmail = user?.email ?? '';
    _savedBio = user?.bio ?? '';
    _email = TextEditingController(text: _savedEmail)..addListener(_changed);
    _bio = TextEditingController(text: _savedBio)..addListener(_changed);
    _initialized = user != null;
    ref.listenManual(authProvider, (_, next) {
      final loadedUser = next.valueOrNull?.user;
      if (_initialized || loadedUser == null || !mounted) return;
      _savedEmail = loadedUser.email ?? '';
      _savedBio = loadedUser.bio ?? '';
      _email.text = _savedEmail;
      _bio.text = _savedBio;
      _initialized = true;
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _email.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save(User user) async {
    if (_saving || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await ref.read(authProvider.notifier).updateProfile(
            email: _email.text.trim(),
            bio: user.isDriver || user.isRelayAgent ? _bio.text.trim() : null,
          );
      if (!mounted) return;
      setState(() {
        _savedEmail = _email.text.trim();
        _savedBio = _bio.text.trim();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Vos informations ont été enregistrées.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadPhoto() async {
    if (_uploading || _saving) return;
    setState(() => _uploading = true);
    try {
      final photo = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 75);
      if (photo == null || !mounted) return;
      await ref.read(apiClientProvider).uploadAvatar(File(photo.path));
      await ref.read(authProvider.notifier).fetchMe();
      if (!mounted) return;
      final user = ref.read(authProvider).valueOrNull?.user;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
        user?.isDriver == true
            ? 'Photo envoyée. Denkma doit la valider avant votre disponibilité.'
            : 'Photo de profil enregistrée.',
      )));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _leave() async {
    if (_saving || _uploading || _confirmingExit) return;
    _confirmingExit = true;
    final discard = await confirmDiscardChanges(context);
    _confirmingExit = false;
    if (!discard || !mounted) return;
    setState(() => _allowExit = true);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull?.user;
    return PopScope(
      canPop: _allowExit || (!_dirty && !_saving && !_uploading),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Mes informations'),
            actions: const [SupportWhatsAppButton()]),
        body: user == null
            ? const Center(
                child: Text('Connectez-vous pour consulter votre compte.'))
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    ProfileSection(
                        title: 'Photo de profil',
                        child: Column(children: [
                          AuthenticatedAvatar(
                              imageUrl:
                                  user.profilePictureUrl ?? user.avatarUrl,
                              radius: 42,
                              fallback:
                                  const Icon(Icons.person_outline, size: 42)),
                          const SizedBox(height: 12),
                          if (user.isDriver) ...[
                            Text(profilePhotoLabel(user)),
                            if (user.profilePictureStatus == 'rejected' &&
                                user.profilePictureRejectedReason
                                        ?.trim()
                                        .isNotEmpty ==
                                    true)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child:
                                      Text(user.profilePictureRejectedReason!)),
                          ],
                          OutlinedButton.icon(
                            onPressed:
                                _uploading || _saving ? null : _uploadPhoto,
                            icon: const Icon(Icons.add_a_photo_outlined),
                            label: Text(_uploading
                                ? 'Envoi de la photo…'
                                : 'Modifier ma photo'),
                          ),
                        ])),
                    ProfileSection(
                        title: 'Mes coordonnées',
                        subtitle: user.isRelayAgent
                            ? 'Le téléphone ci-dessous sert à vous connecter. Le numéro public du relais se modifie dans sa fiche.'
                            : 'Le nom et le téléphone de connexion sont protégés. Vous pouvez demander leur correction au support.',
                        child: Column(children: [
                          TextFormField(
                              initialValue: user.name,
                              enabled: false,
                              decoration: const InputDecoration(
                                  labelText: 'Nom complet',
                                  border: OutlineInputBorder())),
                          const SizedBox(height: 16),
                          TextFormField(
                              initialValue: user.phone,
                              enabled: false,
                              decoration: InputDecoration(
                                  labelText: 'Téléphone de connexion',
                                  helperText: user.isPhoneVerified
                                      ? 'Numéro vérifié'
                                      : 'Numéro non vérifié',
                                  border: const OutlineInputBorder())),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _email,
                            enabled: !_saving,
                            keyboardType: TextInputType.emailAddress,
                            maxLength: 254,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                                labelText: 'E-mail (facultatif)',
                                border: OutlineInputBorder()),
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              return email.isEmpty ||
                                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                          .hasMatch(email)
                                  ? null
                                  : 'Saisissez une adresse e-mail valide.';
                            },
                          ),
                          if (user.isDriver || user.isRelayAgent) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                                controller: _bio,
                                enabled: !_saving,
                                maxLines: 3,
                                maxLength: 500,
                                decoration: const InputDecoration(
                                    labelText:
                                        'Présentation professionnelle (facultative)',
                                    helperText:
                                        'Une courte présentation de votre activité.',
                                    border: OutlineInputBorder())),
                          ],
                          const SizedBox(height: 12),
                          FilledButton(
                              onPressed: _saving || _uploading || !_dirty
                                  ? null
                                  : () => _save(user),
                              child: Text(_saving
                                  ? 'Enregistrement…'
                                  : 'Enregistrer mes informations')),
                        ])),
                    ProfileSection(
                        title: 'Corriger mon identité',
                        subtitle:
                            'Pour modifier votre nom ou votre numéro de connexion, contactez le support afin de vérifier votre identité.',
                        child: SupportWhatsAppTile(
                          contentPadding: EdgeInsets.zero,
                          message:
                              'Bonjour, je souhaite corriger mon nom ou mon numéro de connexion Denkma. Mon numéro actuel est ${user.phone}.',
                        )),
                    ProfileSection(
                        title: 'État de mon compte',
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(user.isBanned
                                  ? 'Compte suspendu'
                                  : user.isActive
                                      ? 'Compte actif'
                                      : 'Compte désactivé'),
                              if (user.createdAt != null)
                                Text(
                                    'Membre depuis le ${DateFormat('dd/MM/yyyy').format(user.createdAt!.toLocal())}'),
                            ])),
                  ]),
                ),
              ),
      ),
    );
  }
}
