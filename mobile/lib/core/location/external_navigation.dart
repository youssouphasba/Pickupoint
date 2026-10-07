import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

enum NavigationApp { googleMaps, waze }

class ExternalNavigation {
  static List<Uri> destinations({
    required NavigationApp app,
    required double latitude,
    required double longitude,
    required TargetPlatform platform,
  }) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return const [];
    }
    final point = '$latitude,$longitude';
    return [
      if (app == NavigationApp.waze)
        Uri.parse('waze://ul?ll=$point&navigate=yes')
      else if (platform == TargetPlatform.iOS)
        Uri.parse('comgooglemaps://?daddr=$point&directionsmode=driving')
      else if (platform == TargetPlatform.android)
        Uri.parse('google.navigation:q=$point&mode=d'),
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': point,
        'travelmode': 'driving',
      }),
    ];
  }

  static Future<bool> open({
    required NavigationApp app,
    required double latitude,
    required double longitude,
    TargetPlatform? platform,
    Future<bool> Function(Uri)? launcher,
  }) async {
    final launch = launcher ??
        (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
    for (final uri in destinations(
      app: app,
      latitude: latitude,
      longitude: longitude,
      platform: platform ?? defaultTargetPlatform,
    )) {
      try {
        if (await launch(uri)) return true;
      } catch (_) {}
    }
    return false;
  }
}
