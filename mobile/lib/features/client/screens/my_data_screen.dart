import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/auth/auth_provider.dart';

class MyDataScreen extends ConsumerStatefulWidget {
  const MyDataScreen({super.key});

  @override
  ConsumerState<MyDataScreen> createState() => _MyDataScreenState();
}

class _MyDataScreenState extends ConsumerState<MyDataScreen> {
  late Future<Map<String, dynamic>> _summary;
  List<Map<String, dynamic>> _requests = const [];
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _summary = _loadSummary();
  }

  Future<Map<String, dynamic>> _loadSummary() async {
    final api = ref.read(apiClientProvider);
    final responses = await Future.wait([
      api.getMyDataSummary(),
      api.getMyPrivacyRequests(),
    ]);
    final requestData = Map<String, dynamic>.from(responses[1].data as Map);
    _requests = (requestData['requests'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return Map<String, dynamic>.from(responses[0].data as Map);
  }

  Future<void> _download({required bool pdf}) async {
    setState(() => _downloading = true);
    try {
      final bytes = await ref.read(apiClientProvider).downloadMyData(pdf: pdf);
      final directory = await getApplicationDocumentsDirectory();
      final extension = pdf ? 'pdf' : 'json';
      final file = File('${directory.path}/denkma-mes-donnees.$extension');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await Share.shareXFiles(
        [
          XFile(file.path,
              mimeType: pdf ? 'application/pdf' : 'application/json')
        ],
        subject: 'Mes données Denkma',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Vos données sont prêtes à être enregistrées ou partagées.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Téléchargement impossible pour le moment.')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _createRequest(String type) async {
    try {
      await ref
          .read(apiClientProvider)
          .createPrivacyRequest({'request_type': type});
      setState(() => _summary = _loadSummary());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Votre demande a été envoyée.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Une demande similaire est peut-être déjà en cours.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes données')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _summary,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
                child: Text('Impossible de charger vos données.'));
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final profile =
              Map<String, dynamic>.from(data['profile'] as Map? ?? const {});
          final parcels = (data['recent_parcels'] as List? ?? const []).length;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _summary = _loadSummary()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Vos informations essentielles',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              _DataLine(
                                  label: 'Nom',
                                  value: '${profile['name'] ?? '—'}'),
                              _DataLine(
                                  label: 'Téléphone',
                                  value: '${profile['phone'] ?? '—'}'),
                              _DataLine(
                                  label: 'E-mail',
                                  value:
                                      '${profile['email'] ?? 'Non renseigné'}'),
                              _DataLine(
                                  label: 'Rôle',
                                  value: '${profile['role'] ?? '—'}'),
                              _DataLine(
                                  label: 'Colis associés',
                                  value: '${data['parcel_count'] ?? parcels}'),
                            ]))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            _downloading ? null : () => _download(pdf: true),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('PDF'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _downloading ? null : () => _download(pdf: false),
                        icon: const Icon(Icons.data_object),
                        label: const Text('JSON'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Faire une demande',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _RequestButton(
                    label: 'Demander une rectification',
                    icon: Icons.edit_outlined,
                    onTap: () => _createRequest('rectification')),
                _RequestButton(
                    label: 'Demander la suppression de mon compte',
                    icon: Icons.delete_outline,
                    onTap: () => _createRequest('deletion')),
                _RequestButton(
                    label: 'Demander une limitation du traitement',
                    icon: Icons.pause_circle_outline,
                    onTap: () => _createRequest('restriction')),
                if (_requests.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Mes demandes',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ..._requests.map((request) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.assignment_outlined),
                      title: Text('${request['request_type'] ?? 'Demande'}'),
                      subtitle: Text(
                          '${request['status'] ?? 'pending'}${request['admin_response'] == null ? '' : '\n${request['admin_response']}'}'))),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DataLine extends StatelessWidget {
  const _DataLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.grey))),
        Expanded(child: Text(value))
      ]));
}

class _RequestButton extends StatelessWidget {
  const _RequestButton(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap);
}
