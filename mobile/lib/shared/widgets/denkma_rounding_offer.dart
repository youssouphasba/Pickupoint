import 'package:flutter/material.dart';

import '../utils/currency_format.dart';

class DenkmaRoundingOffer extends StatelessWidget {
  const DenkmaRoundingOffer({
    super.key,
    required this.amount,
    this.includedInGain = false,
    this.onColoredBackground = false,
  });

  final double amount;
  final bool includedInGain;
  final bool onColoredBackground;

  @override
  Widget build(BuildContext context) {
    if (!amount.isFinite || amount <= 0) return const SizedBox.shrink();
    final label = '${formatXofExact(amount)} offerts par Denkma'
        '${includedInGain ? ' · inclus dans votre gain' : ''}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color:
              onColoredBackground ? Colors.green.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: onColoredBackground
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
              : EdgeInsets.zero,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.green.shade800,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
