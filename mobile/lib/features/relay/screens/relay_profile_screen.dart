import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/relay_point.dart';
import '../../../shared/widgets/loading_button.dart';

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
  RelayPoint? _relay;

  @override
  void initState() {
    super.initState();
    _loadRelay();
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
      _relay = RelayPoint.fromJson(res.data as Map<String, dynamic>);
      _nameCtrl.text = _relay!.name;
      _phoneCtrl.text = _relay!.phone;
      _descCtrl.text = _relay?.description ?? '';
      _hoursCtrl.text = _relay?.openingHours?['general'] ?? '';
    } catch (e) {
      debugPrint("Erreur loadRelay: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_relay == null) return;
    
    try {
      final api = ref.read(apiClientProvider);
      await api.updateRelayPoint(_relay!.id, {
        "name": _nameCtrl.text,
        "phone": _phoneCtrl.text,
        "description": _descCtrl.text,
        "opening_hours": {"general": _hoursCtrl.text},
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profil du relais mis à jour avec succès'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil du Relais')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _relay == null
              ? const Center(child: Text('Aucun point relais associé à ce compte.'))
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('Informations publiques', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Ces informations seront visibles par les clients.', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nom du relais', border: OutlineInputBorder()),
                        validator: (v) => v!.isEmpty ? 'Requis' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(labelText: 'Téléphone de contact', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _hoursCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Horaires d\'ouverture', 
                            hintText: 'ex: Lundi - Samedi de 08:00 à 20:00',
                            border: OutlineInputBorder()),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Instructions / Accès (Optionnel)', 
                            hintText: 'ex: Situé à côté de la pharmacie, portail rouge.',
                            border: OutlineInputBorder()),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: LoadingButton(
                          label: 'Enregistrer',
                          onPressed: _save,
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Divider(),
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('Politique de confidentialité'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/legal/privacy_policy'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.gavel_outlined),
                        title: const Text("Conditions Générales d'Utilisation"),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/legal/cgu'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
