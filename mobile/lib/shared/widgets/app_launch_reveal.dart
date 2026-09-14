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
  late final Animation<double> _logoRide;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineOffset;
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
    _logoRide = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: -10, end: 8)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 8, end: -4)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -4, end: 0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
    ]).animate(_controller);
    _taglineOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.42, 0.82, curve: Curves.easeOut),
    );
    _taglineOffset = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.42, 0.9, curve: Curves.easeOutCubic),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: _logoOpacity,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: SizedBox(
                            width: 230,
                            height: 230,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/logo_base.png',
                                  width: 230,
                                  height: 230,
                                  fit: BoxFit.contain,
                                ),
                                Positioned(
                                  top: 15,
                                  left: 0,
                                  right: 0,
                                  child: AnimatedBuilder(
                                    animation: _logoRide,
                                    builder: (context, child) =>
                                        Transform.translate(
                                      offset: Offset(_logoRide.value, 0),
                                      child: child,
                                    ),
                                    child: Image.asset(
                                      'assets/logo_moto.png',
                                      width: 230,
                                      height: 154,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SlideTransition(
                        position: _taglineOffset,
                        child: FadeTransition(
                          opacity: _taglineOpacity,
                          child: const Text(
                            'Livrez sans stress',
                            style: TextStyle(
                              color: Color(0xFF087F43),
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                            ),
                          ),
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
  }
}
