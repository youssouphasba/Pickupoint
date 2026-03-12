import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class ParcelStatusBadge extends StatelessWidget {
  final String status;

  const ParcelStatusBadge({super.key, required this.status});

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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _colorForStatus(status).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _colorForStatus(status)),
      ),
      child: Text(
        _labelForStatus(status).toUpperCase(),
        style: TextStyle(
          color: _colorForStatus(status),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
