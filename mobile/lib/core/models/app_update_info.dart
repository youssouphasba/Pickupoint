import 'dart:io';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.enabled,
    required this.message,
    required this.latestVersion,
    required this.minVersion,
    required this.storeUrl,
  });

  final bool enabled;
  final String message;
  final String latestVersion;
  final String minVersion;
  final String storeUrl;

  factory AppUpdateInfo.fromSettings(Map<String, dynamic> json) {
    final update = Map<String, dynamic>.from(
      json['app_update'] as Map? ?? const {},
    );
    final platform = Platform.isIOS ? 'ios' : 'android';
    final platformData = Map<String, dynamic>.from(
      update[platform] as Map? ?? const {},
    );
    return AppUpdateInfo(
      enabled: update['enabled'] as bool? ?? true,
      message: update['message'] as String? ??
          'Une nouvelle version de Denkma est disponible.',
      latestVersion: platformData['latest_version'] as String? ?? '',
      minVersion: platformData['min_version'] as String? ?? '',
      storeUrl: platformData['store_url'] as String? ?? '',
    );
  }

  AppUpdateDecision evaluate(String installedVersion) {
    if (!enabled) return AppUpdateDecision.none;
    if (_isVersionLower(installedVersion, minVersion)) {
      return AppUpdateDecision.required;
    }
    if (_isVersionLower(installedVersion, latestVersion)) {
      return AppUpdateDecision.available;
    }
    return AppUpdateDecision.none;
  }
}

enum AppUpdateDecision { none, available, required }

bool _isVersionLower(String current, String target) {
  final targetParts = _versionParts(target);
  if (targetParts.isEmpty) return false;
  final currentParts = _versionParts(current);
  final length = currentParts.length > targetParts.length
      ? currentParts.length
      : targetParts.length;
  for (var i = 0; i < length; i++) {
    final currentValue = i < currentParts.length ? currentParts[i] : 0;
    final targetValue = i < targetParts.length ? targetParts[i] : 0;
    if (currentValue < targetValue) return true;
    if (currentValue > targetValue) return false;
  }
  return false;
}

List<int> _versionParts(String value) {
  final version = value.trim().split('+').first;
  if (version.isEmpty) return const [];
  return version
      .split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
}
