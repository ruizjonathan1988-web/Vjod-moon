// VJOD 5.3: how smooth each screen really is on this device. Every frame
// Flutter draws is timed; a frame over [slowMs] is one the eye sees as a jolt.
// Kept per screen (the route path), shown in « À propos », so « l'appli est
// lente » turns into « tel écran rate une image sur trois ».
import 'package:flutter/scheduler.dart';

class VjodSmoothness {
  VjodSmoothness._();

  /// Above this, a frame misses the 60 images per second (16 ms) by enough to
  /// be seen: 2 images.
  static const slowMs = 32;
  static const _keepScreens = 12;

  static final _frames = <String, int>{};
  static final _slow = <String, int>{};
  static final _worst = <String, int>{};
  static String Function()? _screen;
  static bool _started = false;

  /// Starts timing frames. [screen] names the screen on display (the route
  /// path); called once, from main.
  static void start(String Function() screen) {
    if (_started) return;
    _started = true;
    _screen = screen;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    final name = _screen?.call() ?? '?';
    for (final t in timings) {
      add(name, t.totalSpan.inMilliseconds);
    }
  }

  /// One frame of [ms] drawn on [screen].
  static void add(String screen, int ms) {
    final name = screenName(screen);
    if (!_frames.containsKey(name) && _frames.length >= _keepScreens) {
      // The screen seen least goes, so the list stays short.
      final least = _frames.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
      _frames.remove(least);
      _slow.remove(least);
      _worst.remove(least);
    }
    _frames[name] = (_frames[name] ?? 0) + 1;
    if (ms > slowMs) _slow[name] = (_slow[name] ?? 0) + 1;
    if (ms > (_worst[name] ?? 0)) _worst[name] = ms;
  }

  /// A route path as a short name: « /item/abc123 » becomes « /item ».
  static String screenName(String path) {
    final parts = path.split('?').first.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'Accueil';
    return '/${parts.first}';
  }

  /// The share of slow frames on [screen], from 0 to 100, or null if it was
  /// barely drawn (too few frames to say).
  static int? slowPercent(String screen) {
    final n = _frames[screen] ?? 0;
    if (n < 30) return null;
    return ((_slow[screen] ?? 0) * 100 / n).round();
  }

  /// One line per screen, the jerkiest first: « /item : 18 % d'images
  /// saccadées, pire 240 ms (530 images) ».
  static List<String> lines() {
    final names = _frames.keys.where((s) => slowPercent(s) != null).toList()
      ..sort((a, b) => slowPercent(b)!.compareTo(slowPercent(a)!));
    return [
      for (final s in names)
        '$s : ${slowPercent(s)} % d’images saccadées, pire ${_worst[s]} ms (${_frames[s]} images)',
    ];
  }

  static void reset() {
    _frames.clear();
    _slow.clear();
    _worst.clear();
  }
}
