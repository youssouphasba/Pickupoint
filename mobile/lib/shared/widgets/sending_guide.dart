import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/auth/auth_provider.dart';

class SendingGuide {
  const SendingGuide({required this.videoUrl, this.thumbnailUrl});

  final Uri videoUrl;
  final String? thumbnailUrl;

  static SendingGuide? fromJson(dynamic json) {
    if (json is! Map) return null;
    final rawUrl = json['video_url'];
    if (rawUrl is! String) return null;
    final url = Uri.tryParse(rawUrl.trim());
    if (url == null || url.scheme != 'https' || url.host.isEmpty) return null;
    final rawThumbnail = json['thumbnail_url'];
    final thumbnail =
        rawThumbnail is String ? Uri.tryParse(rawThumbnail.trim()) : null;
    return SendingGuide(
        videoUrl: url,
        thumbnailUrl: thumbnail?.scheme == 'https' && thumbnail!.host.isNotEmpty
            ? thumbnail.toString()
            : null);
  }
}

final sendingGuideProvider =
    FutureProvider.autoDispose<SendingGuide?>((ref) async {
  final response = await ref.watch(apiClientProvider).getPublicAppSettings();
  return SendingGuide.fromJson(response.data['sending_guide']);
});

class SendingGuideEntry extends ConsumerWidget {
  const SendingGuideEntry({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guide = ref.watch(sendingGuideProvider).asData?.value;
    if (guide == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: compact
          ? const EdgeInsets.only(bottom: 20)
          : const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => SendingGuideVideoScreen(guide: guide),
          )),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              SizedBox(
                width: compact ? 48 : 80,
                height: compact ? 48 : 64,
                child: Stack(fit: StackFit.expand, children: [
                  ColoredBox(color: colors.primaryContainer),
                  if (!compact && guide.thumbnailUrl != null)
                    Image.network(guide.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  Center(
                      child: Icon(Icons.play_circle_fill,
                          color: colors.primary, size: 36)),
                ]),
              ),
              const SizedBox(width: 12),
              const Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Comment envoyer un colis ?',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 4),
                  Text('Regarder la vidéo explicative'),
                ],
              )),
            ]),
          ),
        ),
      ),
    );
  }
}

class SendingGuideVideoScreen extends StatefulWidget {
  const SendingGuideVideoScreen({super.key, required this.guide});

  final SendingGuide guide;

  @override
  State<SendingGuideVideoScreen> createState() =>
      _SendingGuideVideoScreenState();
}

class _SendingGuideVideoScreenState extends State<SendingGuideVideoScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    final previous = _controller;
    final controller = VideoPlayerController.networkUrl(widget.guide.videoUrl);
    _controller = controller;
    setState(() {
      _loading = true;
      _failed = false;
    });
    await previous?.dispose();
    try {
      await controller.initialize();
      if (!mounted || _controller != controller) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted || _controller != controller) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Comment envoyer un colis ?')),
      body: SafeArea(
          child: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _failed || controller == null
                ? _VideoError(onRetry: _initialize)
                : ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      if (value.hasError) {
                        return _VideoError(onRetry: _initialize);
                      }
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          AspectRatio(
                            aspectRatio: value.aspectRatio > 0
                                ? value.aspectRatio
                                : 16 / 9,
                            child: ColoredBox(
                                color: Colors.black,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    VideoPlayer(controller),
                                    if (value.isBuffering)
                                      const Center(
                                          child: CircularProgressIndicator()),
                                  ],
                                )),
                          ),
                          const SizedBox(height: 12),
                          VideoProgressIndicator(controller,
                              allowScrubbing: true,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12)),
                          IconButton.filled(
                            tooltip:
                                value.isPlaying ? 'Pause' : 'Lire la vidéo',
                            iconSize: 40,
                            icon: Icon(value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow),
                            onPressed: () async {
                              if (value.isPlaying) {
                                await controller.pause();
                              } else {
                                if (value.position >= value.duration) {
                                  await controller.seekTo(Duration.zero);
                                }
                                if (mounted && _controller == controller) {
                                  await controller.play();
                                }
                              }
                            },
                          ),
                        ]),
                      );
                    },
                  ),
      )),
    );
  }
}

class _VideoError extends StatelessWidget {
  const _VideoError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Impossible de lire la vidéo. Vérifiez votre connexion et réessayez.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer')),
        ]),
      );
}
