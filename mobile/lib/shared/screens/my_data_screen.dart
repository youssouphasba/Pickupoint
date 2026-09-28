import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/auth/auth_provider.dart';

final _myDataSummaryProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final response = await ref.read(apiClientProvider).getMyDataSummary();
  return Map<String, dynamic>.from(response.data as Map);
});

final _myPrivacyRequestsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await ref.read(apiClientProvider).getMyPrivacyRequests();
  final payload = Map<String, dynamic>.from(response.data as Map);
  return (payload['requests'] as List? ?? const [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
});

class MyDataScreen extends ConsumerStatefulWidget {
  const MyDataScreen({super.key});

  @override
  ConsumerState<MyDataScreen> createState() => _MyDataScreenState();
}

class _MyDataScreenState extends ConsumerState<MyDataScreen> {
  bool _downloading = false;
  bool _submitting = false;

  static const _requestTypes = <String, String>{
    'access': 'Accéder à mes données',
    'rectification': 'Corriger mes données',
    'deletion': 'Supprimer mes données',
    'opposition': 'M’opposer à un traitement',
    'restriction': 'Limiter un traitement',
    'export': 'Recevoir une copie de mes données',
  };

  static const _statusLabels = <String, String>{
    'pending': 'En attente',
    'in_progress': 'En cours',
    'completed': 'Terminée',
    'rejected': 'Refusée',
  };

  Future<void> _download({required bool pdf}) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await ref.read(apiClientProvider).downloadMyData(pdf: pdf);
      final directory = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
      final extension = pdf ? 'pdf' : 'json';
      final file = File(
        '${directory.path}${Platform.pathSeparator}denkma-mes-donnees-$timestamp.$extension',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fichier enregistré dans ${file.path}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le téléchargement a échoué. Réessayez.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _createRequest() async {
    String requestType = 'access';
    final messageController = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouvelle demande'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: requestType,
                  decoration: const InputDecoration(
                    labelText: 'Type de demande',
                    border: OutlineInputBorder(),
                  ),
                  items: _requestTypes.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => requestType = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: messageController,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Précisions (facultatif)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );
    final message = messageController.text.trim();
    messageController.dispose();
    if (submitted != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await ref.read(apiClientProvider).createPrivacyRequest({
        'request_type': requestType,
        if (message.isNotEmpty) 'message': message,
      });
      ref.invalidate(_myDataSummaryProvider);
      ref.invalidate(_myPrivacyRequestsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Votre demande a été envoyée.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La demande n’a pas pu être envoyée. Vérifiez qu’une demande identique n’est pas déjà en cours.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(_myDataSummaryProvider);
    final requests = ref.watch(_myPrivacyRequestsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mes données')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_myDataSummaryProvider);
          ref.invalidate(_myPrivacyRequestsProvider);
          await Future.wait([
            ref.read(_myDataSummaryProvider.future),
            ref.read(_myPrivacyRequestsProvider.future),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            summary.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (_, __) => _ErrorCard(
                message: 'Impossible de charger vos données.',
                onRetry: () => ref.invalidate(_myDataSummaryProvider),
              ),
              data: (data) => _SummaryCard(data: data),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Télécharger une copie',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Le PDF est lisible directement. Le fichier JSON contient les mêmes informations dans un format réutilisable.',
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed:
                              _downloading ? null : () => _download(pdf: true),
                          icon: _downloading
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Télécharger le PDF'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              _downloading ? null : () => _download(pdf: false),
                          icon: const Icon(Icons.data_object_outlined),
                          label: const Text('Télécharger le JSON'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Mes demandes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _submitting ? null : _createRequest,
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Nouvelle'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            requests.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => _ErrorCard(
                message: 'Impossible de charger vos demandes.',
                onRetry: () => ref.invalidate(_myPrivacyRequestsProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Vous n’avez encore envoyé aucune demande.'),
                    ),
                  );
                }
                return Column(
                  children: items
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RequestCard(
                            item: item,
                            typeLabels: _requestTypes,
                            statusLabels: _statusLabels,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final profile =
        Map<String, dynamic>.from(data['profile'] as Map? ?? const {});
    final recentParcels = (data['recent_parcels'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Informations essentielles',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _InfoRow(label: 'Nom', value: profile['name']),
                _InfoRow(label: 'Téléphone', value: profile['phone']),
                _InfoRow(label: 'E-mail', value: profile['email']),
                _InfoRow(label: 'Type de compte', value: profile['role']),
                _InfoRow(
                  label: 'Colis associés',
                  value: data['parcel_count'],
                ),
                _InfoRow(
                  label: 'Demandes en cours',
                  value: data['open_privacy_request_count'],
                ),
              ],
            ),
          ),
        ),
        if (recentParcels.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Colis récents',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...recentParcels.map(
                    (parcel) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(
                        (parcel['tracking_code'] ??
                                parcel['parcel_id'] ??
                                'Colis')
                            .toString(),
                      ),
                      subtitle: Text(
                        '${parcel['delivery_mode'] ?? '—'} · ${parcel['status'] ?? '—'}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value?.toString().trim().isNotEmpty == true
                    ? value.toString()
                    : '—',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.item,
    required this.typeLabels,
    required this.statusLabels,
  });

  final Map<String, dynamic> item;
  final Map<String, String> typeLabels;
  final Map<String, String> statusLabels;

  @override
  Widget build(BuildContext context) {
    final type = item['request_type']?.toString() ?? '';
    final status = item['status']?.toString() ?? '';
    final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '');
    final response = item['admin_response']?.toString().trim() ?? '';
    return Card(
      child: ListTile(
        title: Text(typeLabels[type] ?? type),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (createdAt != null)
              Text(
                  DateFormat('dd/MM/yyyy à HH:mm').format(createdAt.toLocal())),
            if (response.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Réponse : $response'),
            ],
          ],
        ),
        trailing: Text(
          statusLabels[status] ?? status,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: status == 'completed'
                ? Colors.green.shade700
                : status == 'rejected'
                    ? Colors.red.shade700
                    : Colors.orange.shade800,
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: Text(message)),
              TextButton(onPressed: onRetry, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
}
