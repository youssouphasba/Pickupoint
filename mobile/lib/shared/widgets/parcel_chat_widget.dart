import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/auth_provider.dart';

// ── Provider messages ──────────────────────────────────────────────────────

final parcelMessagesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, parcelId) async {
    final api = ref.read(apiClientProvider);
    final res = await api.getParcelMessages(parcelId);
    final data = res.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['messages'] ?? []);
  },
);

// ── Widget principal ───────────────────────────────────────────────────────

class ParcelChatWidget extends ConsumerStatefulWidget {
  const ParcelChatWidget({super.key, required this.parcelId, required this.isClosed});
  final String parcelId;
  final bool   isClosed; // true si statut terminal → messagerie en lecture seule

  @override
  ConsumerState<ParcelChatWidget> createState() => _ParcelChatWidgetState();
}

class _ParcelChatWidgetState extends ConsumerState<ParcelChatWidget> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();
  bool _isSending    = false;
  bool _isRecording  = false;
  String? _recordingPath;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Polling léger toutes les 8 secondes pendant la livraison
    if (!widget.isClosed) {
      _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        ref.invalidate(parcelMessagesProvider(widget.parcelId));
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.sendParcelMessage(widget.parcelId, text);
      _textController.clear();
      ref.invalidate(parcelMessagesProvider(widget.parcelId));
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission micro refusée')),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    _recordingPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
      path: _recordingPath!,
    );
    setState(() => _isRecording = true);
  }

  Future<void> _stopAndSendRecording() async {
    await _recorder.stop();
    setState(() => _isRecording = false);
    if (_recordingPath == null) return;
    setState(() => _isSending = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.sendParcelVoice(widget.parcelId, _recordingPath!);
      ref.invalidate(parcelMessagesProvider(widget.parcelId));
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur envoi audio : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
      _recordingPath = null;
    }
  }

  Future<void> _cancelRecording() async {
    await _recorder.cancel();
    setState(() => _isRecording = false);
    _recordingPath = null;
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(parcelMessagesProvider(widget.parcelId));
    final me = ref.read(authProvider).valueOrNull?.user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Messages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              // Liste messages
              SizedBox(
                height: 240,
                child: messagesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (e, _) => Center(child: Text('Erreur: $e', style: const TextStyle(color: Colors.red))),
                  data: (messages) {
                    if (messages.isEmpty) {
                      return const Center(
                        child: Text(
                          'Aucun message.\nEnvoyez une instruction au livreur.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      );
                    }
                    _scrollToBottom();
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (context, i) => _MessageBubble(
                        message: messages[i],
                        isMe: messages[i]['sender_id'] == me?.id,
                      ),
                    );
                  },
                ),
              ),

              // Composer
              if (!widget.isClosed) ...[
                const Divider(height: 1),
                _buildComposer(),
              ] else
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Messagerie fermée (livraison terminée)',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComposer() {
    if (_isRecording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Enregistrement en cours…',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey),
              onPressed: _cancelRecording,
              tooltip: 'Annuler',
            ),
            IconButton(
              icon: const Icon(Icons.send, color: Colors.blue),
              onPressed: _stopAndSendRecording,
              tooltip: 'Envoyer',
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Écrire un message…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                isDense: true,
              ),
              onSubmitted: (_) => _sendText(),
            ),
          ),
          const SizedBox(width: 6),
          // Bouton micro (maintenir pour enregistrer)
          GestureDetector(
            onLongPressStart: (_) => _startRecording(),
            onLongPressEnd:   (_) => _stopAndSendRecording(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic, size: 20, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 6),
          // Bouton envoyer texte
          GestureDetector(
            onTap: _isSending ? null : _sendText,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _isSending ? Colors.grey.shade300 : Theme.of(context).primaryColor,
                shape: BoxShape.circle,
              ),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bulle de message ───────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMe});
  final Map<String, dynamic> message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final role   = message['sender_role'] as String? ?? '';
    final type   = message['type'] as String? ?? 'text';
    final name   = message['sender_name'] as String? ?? role;
    final time   = _formatTime(message['created_at']);

    final Color bubbleColor;
    final Color textColor;
    if (isMe) {
      bubbleColor = Theme.of(context).primaryColor;
      textColor   = Colors.white;
    } else if (role == 'driver') {
      bubbleColor = Colors.orange.shade100;
      textColor   = Colors.orange.shade900;
    } else {
      bubbleColor = Colors.grey.shade200;
      textColor   = Colors.black87;
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(14),
            topRight:    const Radius.circular(14),
            bottomLeft:  Radius.circular(isMe ? 14 : 2),
            bottomRight: Radius.circular(isMe ? 2 : 14),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                _roleLabel(role, name),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: textColor.withOpacity(0.7),
                ),
              ),
            if (type == 'voice')
              _AudioPlayer(url: message['content']?.toString() ?? '', color: textColor)
            else
              Text(
                message['content']?.toString() ?? '',
                style: TextStyle(color: textColor, fontSize: 14),
              ),
            const SizedBox(height: 2),
            Text(
              time,
              style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.6)),
            ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role, String name) {
    if (name.isNotEmpty) return name;
    return switch (role) {
      'sender'    => 'Expéditeur',
      'recipient' => 'Destinataire',
      'driver'    => 'Livreur',
      _           => role,
    };
  }

  String _formatTime(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = ts is String ? DateTime.parse(ts).toLocal() : DateTime.now();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

// ── Lecteur audio inline ───────────────────────────────────────────────────

class _AudioPlayer extends StatefulWidget {
  const _AudioPlayer({required this.url, required this.color});
  final String url;
  final Color  color;

  @override
  State<_AudioPlayer> createState() => _AudioPlayerState();
}

class _AudioPlayerState extends State<_AudioPlayer> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(widget.url));
    }
    setState(() => _state = _player.state);
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _state == PlayerState.playing;
    return GestureDetector(
      onTap: _toggle,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPlaying ? Icons.pause_circle : Icons.play_circle,
            color: widget.color,
            size: 28,
          ),
          const SizedBox(width: 6),
          Text(
            isPlaying ? 'En lecture…' : 'Note vocale',
            style: TextStyle(color: widget.color, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
