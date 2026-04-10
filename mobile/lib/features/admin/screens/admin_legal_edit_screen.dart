import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/providers/legal_provider.dart';
import '../providers/admin_legal_provider.dart';
import '../../../shared/utils/error_utils.dart';

class AdminLegalEditScreen extends ConsumerStatefulWidget {
  final String docType;

  const AdminLegalEditScreen({super.key, required this.docType});

  @override
  ConsumerState<AdminLegalEditScreen> createState() => _AdminLegalEditScreenState();
}

class _AdminLegalEditScreenState extends ConsumerState<AdminLegalEditScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  void _loadInitialData() {
    // On s'assure d'attendre le chargement initial si le cache n'est pas rempli
    Future.microtask(() {
      final doc = ref.read(legalContentProvider(widget.docType)).valueOrNull;
      if (doc != null) {
        _titleController.text = doc.title;
        _contentController.text = doc.content;
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await ref.read(adminLegalProvider.notifier).updateDocument(
            widget.docType,
            _titleController.text.trim(),
            _contentController.text.trim(),
          );
          
      // Rafraîchir le provider public
      ref.invalidate(legalContentProvider(widget.docType));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document mis à jour avec succès')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncContent = ref.watch(legalContentProvider(widget.docType));
    final isSaving = ref.watch(adminLegalProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.docType == 'cgu' ? 'Modifier les CGU' : 'Modifier la Politique'),
        actions: [
          if (!isSaving)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _save,
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
      body: asyncContent.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Erreur : $err')),
        data: (doc) {
          // On set la valeur si ce n'est pas déjà fait (utile au premier chargement)
          if (_titleController.text.isEmpty && _contentController.text.isEmpty) {
            _titleController.text = doc.title;
            _contentController.text = doc.content;
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Titre du document',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Requis' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _contentController,
                  decoration: const InputDecoration(
                    labelText: 'Contenu',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 20,
                  validator: (val) => val == null || val.trim().isEmpty ? 'Requis' : null,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: isSaving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Enregistrer les modifications'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
