import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';

void showSuccessCelebration(BuildContext context, {required String message}) {
  if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;

  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _SuccessCelebration(
      message: message,
      onFinished: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _SuccessCelebration extends StatefulWidget {
  const _SuccessCelebration({required this.message, required this.onFinished});

  final String message;
  final VoidCallback onFinished;

  @override
  State<_SuccessCelebration> createState() => _SuccessCelebrationState();
}

class _SuccessCelebrationState extends State<_SuccessCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final fade = CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.65, 1, curve: Curves.easeIn),
          );
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CelebrationPainter(_controller.value),
                ),
              ),
              Align(
                alignment: const Alignment(0, -0.2),
                child: FadeTransition(
                  opacity: Tween<double>(begin: 1, end: 0).animate(fade),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.86, end: 1).animate(
                      CurvedAnimation(
                        parent: _controller,
                        curve: AppMotion.emphasizedCurve,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              widget.message,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF172033),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter(this.progress);

  final double progress;
  static const _colors = [
    Color(0xFF0A9F68),
    Color(0xFFFFC400),
    Color(0xFF2374E1),
    Color(0xFFE84A5F),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(19);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 32; i++) {
      final startX = size.width * (0.18 + random.nextDouble() * 0.64);
      final startY = size.height * (0.22 + random.nextDouble() * 0.16);
      final drift = (random.nextDouble() - 0.5) * size.width * 0.28;
      final x = startX + drift * progress;
      final y =
          startY + size.height * (0.28 + random.nextDouble() * 0.18) * progress;
      final radius = 2.5 + random.nextDouble() * 3;
      paint.color = _colors[i % _colors.length].withValues(
        alpha: (1 - progress * 0.35).clamp(0, 1),
      );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(progress * (i.isEven ? 3 : -3));
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset.zero, width: radius * 1.6, height: radius * 3),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
