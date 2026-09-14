import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

abstract final class ActionFeedback {
  static final _player = AudioPlayer();

  static Future<void> confirm() async {
    await HapticFeedback.mediumImpact();
    await _play('sounds/denkma_status.wav');
  }

  static Future<void> mission() async {
    await HapticFeedback.heavyImpact();
    await _play('sounds/denkma_mission.wav');
  }

  static Future<void> message() async {
    await HapticFeedback.lightImpact();
    await _play('sounds/denkma_message.wav');
  }

  static Future<void> error() async {
    await HapticFeedback.vibrate();
    await _play('sounds/denkma_status.wav');
  }

  static Future<void> _play(String asset) async {
    try {
      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (_) {}
  }
}
