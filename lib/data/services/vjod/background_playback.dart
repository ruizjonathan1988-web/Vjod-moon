// VJOD 4.17: a Ma TV channel or an IPTV film keeps playing with the screen
// off or the app reduced (phone and tablet, Android). While a VJOD player is
// open, a media notification (Pause / Lecture, Arrêter) keeps the app alive
// with the Wi-Fi awake; Moonfin's lifecycle handler then leaves the player
// alone instead of releasing it when the app goes to the background.
//
// The notification is started with the player, in the foreground: Android
// does not allow it to start once the app is already in the background.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../../../util/platform_detection.dart';

class VjodBackgroundPlayback {
  VjodBackgroundPlayback._();

  static const _channel = MethodChannel('vjod/background');
  static const prefKey = 'vjod_background_playback';

  static Object? _owner;
  static void Function(String command)? _onCommand;
  static bool _bound = false;
  static String _title = '';
  static String _text = '';

  /// Whether this device may play on in the background (phone or tablet on
  /// Android; set per device, on by default).
  static bool get supported => !kIsWeb && PlatformDetection.isAndroid && !PlatformDetection.isTV;

  static bool get enabled {
    if (!supported) return false;
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<PreferenceStore>()) return true;
    try {
      return getIt<PreferenceStore>().getBool(prefKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool on) async {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<PreferenceStore>()) await getIt<PreferenceStore>().setBool(prefKey, on);
    if (!on && _owner != null) await _stopNative();
  }

  /// Whether a VJOD player is open with background playback on: Moonfin's
  /// lifecycle handler must not release the player then.
  static bool get keepsPlaying => _owner != null;

  /// A VJOD player opens: [onCommand] receives `playPause` and `stop` from
  /// the notification.
  static Future<void> start(
    Object owner, {
    required String title,
    String text = '',
    required void Function(String command) onCommand,
  }) async {
    if (!enabled) return;
    _owner = owner;
    _onCommand = onCommand;
    _title = title;
    _text = text;
    if (!_bound) {
      _bound = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'command') _onCommand?.call('${call.arguments}');
        return null;
      });
    }
    await _send(playing: true);
  }

  /// The channel changed, or the picture was paused.
  static Future<void> update(Object owner, {String? title, String? text, bool playing = true}) async {
    if (!identical(owner, _owner)) return;
    final changed = (title != null && title != _title) || (text != null && text != _text);
    _title = title ?? _title;
    _text = text ?? _text;
    if (changed || !playing) await _send(playing: playing);
  }

  /// The player closes.
  static Future<void> stop(Object owner) async {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _onCommand = null;
    await _stopNative();
  }

  static Future<void> _send({required bool playing}) async {
    try {
      await _channel.invokeMethod<bool>('start', {'title': _title, 'text': _text, 'playing': playing});
    } catch (_) {}
  }

  static Future<void> _stopNative() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {}
  }
}
