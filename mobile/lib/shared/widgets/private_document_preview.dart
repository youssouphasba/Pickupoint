import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/error_utils.dart';

Future<void> showPrivateDocumentPreview(
  BuildContext context, {
  required String title,
  required Future<Uint8List> Function() loadDocument,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => PrivateDocumentPreview(
        title: title,
        loadDocument: loadDocument,
      ),
    );

class PrivateDocumentPreview extends StatefulWidget {
  const PrivateDocumentPreview({
    super.key,
    required this.title,
    required this.loadDocument,
  });

  final String title;
  final Future<Uint8List> Function() loadDocument;

  @override
  State<PrivateDocumentPreview> createState() => _PrivateDocumentPreviewState();
}

class _PrivateDocumentPreviewState extends State<PrivateDocumentPreview> {
  late final AppLifecycleListener _lifecycle;
  MemoryImage? _image;
  Object? _error;
  bool _loading = true;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _visible = state == null || state == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      if (mounted) {
        setState(() => _visible = state == AppLifecycleState.resumed);
      }
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.loadDocument();
      if (mounted) setState(() => _image = MemoryImage(bytes));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    final image = _image;
    _image = null;
    if (image != null) unawaited(image.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: !_visible
            ? const Center(
                child: Text(
                    'Document masqué lorsque l’application est en arrière-plan.'))
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(friendlyError(_error!)))
                    : InteractiveViewer(
                        child: Image(
                          image: _image!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Text(
                                'Aperçu indisponible pour ce format. Consultez le document dans l’admin web sécurisé.'),
                          ),
                        ),
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
