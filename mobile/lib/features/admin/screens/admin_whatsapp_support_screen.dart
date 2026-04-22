import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../shared/utils/error_utils.dart';

class AdminWhatsappSupportScreen extends ConsumerStatefulWidget {
  const AdminWhatsappSupportScreen({super.key});

  @override
  ConsumerState<AdminWhatsappSupportScreen> createState() =>
      _AdminWhatsappSupportScreenState();
}

class _AdminWhatsappSupportScreenState
    extends ConsumerState<AdminWhatsappSupportScreen> {
  final _searchController = TextEditingController();
  final _replyController = TextEditingController();
  final _audioPlayer = AudioPlayer();
  final _audioRecorder = AudioRecorder();

  String _status = 'open';
  String? _selectedConversationId;
  List<Map<String, dynamic>> _conversations = [];
  Map<String, dynamic>? _conversation;
  List<Map<String, dynamic>> _messages = [];
  bool _loadingConversations = true;
  bool _loadingDetail = false;
  bool _sending = false;
  bool _recording = false;
  bool _recordingBusy = false;
  String? _playingMessageId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _replyController.dispose();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _loadingConversations = true;
      _error = null;
    });
    try {
      final response = await ref.read(apiClientProvider).getWhatsappSupportConversations(
            status: _status,
            query: _searchController.text,
          );
      final data = Map<String, dynamic>.from(response.data as Map);
      final conversations = (data['conversations'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      setState(() {
        _conversations = conversations;
        _selectedConversationId ??=
            conversations.isNotEmpty ? _string(conversations.first['conversation_id']) : null;
      });
      if (_selectedConversationId != null) {
        await _loadDetail(_selectedConversationId!);
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => _loadingConversations = false);
      }
    }
  }

  Future<void> _loadDetail(String conversationId) async {
    setState(() {
      _selectedConversationId = conversationId;
      _loadingDetail = true;
      _error = null;
    });
    try {
      final response =
          await ref.read(apiClientProvider).getWhatsappSupportConversation(conversationId);
      final data = Map<String, dynamic>.from(response.data as Map);
      setState(() {
        _conversation = _map(data['conversation']);
        _messages = (data['messages'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => _loadingDetail = false);
      }
    }
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    final conversationId = _selectedConversationId;
    if (text.isEmpty || conversationId == null || _sending) return;

    setState(() => _sending = true);
    try {
      await ref
          .read(apiClientProvider)
          .sendWhatsappSupportTextReply(conversationId, text);
      _replyController.clear();
      await _loadConversations();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Réponse WhatsApp envoyée.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _toggleVoiceReply() async {
    final conversationId = _selectedConversationId;
    if (conversationId == null || _recordingBusy) return;

    setState(() => _recordingBusy = true);
    try {
      if (_recording) {
        final path = await _audioRecorder.stop();
        setState(() => _recording = false);
        if (path == null || path.trim().isEmpty) {
          throw Exception('Enregistrement audio introuvable.');
        }
        await ref
            .read(apiClientProvider)
            .sendWhatsappSupportVoiceReply(conversationId, path);
        await _loadConversations();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note vocale WhatsApp envoyée.')),
          );
        }
        return;
      }

      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        throw Exception('Autorisation micro refusée.');
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/denkma_support_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: path,
      );
      setState(() => _recording = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _recordingBusy = false);
      }
    }
  }

  Future<void> _updateStatus(String status) async {
    final conversationId = _selectedConversationId;
    if (conversationId == null) return;
    try {
      await ref
          .read(apiClientProvider)
          .updateWhatsappSupportConversationStatus(conversationId, status);
      await _loadConversations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _playAudio(Map<String, dynamic> message) async {
    final messageId = _string(message['message_id']) ?? '';
    final media = _map(message['media']);
    final downloadUrl = _string(media?['download_url']);
    if (downloadUrl == null || downloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio indisponible.')),
      );
      return;
    }

    if (_playingMessageId == messageId) {
      await _audioPlayer.stop();
      setState(() => _playingMessageId = null);
      return;
    }

    try {
      setState(() => _playingMessageId = messageId);
      final Uint8List bytes = await ref.read(apiClientProvider).downloadBytes(downloadUrl);
      await _audioPlayer.stop();
      await _audioPlayer.play(BytesSource(bytes));
      _audioPlayer.onPlayerComplete.first.then((_) {
        if (mounted && _playingMessageId == messageId) {
          setState(() => _playingMessageId = null);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _playingMessageId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lecture audio impossible : ${friendlyError(e)}'),
            backgroundColor: Colors.red,
          ),
        );
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
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Rechercher',
            hintText: 'Nom, numéro, colis ou message',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              onPressed: _loadConversations,
              icon: const Icon(Icons.arrow_forward),
            ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _loadConversations(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            _filterChip('open', 'Ouverts'),
            _filterChip('pending', 'En attente'),
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
      onSelected: (_) {
        setState(() {
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
      ],
    );
  }

  Widget _buildConversationTile(Map<String, dynamic> conversation) {
    final id = _string(conversation['conversation_id']) ?? '';
    final user = _map(conversation['matched_user']);
    final parcel = _map(conversation['matched_parcel']);
    final label = _string(user?['name']) ?? _string(conversation['phone']) ?? 'Contact';
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
        onTap: () => _loadDetail(id),
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
    final relatedParcels = (conversation['related_parcels'] as List? ?? const [])
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
                    _StatusPill(status: _string(conversation['status']) ?? 'open'),
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
                      onPressed: () => _updateStatus('open'),
                      icon: const Icon(Icons.mark_chat_unread_outlined),
                      label: const Text('Ouvert'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _updateStatus('pending'),
                      icon: const Icon(Icons.schedule_outlined),
                      label: const Text('En attente'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _updateStatus('resolved'),
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
              inbound ? 'Client' : 'Denkma',
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
                  _playingMessageId == messageId ? Icons.stop : Icons.play_arrow,
                ),
                label: Text(
                  _playingMessageId == messageId
                      ? 'Arrêter l’audio'
                      : 'Lire l’audio',
                ),
              ),
            ],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _replyController,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Réponse',
                  hintText: 'Écrire une réponse WhatsApp...',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _recordingBusy ? null : _toggleVoiceReply,
              style: OutlinedButton.styleFrom(
                foregroundColor: _recording ? Colors.red : null,
              ),
              child: _recordingBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_recording ? Icons.stop : Icons.mic),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _sending ? null : _sendReply,
              child: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
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
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
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
    'pending' => 'En attente',
    'resolved' => 'Résolu',
    _ => 'Ouvert',
  };
}

Color _statusColor(String status) {
  return switch (status) {
    'pending' => Colors.orange,
    'resolved' => Colors.green,
    _ => Colors.red,
  };
}
