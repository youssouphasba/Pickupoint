import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../shared/utils/error_utils.dart';

class AdminWhatsappSupportScreen extends ConsumerStatefulWidget {
  const AdminWhatsappSupportScreen({
    super.key,
    this.initialQuery,
    this.initialConversationId,
  });

  final String? initialQuery;
  final String? initialConversationId;

  @override
  ConsumerState<AdminWhatsappSupportScreen> createState() =>
      _AdminWhatsappSupportScreenState();
}

class _AdminWhatsappSupportScreenState
    extends ConsumerState<AdminWhatsappSupportScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _startPhoneController = TextEditingController();
  final _replyController = TextEditingController();
  final _audioPlayer = AudioPlayer();
  final _audioRecorder = AudioRecorder();
  final _noteController = TextEditingController();
  final Map<String, String> _drafts = {};
  final Map<String, String> _requestIds = {};
  Timer? _refreshTimer;
  int _detailRevision = 0;
  int _listRevision = 0;
  int _conversationLimit = 50;
  int _conversationTotal = 0;
  String? _before;
  bool _hasMore = false;
  bool _loadingOlder = false;
  List<Map<String, dynamic>> _notes = [];
  List<Map<String, dynamic>> _quickReplies = [];
  String? _voicePath;
  String? _voiceConversationId;
  String? _voiceRequestId;
  bool get _locked =>
      _sending ||
      _sendingTemplate ||
      _startingSupport ||
      _recording ||
      _recordingBusy ||
      _voicePath != null;
  String _requestId(String key) => _requestIds.putIfAbsent(
      key,
      () => List.generate(
          24,
          (_) => Random.secure()
              .nextInt(256)
              .toRadixString(16)
              .padLeft(2, '0')).join());

  String _status = 'open';
  String? _selectedConversationId;
  List<Map<String, dynamic>> _conversations = [];
  Map<String, dynamic>? _conversation;
  List<Map<String, dynamic>> _messages = [];
  bool _loadingConversations = true;
  bool _loadingDetail = false;
  bool _sending = false;
  bool _startingSupport = false;
  bool _sendingTemplate = false;
  bool _recording = false;
  bool _recordingBusy = false;
  String? _playingMessageId;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          !_loadingConversations &&
          !_loadingDetail) {
        _loadConversations(silent: true);
      }
    });
    _loadSettings();
    final initialQuery = widget.initialQuery?.trim();
    final initialConversationId = widget.initialConversationId?.trim();
    if (initialQuery != null && initialQuery.isNotEmpty) {
      _searchController.text = initialQuery;
      _startPhoneController.text = initialQuery;
      _status = 'all';
    }
    if (initialConversationId != null && initialConversationId.isNotEmpty) {
      _selectedConversationId = initialConversationId;
    }
    _loadConversations();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _noteController.dispose();
    _removeVoiceFile();
    _searchController.dispose();
    _startPhoneController.dispose();
    _replyController.dispose();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadConversations(silent: true);
    }
  }

  Future<void> _loadSettings() async {
    try {
      final response =
          await ref.read(apiClientProvider).getWhatsappSupportSettings();
      if (!mounted) return;
      setState(() => _quickReplies =
          (response.data['quick_replies'] as List? ?? [])
              .whereType<Map>()
              .map((x) => Map<String, dynamic>.from(x))
              .toList());
    } catch (_) {}
  }

  Future<void> _loadConversations({bool silent = false}) async {
    if (!mounted) return;
    final revision = ++_listRevision;
    if (!silent) {
      setState(() {
        _loadingConversations = true;
        _error = null;
      });
    }
    try {
      final response = await ref
          .read(apiClientProvider)
          .getWhatsappSupportConversations(
              status: _status,
              query: _searchController.text,
              limit: _conversationLimit.clamp(1, 100));
      final data = Map<String, dynamic>.from(response.data as Map);
      final conversations = (data['conversations'] as List? ?? [])
          .whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
      if (_conversationLimit > 100) {
        for (var skip = 100; skip < _conversationLimit; skip += 100) {
          final more = await ref
              .read(apiClientProvider)
              .getWhatsappSupportConversations(
                  status: _status,
                  query: _searchController.text,
                  skip: skip,
                  limit: (_conversationLimit - skip).clamp(1, 100));
          conversations.addAll((more.data['conversations'] as List? ?? [])
              .whereType<Map>()
              .map((x) => Map<String, dynamic>.from(x)));
        }
      }
      if (!mounted || revision != _listRevision) return;
      setState(() {
        _conversationTotal =
            (data['total'] as num?)?.toInt() ?? conversations.length;
        _conversations = {
          for (final x in conversations) x['conversation_id']: x
        }.values.toList();
        if (_selectedConversationId == null && conversations.isNotEmpty) {
          _selectedConversationId =
              _string(conversations.first['conversation_id']);
          _replyController.text = _drafts[_selectedConversationId] ?? '';
        }
      });
      if (_selectedConversationId != null && !_loadingOlder) {
        await _loadDetail(_selectedConversationId!, silent: silent);
      }
    } catch (e) {
      if (mounted && revision == _listRevision) {
        setState(() => _error = friendlyError(e));
      }
    } finally {
      if (mounted && revision == _listRevision) {
        setState(() => _loadingConversations = false);
      }
    }
  }

  Future<void> _loadDetail(String conversationId,
      {bool silent = false, String? before}) async {
    if (!mounted || (_locked && conversationId != _selectedConversationId)) {
      return;
    }
    final switched = conversationId != _selectedConversationId;
    if (switched) {
      final previous = _selectedConversationId;
      if (previous != null) _drafts[previous] = _replyController.text;
      _replyController.text = _drafts[conversationId] ?? '';
      _noteController.clear();
      _messages = [];
      _notes = [];
      _hasMore = false;
      _before = null;
    }
    final revision = ++_detailRevision;
    setState(() {
      _selectedConversationId = conversationId;
      if (!silent && before == null) _loadingDetail = true;
      if (before != null) _loadingOlder = true;
    });
    try {
      final response = await ref
          .read(apiClientProvider)
          .getWhatsappSupportConversation(conversationId, before: before);
      final data = Map<String, dynamic>.from(response.data as Map);
      if (!mounted ||
          revision != _detailRevision ||
          conversationId != _selectedConversationId) {
        return;
      }
      final incoming = (data['messages'] as List? ?? [])
          .whereType<Map>()
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
      final initialPage = switched || _messages.isEmpty;
      setState(() {
        _conversation = _map(data['conversation']);
        final merged = {
          for (final message in [..._messages, ...incoming])
            message['message_id']: message
        };
        _messages = merged.values.toList()
          ..sort((a, b) {
            final date = (a['created_at']?.toString() ?? '')
                .compareTo(b['created_at']?.toString() ?? '');
            return date != 0
                ? date
                : a['message_id']
                    .toString()
                    .compareTo(b['message_id'].toString());
          });
        if (before != null || initialPage) {
          _hasMore = data['has_more'] == true;
          _before = _string(data['next_before']);
        }
        _notes = (data['notes'] as List? ?? [])
            .whereType<Map>()
            .map((x) => Map<String, dynamic>.from(x))
            .toList();
      });
    } catch (e) {
      if (mounted && revision == _detailRevision) {
        setState(() => _error = friendlyError(e));
      }
    } finally {
      if (mounted && revision == _detailRevision) {
        setState(() {
          _loadingDetail = false;
          _loadingOlder = false;
        });
      }
    }
  }

  bool get _canReplyFreeform {
    final expires = DateTime.tryParse(
        _conversation?['reply_window_expires_at']?.toString() ?? '');
    return _conversation?['can_reply_freeform'] == true &&
        expires != null &&
        expires.isAfter(DateTime.now());
  }

  void _showReplyWindowClosedMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'La fenêtre WhatsApp de 24h est fermée. Le client doit renvoyer un message ou il faut utiliser un modèle approuvé.',
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    final conversationId = _selectedConversationId;
    if (text.isEmpty || conversationId == null || _locked) return;
    if (!_canReplyFreeform) {
      _showReplyWindowClosedMessage();
      return;
    }

    setState(() => _sending = true);
    try {
      await ref.read(apiClientProvider).sendWhatsappSupportTextReply(
          conversationId, text,
          requestId: _requestId('text:$conversationId'));
      _requestIds.remove('text:$conversationId');
      if (_selectedConversationId == conversationId) _replyController.clear();
      _drafts.remove(conversationId);
      await _loadConversations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Réponse WhatsApp envoyée.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _sendReopenTemplate() async {
    final conversationId = _selectedConversationId;
    if (conversationId == null || _locked) return;

    setState(() => _sendingTemplate = true);
    try {
      await ref.read(apiClientProvider).sendWhatsappSupportReopenTemplate(
          conversationId,
          requestId: _requestId('reopen:$conversationId'));
      _requestIds.remove('reopen:$conversationId');
      await _loadConversations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relance WhatsApp envoyée.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sendingTemplate = false);
      }
    }
  }

  Future<void> _startSupportConversation() async {
    final phone = _startPhoneController.text.trim();
    if (phone.isEmpty || _locked) return;

    setState(() => _startingSupport = true);
    try {
      final response = await ref.read(apiClientProvider).startWhatsappSupport(
          phone: phone, requestId: _requestId('start:$phone'));
      if (!mounted) return;
      _requestIds.remove('start:$phone');
      final data = Map<String, dynamic>.from(response.data as Map);
      final conversation = _map(data['conversation']);
      final conversationId = _string(conversation?['conversation_id']);
      setState(() {
        _status = 'all';
        _searchController.text = phone;
        _selectedConversationId = conversationId;
      });
      await _loadConversations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template WhatsApp envoyé.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _startingSupport = false);
      }
    }
  }

  Future<void> _removeVoiceFile() async {
    final path = _voicePath;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> _toggleVoiceReply() async {
    final id = _selectedConversationId;
    if (id == null || _recordingBusy || _sending || _voicePath != null) return;
    if (!_recording && !_canReplyFreeform) {
      _showReplyWindowClosedMessage();
      return;
    }
    setState(() => _recordingBusy = true);
    try {
      if (_recording) {
        final path = await _audioRecorder.stop();
        if (!mounted) {
          if (path != null) {
            try {
              await File(path).delete();
            } catch (_) {}
          }
          return;
        }
        if (path == null) throw Exception('Aucun audio enregistré.');
        setState(() {
          _recording = false;
          _voicePath = path;
        });
        return;
      }
      if (!await _audioRecorder.hasPermission()) {
        throw Exception('Autorisation micro refusée.');
      }
      final dir = await getTemporaryDirectory();
      final opus = await _audioRecorder.isEncoderSupported(AudioEncoder.opus);
      final path =
          '${dir.path}/denkma_support_${_requestId("voice-file:$id")}.${opus ? "opus" : "m4a"}';
      await _audioRecorder.start(
          RecordConfig(
              encoder: opus ? AudioEncoder.opus : AudioEncoder.aacLc,
              bitRate: 64000,
              sampleRate: 44100),
          path: path);
      if (!mounted) {
        await _audioRecorder.cancel();
        return;
      }
      setState(() {
        _recording = true;
        _voiceConversationId = id;
        _voiceRequestId = _requestId('voice:$id');
      });
    } catch (e) {
      if (mounted) {
        setState(() => _recording = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _recordingBusy = false);
    }
  }

  Future<void> _cancelVoice() async {
    await _audioPlayer.stop();
    await _removeVoiceFile();
    if (mounted) {
      setState(() {
        _requestIds.remove('voice:$_voiceConversationId');
        _requestIds.remove('voice-file:$_voiceConversationId');
        _voicePath = null;
        _voiceConversationId = null;
        _voiceRequestId = null;
        _playingMessageId = null;
      });
    }
  }

  Future<void> _sendVoice() async {
    final path = _voicePath;
    final id = _voiceConversationId;
    if (path == null || id == null || _sending) return;
    if (!_canReplyFreeform) {
      _showReplyWindowClosedMessage();
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(apiClientProvider)
          .sendWhatsappSupportVoiceReply(id, path, requestId: _voiceRequestId);
      await _cancelVoice();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        await _loadConversations(silent: true);
      }
    }
  }

  Future<void> _addNote() async {
    final id = _selectedConversationId;
    final text = _noteController.text.trim();
    if (id == null || text.isEmpty || _locked) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiClientProvider).addWhatsappSupportNote(id, text);
      if (mounted) {
        _noteController.clear();
        await _loadDetail(id, silent: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _updateStatus(String status) async {
    final conversationId = _selectedConversationId;
    if (conversationId == null || _locked) return;
    try {
      await ref
          .read(apiClientProvider)
          .updateWhatsappSupportConversationStatus(conversationId, status);
      await _loadConversations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _privateMediaUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.path.startsWith('/api/admin/support/whatsapp/media/')) {
      throw Exception('Adresse du média invalide.');
    }
    return ApiEndpoints.resolve(uri.path);
  }

  Future<void> _openAttachment(Map<String, dynamic> message) async {
    final media = _map(message['media']);
    final url = _string(media?['download_url']);
    if (url == null) return;
    try {
      final bytes = await ref
          .read(apiClientProvider)
          .downloadBytes(_privateMediaUrl(url));
      if (!mounted) return;
      if (message['message_type'] == 'image' &&
          ['image/jpeg', 'image/png', 'image/webp']
              .contains(media?['mime_type'])) {
        await showDialog<void>(
            context: context,
            builder: (context) => Dialog(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                      child: InteractiveViewer(
                          child: Image.memory(bytes,
                              errorBuilder: (context, error, stack) =>
                                  const Text('Photo illisible')))),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fermer')),
                ])));
      } else {
        final directory = await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
        final original = _string(media?['filename']) ?? 'document';
        final safeName = original
            .split(RegExp(r'[\\/]'))
            .last
            .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final file = File(
            '${directory.path}/support_${DateTime.now().microsecondsSinceEpoch}_$safeName');
        await file.writeAsBytes(bytes, flush: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Document enregistré dans ${file.path}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Média indisponible : ${friendlyError(e)}')));
      }
    }
  }

  Future<void> _playAudio(Map<String, dynamic> message) async {
    final id = _string(message['message_id']) ?? '';
    final url = _string(_map(message['media'])?['download_url']);
    if (url == null) return;
    try {
      if (_playingMessageId == id) {
        await _audioPlayer.stop();
        if (mounted) setState(() => _playingMessageId = null);
        return;
      }
      setState(() => _playingMessageId = id);
      final bytes = await ref
          .read(apiClientProvider)
          .downloadBytes(_privateMediaUrl(url));
      if (!mounted || _playingMessageId != id) return;
      await _audioPlayer.stop();
      await _audioPlayer.play(BytesSource(bytes));
      _audioPlayer.onPlayerComplete.first.then((_) {
        if (mounted && _playingMessageId == id) {
          setState(() => _playingMessageId = null);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _playingMessageId = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Lecture impossible : ${friendlyError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support WhatsApp'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loadConversations,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadConversations,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSearchAndFilters(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorCard(message: _error!),
            ],
            const SizedBox(height: 16),
            _buildConversationList(),
            const SizedBox(height: 16),
            _buildDetail(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          enabled: !_locked,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Rechercher',
            hintText: 'Nom, numéro, colis ou message',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              onPressed: _locked
                  ? null
                  : () {
                      _conversationLimit = 50;
                      _loadConversations();
                    },
              icon: const Icon(Icons.arrow_forward),
            ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _loadConversations(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _startPhoneController,
                enabled: !_locked,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Contacter un utilisateur',
                  hintText: '+221...',
                  prefixIcon: Icon(Icons.chat_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _locked ? null : _startSupportConversation,
              child: _startingSupport
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Template'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            _filterChip('open', 'À traiter'),
            _filterChip('pending', 'Attente client'),
            _filterChip('pending_internal', 'Action interne'),
            _filterChip('resolved', 'Résolus'),
            _filterChip('all', 'Tous'),
          ],
        ),
      ],
    );
  }

  Widget _filterChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _status == value,
      onSelected: _locked
          ? null
          : (_) {
              setState(() {
                final previous = _selectedConversationId;
                if (previous != null) _drafts[previous] = _replyController.text;
                _replyController.clear();
                _noteController.clear();
                _notes = [];
                _before = null;
                _hasMore = false;
                _conversationLimit = 50;
                _status = value;
                _selectedConversationId = null;
                _conversation = null;
                _messages = [];
              });
              _loadConversations();
            },
    );
  }

  Widget _buildConversationList() {
    if (_loadingConversations) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_conversations.isEmpty) {
      return const _InfoCard(
        icon: Icons.mark_chat_read_outlined,
        title: 'Aucune conversation',
        subtitle: 'Aucun message WhatsApp ne correspond au filtre actuel.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_conversations.length} conversation(s)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._conversations.map(_buildConversationTile),
        if (_conversations.length < _conversationTotal)
          OutlinedButton(
              onPressed: _locked
                  ? null
                  : () {
                      _conversationLimit += 50;
                      _loadConversations();
                    },
              child: const Text('Voir plus de conversations')),
      ],
    );
  }

  Widget _buildConversationTile(Map<String, dynamic> conversation) {
    final id = _string(conversation['conversation_id']) ?? '';
    final user = _map(conversation['matched_user']);
    final parcel = _map(conversation['matched_parcel']);
    final label =
        _string(user?['name']) ?? _string(conversation['phone']) ?? 'Contact';
    final status = _string(conversation['status']) ?? 'open';
    final tracking = _string(parcel?['tracking_code']);
    final selected = id == _selectedConversationId;

    return Card(
      color: selected ? Colors.green.withValues(alpha: 0.08) : null,
      child: ListTile(
        selected: selected,
        leading: CircleAvatar(
          backgroundColor: _statusColor(status).withValues(alpha: 0.15),
          child: Icon(Icons.support_agent, color: _statusColor(status)),
        ),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            _string(conversation['last_message_text']) ?? 'Message WhatsApp',
            if (tracking != null) tracking,
          ].join(' • '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _StatusPill(status: status),
            const SizedBox(height: 4),
            Text(_formatDate(conversation['last_message_at'])),
          ],
        ),
        onTap: _locked ? null : () => _loadDetail(id),
      ),
    );
  }

  Widget _buildDetail() {
    if (_selectedConversationId == null) {
      return const SizedBox.shrink();
    }
    if (_loadingDetail) {
      return const Center(child: CircularProgressIndicator());
    }
    final conversation = _conversation;
    if (conversation == null) {
      return const _InfoCard(
        icon: Icons.forum_outlined,
        title: 'Conversation non chargée',
        subtitle: 'Sélectionnez une conversation pour afficher le détail.',
      );
    }

    final user = _map(conversation['matched_user']);
    final parcel = _map(conversation['matched_parcel']);
    final relatedParcels =
        (conversation['related_parcels'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_search_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _string(user?['name']) ??
                            _string(conversation['phone']) ??
                            'Contact WhatsApp',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _StatusPill(
                        status: _string(conversation['status']) ?? 'open'),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Téléphone : ${_string(conversation['phone']) ?? '-'}'),
                Text('Rôle : ${_string(user?['role']) ?? 'non identifié'}'),
                if (parcel != null) ...[
                  const Divider(height: 24),
                  Text(
                    'Colis lié : ${_string(parcel['tracking_code']) ?? _string(parcel['parcel_id']) ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text('Statut : ${_string(parcel['status']) ?? '-'}'),
                  Text('Mode : ${_string(parcel['delivery_mode']) ?? '-'}'),
                ],
                if (relatedParcels.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: relatedParcels
                        .take(6)
                        .map((parcel) => Chip(
                              label: Text(
                                _string(parcel['tracking_code']) ??
                                    _string(parcel['parcel_id']) ??
                                    'Colis',
                              ),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _locked ? null : () => _updateStatus('open'),
                      icon: const Icon(Icons.mark_chat_unread_outlined),
                      label: const Text('À traiter'),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _locked ? null : () => _updateStatus('pending'),
                      icon: const Icon(Icons.schedule_outlined),
                      label: const Text('Attente du client'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _locked
                          ? null
                          : () => _updateStatus('pending_internal'),
                      icon: const Icon(Icons.assignment_outlined),
                      label: const Text('Action interne'),
                    ),
                    FilledButton.icon(
                      onPressed:
                          _locked ? null : () => _updateStatus('resolved'),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Résolu'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Messages',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_hasMore)
          OutlinedButton(
              onPressed: _loadingOlder
                  ? null
                  : () => _loadDetail(_selectedConversationId!,
                      before: _before, silent: true),
              child:
                  Text(_loadingOlder ? 'Chargement…' : 'Messages précédents')),
        if (_messages.isEmpty)
          const _InfoCard(
            icon: Icons.chat_bubble_outline,
            title: 'Aucun message',
            subtitle: 'Les messages apparaîtront ici dès réception.',
          )
        else
          ..._messages.map(_buildMessageBubble),
        const SizedBox(height: 16),
        _buildReplyBox(),
        const SizedBox(height: 16),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Notes internes',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text(
                          'Réservées à l’administration. Les 50 dernières notes sont affichées.'),
                      ..._notes.map((note) => ListTile(
                          title: Text(_string(note['text']) ?? ''),
                          subtitle: Text(
                              '${note["admin_name"] ?? "Admin"} · ${_formatDate(note["created_at"])}'))),
                      TextField(
                          controller: _noteController,
                          enabled: !_locked,
                          maxLength: 2000,
                          maxLines: 3,
                          decoration: const InputDecoration(
                              labelText: 'Nouvelle note interne')),
                      OutlinedButton(
                          onPressed: _locked ? null : _addNote,
                          child: const Text('Ajouter la note interne')),
                    ]))),
      ],
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final inbound = _string(message['direction']) != 'outbound';
    final text = _string(message['text']) ?? '';
    final media = _map(message['media']);
    final hasAudio = (_string(message['message_type']) == 'audio') ||
        (_string(media?['mime_type']) ?? '').startsWith('audio/');
    final messageId = _string(message['message_id']) ?? '';

    return Align(
      alignment: inbound ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: inbound ? Colors.grey.shade100 : Colors.green.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: inbound ? Colors.grey.shade300 : Colors.green.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              inbound ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Text(
              inbound ? 'Contact' : (_string(message['admin_name']) ?? 'Admin'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: inbound ? Colors.blueGrey : Colors.green.shade800,
              ),
            ),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(text),
            ],
            if (hasAudio) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _playAudio(message),
                icon: Icon(
                  _playingMessageId == messageId
                      ? Icons.stop
                      : Icons.play_arrow,
                ),
                label: Text(
                  _playingMessageId == messageId
                      ? 'Arrêter l’audio'
                      : 'Lire l’audio',
                ),
              ),
            ],
            if (!hasAudio && media?['download_url'] != null)
              OutlinedButton.icon(
                  onPressed: () => _openAttachment(message),
                  icon: Icon(message['message_type'] == 'image'
                      ? Icons.image_outlined
                      : Icons.download),
                  label: Text(message['message_type'] == 'image'
                      ? 'Voir la photo'
                      : 'Télécharger le document')),
            if (!inbound)
              Text(_deliveryLabel(message['delivery_status']),
                  style: const TextStyle(fontSize: 11)),
            if (message['send_error'] != null)
              Text(message['send_error'].toString(),
                  style: const TextStyle(color: Colors.red, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              _formatDate(message['created_at']),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBox() {
    final allowed = _canReplyFreeform;
    final expires = _conversation?['reply_window_expires_at'];
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(allowed
                  ? 'Réponses libres jusqu’au ${_formatDate(expires)}.'
                  : 'Fenêtre de réponse fermée. Le contact doit répondre à un modèle approuvé pour la rouvrir.'),
              if (!allowed)
                OutlinedButton(
                    onPressed: _locked ? null : _sendReopenTemplate,
                    child: const Text('Envoyer une relance approuvée')),
              if (allowed) ...[
                Wrap(
                    spacing: 8,
                    children: _quickReplies
                        .map((reply) => ActionChip(
                            label: Text(_string(reply['label']) ?? ''),
                            onPressed: _locked
                                ? null
                                : () {
                                    _replyController.text = [
                                      _replyController.text,
                                      _string(reply['text']) ?? ''
                                    ].where((x) => x.isNotEmpty).join('\n');
                                    _requestIds.remove(
                                        'text:$_selectedConversationId');
                                  }))
                        .toList()),
                TextField(
                    controller: _replyController,
                    enabled: !_locked,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 2000,
                    onChanged: (_) =>
                        _requestIds.remove('text:$_selectedConversationId'),
                    decoration: const InputDecoration(
                        labelText: 'Réponse au contact',
                        border: OutlineInputBorder())),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                      onPressed: _locked ? null : _sendReply,
                      icon: const Icon(Icons.send),
                      label: const Text('Envoyer le texte')),
                  OutlinedButton.icon(
                      onPressed:
                          _recordingBusy || _sending || _voicePath != null
                              ? null
                              : _toggleVoiceReply,
                      icon: Icon(_recording ? Icons.stop : Icons.mic),
                      label: Text(_recording
                          ? 'Arrêter pour écouter'
                          : 'Enregistrer un vocal')),
                ]),
              ],
              if (_recording && !allowed)
                OutlinedButton(
                    onPressed: _toggleVoiceReply,
                    child: const Text('Arrêter le vocal')),
              if (_voicePath != null) ...[
                const Divider(),
                const Text('Vocal enregistré — non envoyé'),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Écouter'),
                      onPressed: _sending
                          ? null
                          : () async {
                              try {
                                await _audioPlayer
                                    .play(DeviceFileSource(_voicePath!));
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(friendlyError(e))));
                                }
                              }
                            }),
                  FilledButton(
                      onPressed: allowed && !_sending ? _sendVoice : null,
                      child: const Text('Envoyer le vocal')),
                  TextButton(
                      onPressed: _sending ? null : _cancelVoice,
                      child: const Text('Annuler')),
                ]),
              ],
            ])));
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: _statusColor(status),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: Colors.blueGrey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message, style: TextStyle(color: Colors.red.shade800)),
      ),
    );
  }
}

Map<String, dynamic>? _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String? _string(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
    return null;
  }
  return text;
}

String _formatDate(Object? value) {
  final text = _string(value);
  if (text == null) return '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text;
  return DateFormat('dd/MM HH:mm').format(parsed.toLocal());
}

String _statusLabel(String status) {
  return switch (status) {
    'pending' => 'Attente du client',
    'pending_internal' => 'Action interne',
    'resolved' => 'Résolu',
    _ => 'À traiter',
  };
}

String _deliveryLabel(Object? status) => switch (status) {
      'sending' => 'Envoi en cours',
      'accepted' => 'Accepté par WhatsApp',
      'sent' => 'Envoyé',
      'delivered' => 'Livré',
      'read' => 'Lu',
      'failed' => 'Échec d’envoi',
      'uncertain' => 'Envoi incertain — vérifier avant de renvoyer',
      _ => 'Envoi enregistré',
    };

Color _statusColor(String status) {
  return switch (status) {
    'pending' => Colors.orange,
    'resolved' => Colors.green,
    _ => Colors.red,
  };
}
