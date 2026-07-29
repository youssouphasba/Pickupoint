import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_theme.dart';

class ParcelStatusBadge extends StatefulWidget {
  const ParcelStatusBadge({
    super.key,
    required this.status,
  });

  final String status;

  @override
  State<ParcelStatusBadge> createState() => _ParcelStatusBadgeState();
}

class _ParcelStatusBadgeState extends State<ParcelStatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: AppMotion.emphasized,
    );
    _pulse = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 1.08)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 42,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.08, end: 1)
            .chain(CurveTween(curve: AppMotion.standardCurve)),
        weight: 58,
      ),
    ]).animate(_pulseController);
  }

  @override
  void didUpdateWidget(covariant ParcelStatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorForStatus(widget.status);
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) => Transform.scale(
        scale: _pulse.value,
        child: AnimatedContainer(
          duration: AppMotion.standard,
          curve: AppMotion.standardCurve,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color),
            boxShadow: _pulseController.isAnimating
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.2),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: AnimatedSwitcher(
            duration: AppMotion.standard,
            switchInCurve: AppMotion.emphasizedCurve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Row(
              key: ValueKey(widget.status),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _iconForStatus(widget.status),
                  size: 13,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  _labelForStatus(widget.status).toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _colorForStatus(String status) => switch (status) {
      'created' => Colors.grey,
      'dropped_at_origin_relay' ||
      'in_transit' ||
      'at_destination_relay' =>
        AppColors.primary,
      'available_at_relay' => AppColors.warning,
      'out_for_delivery' => AppColors.purple,
      'delivered' => AppColors.success,
      'delivery_failed' => AppColors.error,
      'cancelled' || 'expired' => Colors.grey.shade700,
      _ => Colors.grey,
    };

IconData _iconForStatus(String status) => switch (status) {
      'created' => Icons.inventory_2_outlined,
      'dropped_at_origin_relay' => Icons.store_outlined,
      'in_transit' => Icons.local_shipping_outlined,
      'at_destination_relay' => Icons.store_outlined,
      'available_at_relay' => Icons.notifications_active_outlined,
      'out_for_delivery' => Icons.delivery_dining_outlined,
      'delivered' => Icons.check_circle_outline,
      'delivery_failed' => Icons.error_outline,
      'cancelled' => Icons.cancel_outlined,
      'expired' => Icons.timer_outlined,
      'returned' => Icons.keyboard_return,
      _ => Icons.circle_outlined,
    };

String _labelForStatus(String status) => switch (status) {
      'created' => 'Créé',
      'dropped_at_origin_relay' => 'Déposé au relais',
      'in_transit' => 'En transit',
      'at_destination_relay' => 'Au relais destination',
      'available_at_relay' => 'Disponible au relais',
      'out_for_delivery' => 'En livraison',
      'delivered' => 'Livré',
      'delivery_failed' => 'Échec livraison',
      'cancelled' => 'Annulé',
      'expired' => 'Expiré',
      'returned' => 'Retourné',
      _ => status,
    };
