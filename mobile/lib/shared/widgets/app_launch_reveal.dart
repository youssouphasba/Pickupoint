import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';

class AppLaunchReveal extends StatefulWidget {
  const AppLaunchReveal({
    super.key,
    required this.child,
    this.onFinished,
  });

  final Widget child;
  final VoidCallback? onFinished;

  @override
  State<AppLaunchReveal> createState() => _AppLaunchRevealState();
}

class _AppLaunchRevealState extends State<AppLaunchReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _overlayOpacity;
  var _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.launch,
    );
    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.38, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.76, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.62, curve: AppMotion.emphasizedCurve),
      ),
    );
    _overlayOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(1), weight: 70),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
    ]).animate(_controller);
    _controller.forward().whenComplete(_finish);
  }

  void _finish() {
    if (!mounted || _finished) return;
    setState(() => _finished = true);
    widget.onFinished?.call();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if ((MediaQuery.maybeOf(context)?.disableAnimations ?? false) &&
        !_finished) {
      _controller.value = 1;
      _finish();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.child;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: FadeTransition(
            opacity: _overlayOpacity,
            child: ColoredBox(
              color: Colors.white,
              child: SafeArea(
                child: Center(
                  child: FadeTransition(
                    opacity: _logoOpacity,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Image.asset(
                        'assets/logo_transparent.png',
                        width: 230,
                        height: 230,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
