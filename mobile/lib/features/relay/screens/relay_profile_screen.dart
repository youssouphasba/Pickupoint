import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/user.dart';
import '../../../core/models/relay_point.dart';
import '../../../shared/utils/currency_format.dart';
import '../../../shared/widgets/loading_button.dart';
import '../providers/relay_provider.dart';

class RelayProfileScreen extends ConsumerStatefulWidget {
  const RelayProfileScreen({super.key});

  @override
  ConsumerState<RelayProfileScreen> createState() => _RelayProfileScreenState();
}

class _RelayProfileScreenState extends ConsumerState<RelayProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  RelayPoint? _relay;

  @override
  void initState() {
    super.initState();
    _loadRelay();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    _hoursCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRelay() async {
    final user = ref.read(authProvider).valueOrNull?.user;
    if (user?.relayPointId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final api = ref.read(apiClientProvider);
      final res = await api.getRelayPoint(user!.relayPointId!);
      final relay = RelayPoint.fromJson(res.data as Map<String, dynamic>);
      _relay = relay;
      _nameCtrl.text = relay.name;
      _phoneCtrl.text = relay.phone;
      _descCtrl.text = relay.description ?? '';
      _hoursCtrl.text = relay.openingHours?['general']?.toString() ?? '';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur chargement relais: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _relay == null) return;
    setState(() => _isSaving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.updateRelayPoint(_relay!.id, {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'opening_hours': {'general': _hoursCtrl.text.trim()},
      });
      await _loadRelay();
      ref.invalidate(relayWalletProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil du relais mis a jour avec succes.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editAgentAccount(User user) async {
    final emailCtrl = TextEditingController(text: user.email ?? '');
    final bioCtrl = TextEditingController(text: user.bio ?? '');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Modifier le compte agent'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: user.fullName ?? user.phone,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  helperText:
                      'Le nom n est pas modifiable pour des raisons de securite.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: user.phone,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: 'Telephone',
                  helperText:
                      'Le numero principal du compte agent reste verrouille.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: bioCtrl,
                maxLines: 4,
                maxLength: 160,
                decoration: const InputDecoration(
                  labelText: 'Bio agent',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final body = <String, dynamic>{
                  'bio': bioCtrl.text.trim(),
                };
                if (emailCtrl.text.trim().isNotEmpty) {
                  body['email'] = emailCtrl.text.trim();
                }
                await ref.read(apiClientProvider).updateProfile(body);
                await ref.read(authProvider.notifier).fetchMe();
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Compte agent mis a jour.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Mise a jour impossible: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull?.user;
    final walletAsync = ref.watch(relayWalletProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profil du relais')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _relay == null || user == null
              ? const Center(
                  child: Text('Aucun point relais associe a ce compte.'))
              : RefreshIndicator(
                  onRefresh: _loadRelay,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildHeader(user, _relay!),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Compte agent',
                        subtitle:
                            'Informations utiles pour vous identifier et pour le controle admin.',
                        trailing: IconButton(
                          onPressed: () => _editAgentAccount(user),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        child: Column(
                          children: [
                            _infoRow('Nom', user.fullName ?? user.phone),
                            _infoRow('Telephone', user.phone),
                            _infoRow(
                              'E-mail',
                              (user.email ?? '').isEmpty
                                  ? 'Non renseigne'
                                  : user.email!,
                            ),
                            _infoRow('Role', 'Agent relais'),
                            _infoRow('User ID', user.id),
                            _infoRow(
                              'Etat du compte',
                              user.isBanned
                                  ? 'Suspendu'
                                  : (user.isActive ? 'Actif' : 'Inactif'),
                            ),
                            _infoRow('KYC', _kycLabel(user.kycStatus)),
                            if ((user.bio ?? '').trim().isNotEmpty)
                              _infoRow('Bio', user.bio!.trim()),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Fiche publique du point relais',
                        subtitle:
                            'Ces informations sont visibles par les clients lors du choix du relais.',
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nom du relais',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'Nom requis'
                                        : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _phoneCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Telephone de contact',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _hoursCtrl,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  labelText: 'Horaires d ouverture',
                                  hintText: 'Ex: Lun-Sam 8h-20h',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _descCtrl,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: 'Instructions ou acces',
                                  hintText:
                                      'Repere utile pour les clients et les livreurs',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: LoadingButton(
                                  label: 'Enregistrer',
                                  isLoading: _isSaving,
                                  onPressed: _save,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Operationnel',
                        subtitle:
                            'Vue rapide pour piloter le point relais et verifier sa capacite.',
                        child: Column(
                          children: [
                            _infoRow('Adresse', _relay!.addressLabel),
                            _infoRow('Ville', _relay!.city),
                            _infoRow(
                              'Capacite',
                              '${_relay!.currentStock} / ${_relay!.capacity}',
                            ),
                            _infoRow(
                              'Disponibilite',
                              _relay!.isActive ? 'Active' : 'Inactive',
                            ),
                            _infoRow(
                              'Verification',
                              _relay!.isVerified ? 'Verifie' : 'En attente',
                            ),
                            walletAsync.when(
                              data: (wallet) => _infoRow(
                                'Solde relais',
                                formatXof(wallet.balance),
                              ),
                              loading: () => _infoRow(
                                'Solde relais',
                                'Chargement...',
                              ),
                              error: (_, __) =>
                                  _infoRow('Solde relais', 'Indisponible'),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        context.go('/relay/wallet'),
                                    icon: const Icon(Icons.payments_outlined),
                                    label: const Text('Gains'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => context.go('/relay'),
                                    icon:
                                        const Icon(Icons.inventory_2_outlined),
                                    label: const Text('Stock'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Documents et legal',
                        subtitle:
                            'Acces rapide aux documents utiles et informations de conformite.',
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.privacy_tip_outlined),
                              title: const Text('Politique de confidentialite'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/legal/privacy'),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.gavel_outlined),
                              title: const Text('Conditions generales'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push('/legal/cgu'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader(User user, RelayPoint relay) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade800, Colors.orange.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white24,
                child: Icon(Icons.store, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      relay.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      user.fullName ?? user.phone,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(
                label: relay.isVerified ? 'Verifie' : 'Non verifie',
                color: relay.isVerified ? Colors.green : Colors.orange.shade100,
                textColor: relay.isVerified ? Colors.white : Colors.brown,
              ),
              _StatusChip(
                label: relay.isActive ? 'Actif' : 'Inactif',
                color: relay.isActive
                    ? Colors.green.shade700
                    : Colors.grey.shade300,
                textColor: relay.isActive ? Colors.white : Colors.black87,
              ),
              _StatusChip(
                label: '${relay.currentStock}/${relay.capacity} en stock',
                color: Colors.white24,
                textColor: Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _kycLabel(String status) {
    switch (status) {
      case 'verified':
        return 'Verifie';
      case 'pending':
        return 'En attente';
      case 'rejected':
        return 'Rejete';
      default:
        return 'Non fourni';
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
