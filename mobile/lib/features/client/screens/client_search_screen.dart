import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ClientSearchScreen extends StatefulWidget {
  const ClientSearchScreen({super.key});

  @override
  State<ClientSearchScreen> createState() => _ClientSearchScreenState();
}

class _ClientSearchScreenState extends State<ClientSearchScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _search() {
    final code = _codeController.text.trim();
    if (code.isNotEmpty) {
      context.push('/track/$code');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi de colis')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              'Suivre un colis',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Entrez le code de suivi (ex: PKP-...) pour voir l\'état de la livraison.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _codeController,
              decoration: InputDecoration(
                labelText: 'Code de suivi',
                hintText: 'PKP-123456',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
              textInputAction: TextInputAction.search,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _search,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('Rechercher'),
            ),
          ],
        ),
      ),
    );
  }
}
