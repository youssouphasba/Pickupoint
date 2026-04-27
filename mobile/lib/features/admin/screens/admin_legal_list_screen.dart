import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminLegalListScreen extends StatelessWidget {
  const AdminLegalListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents Légaux')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildItem(
            context,
            title: 'Politique de confidentialité',
            docType: 'privacy_policy',
            icon: Icons.privacy_tip_outlined,
          ),
          const SizedBox(height: 12),
          _buildItem(
            context,
            title: "Conditions Générales d'Utilisation",
            docType: 'cgu',
            icon: Icons.gavel_outlined,
          ),
          const SizedBox(height: 12),
          _buildItem(
            context,
            title: 'Mentions légales',
            docType: 'mentions_legales',
            icon: Icons.business_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, {required String title, required String docType, required IconData icon}) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Modifier le contenu du document'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go('/admin/legal/$docType/edit'),
      ),
    );
  }
}
