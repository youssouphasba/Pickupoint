import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../auth/auth_provider.dart';
import '../models/app_update_info.dart';

class AppUpdateState {
  const AppUpdateState({
    required this.info,
    required this.installedVersion,
    required this.decision,
  });

  final AppUpdateInfo info;
  final String installedVersion;
  final AppUpdateDecision decision;
}

final appUpdateProvider = FutureProvider<AppUpdateState>((ref) async {
  final api = ref.watch(apiClientProvider);
  final settings = await api.getPublicAppSettings();
  final info = AppUpdateInfo.fromSettings(
    settings.data as Map<String, dynamic>,
  );
  final packageInfo = await PackageInfo.fromPlatform();
  final installedVersion = packageInfo.version;
  return AppUpdateState(
    info: info,
    installedVersion: installedVersion,
    decision: info.evaluate(installedVersion),
  );
});
