import 'dart:async';

import 'package:flutter/material.dart';

class PickupConfirmationCountdownBadge extends StatefulWidget {
  const PickupConfirmationCountdownBadge({
    super.key,
    required this.deadline,
  });

  final DateTime deadline;

  @override
  State<PickupConfirmationCountdownBadge> createState() =>
      _PickupConfirmationCountdownBadgeState();
}

class _PickupConfirmationCountdownBadgeState
    extends State<PickupConfirmationCountdownBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.deadline.toLocal().difference(DateTime.now());
    final totalSeconds = remaining.inSeconds < 0 ? 0 : remaining.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final color = totalSeconds == 0
        ? Colors.red
        : totalSeconds < 5 * 60
            ? Colors.red
            : totalSeconds < 10 * 60
                ? Colors.orange
                : Colors.green;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: color, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              totalSeconds == 0
                  ? 'Délai de récupération écoulé'
                  : 'Temps pour récupérer le colis',
              style: TextStyle(
                color: color.shade800,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            style: TextStyle(
              color: color.shade800,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
