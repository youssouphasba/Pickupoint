import 'package:flutter/material.dart';

abstract final class AppMotion {
  static const instant = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 260);
  static const emphasized = Duration(milliseconds: 420);
  static const launch = Duration(milliseconds: 1050);

  static const standardCurve = Curves.easeOutCubic;
  static const emphasizedCurve = Curves.easeOutBack;
}

class DenkmaPageTransitionsBuilder extends PageTransitionsBuilder {
  const DenkmaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return child;
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.standardCurve,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 0.82, end: 1).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.045, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
