import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/legal_provider.dart';

class LegalDocumentScreen extends ConsumerWidget {
  final String docType;

  const LegalDocumentScreen({super.key, required this.docType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncContent = ref.watch(legalContentProvider(docType));

    return Scaffold(
      appBar: AppBar(
        title: asyncContent.maybeWhen(
          data: (data) => Text(data.title),
          orElse: () => const Text('Document légal'),
        ),
      ),
      body: asyncContent.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 16),
              Text('Erreur de chargement', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(legalContentProvider(docType)),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (data) => SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: SelectableText(
            data.content,
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
        ),
      ),
    );
  }
}
