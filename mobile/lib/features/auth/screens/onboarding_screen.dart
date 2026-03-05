import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/widgets/loading_button.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameController = TextEditingController();
  String _selectedType = 'individual';
  bool _isLoading = false;

  final List<Map<String, dynamic>> _userTypes = [
    {
      'value': 'individual',
      'title': 'Particulier',
      'icon': Icons.person,
      'desc': 'J\'envoie ou je reçois des colis occasionnellement.'
    },
    {
      'value': 'merchant',
      'title': 'Commerçant',
      'icon': Icons.storefront,
      'desc': 'Je vends des produits et j\'expédie à mes clients.'
    },
    {
      'value': 'enterprise',
      'title': 'Entreprise',
      'icon': Icons.business,
      'desc': 'Nous avons des besoins d\'expédition réguliers.'
    },
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez saisir votre prénom et nom')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).updateProfile(email: null, userType: _selectedType);
      if (mounted) {
        // Le GoRouter devrait intercepter ce changement d'état via son refreshListenable
        // Mais par sécurité, on force la navigation.
        context.go('/client'); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bienvenue sur PickuPoint'),
        automaticallyImplyLeading: false, // Pas de bouton retour
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Faisons connaissance ! 👋',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Pour vous offrir la meilleure expérience possible, veuillez compléter votre profil.',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 40),

            // Prénom et Nom
            const Text(
              '1. Quel est votre Prénom et Nom ?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Votre prénom et nom *',
                hintText: 'Ex: Anta Diallo',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 40),

            // Type d'utilisateur
            const Text(
              '2. Vous êtes un... ?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._userTypes.map((type) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildTypeCard(
                value: type['value'],
                title: type['title'],
                desc: type['desc'],
                icon: type['icon'],
              ),
            )),
            
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: LoadingButton(
                onPressed: _submit,
                isLoading: _isLoading,
                label: 'C\'est parti !',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeCard({required String value, required String title, required String desc, required IconData icon}) {
    final isSelected = _selectedType == value;
    return InkWell(
      onTap: () => setState(() => _selectedType = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.05) : Colors.white,
        ),
        child: Row(
          children: [
            Icon(icon, size: 32, color: isSelected ? Theme.of(context).primaryColor : Colors.grey),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isSelected ? Theme.of(context).primaryColor : Colors.black87)),
                  const SizedBox(height: 4),
                  Text(desc, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: Theme.of(context).primaryColor),
          ],
        ),
      ),
    );
  }
}
