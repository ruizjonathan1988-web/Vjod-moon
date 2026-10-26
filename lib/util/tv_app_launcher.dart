import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A known external IPTV player the TV tab can open.
class TvApp {
  final String id;
  final String label;
  final String package;

  /// Whether it is meant for the big screen (TV) or the phone.
  final bool forTv;

  const TvApp({
    required this.id,
    required this.label,
    required this.package,
    this.forTv = true,
  });

  static const tivimate = TvApp(
    id: 'tivimate',
    label: 'TiviMate',
    package: 'ar.tvplayer.tv',
  );
  static const ottNavigator = TvApp(
    id: 'ott',
    label: 'OTT Navigator',
    package: 'studio.scillarium.ottnavigator',
    forTv: true,
  );
  static const smarters = TvApp(
    id: 'smarters',
    label: 'IPTV Smarters',
    package: 'com.nst.iptvsmarterspro',
    forTv: false,
  );

  static const all = [tivimate, ottNavigator, smarters];

  static TvApp byId(String? id) =>
      all.firstWhere((a) => a.id == id, orElse: () => tivimate);
}

/// Bridges to the native launcher. Every call is safe off Android: it simply
/// reports "not installed" / "nothing opened" so the UI can fall back to
/// showing instructions.
class TvAppLauncher {
  static const _channel = MethodChannel('org.moonfin.vjod/tv_launcher');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isInstalled(TvApp app) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'isInstalled',
            {'package': app.package},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> launch(TvApp app) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'launch',
            {'package': app.package},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openStore(TvApp app) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openStore',
            {'package': app.package},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
