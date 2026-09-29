import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';

class AnimatedNumberText extends StatelessWidget {
  const AnimatedNumberText({
    super.key,
    required this.value,
    required this.formatter,
    this.style,
    this.duration = AppMotion.dataReveal,
  });

  final num value;
  final String Function(double value) formatter;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (animationsDisabled) {
      return Text(formatter(value.toDouble()), style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: AppMotion.standardCurve,
      builder: (context, animatedValue, _) => Text(
        formatter(animatedValue),
        style: style,
      ),
    );
  }
}
