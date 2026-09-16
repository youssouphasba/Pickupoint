import 'dart:async';

import 'package:flutter/material.dart';

class MissionElapsedBadge extends StatefulWidget {
  const MissionElapsedBadge({
    super.key,
    required this.startedAt,
    this.prominent = false,
  });

  final DateTime startedAt;
  final bool prominent;

  @override
  State<MissionElapsedBadge> createState() => _MissionElapsedBadgeState();
}

class _MissionElapsedBadgeState extends State<MissionElapsedBadge> {
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
    final elapsed = DateTime.now().difference(widget.startedAt.toLocal());
    final seconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    final value = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';

    return Container(
      width: widget.prominent ? double.infinity : null,
      padding: EdgeInsets.symmetric(
        horizontal: widget.prominent ? 16 : 10,
        vertical: widget.prominent ? 11 : 7,
      ),
      decoration: BoxDecoration(
        color: widget.prominent ? Colors.blue.shade800 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(widget.prominent ? 0 : 10),
      ),
      child: Row(
        mainAxisAlignment: widget.prominent
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Icon(
            Icons.timer_outlined,
            size: widget.prominent ? 19 : 15,
            color: widget.prominent ? Colors.white : Colors.blue.shade800,
          ),
          const SizedBox(width: 7),
          Text(
            'Mission en cours · $value',
            style: TextStyle(
              color: widget.prominent ? Colors.white : Colors.blue.shade900,
              fontSize: widget.prominent ? 15 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
