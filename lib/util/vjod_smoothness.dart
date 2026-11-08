// VJOD 5.3: how smooth each screen really is on this device. Every frame
// Flutter draws is timed; a frame over [slowMs] is one the eye sees as a jolt.
// Kept per screen (the route path), shown in « À propos », so « l'appli est
// lente » turns into « tel écran rate une image sur trois ».
//
// VJOD 5.6: and how long each screen takes to settle once opened: from the
// moment it is shown to the last frame before the screen goes still (nothing
// left to load, no spinner turning). Screens that never go still (a trailer,
// a live channel) are left out.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class VjodSmoothness {
  VjodSmoothness._();

  /// Above this, a frame misses the 60 images per second (16 ms) by enough to
  /// be seen: 2 images.
  static const slowMs = 32;
  static const _keepScreens = 14;

  /// The screen counts as settled after this long without a new frame.
  static const stillAfter = Duration(milliseconds: 300);

  /// Past this, the screen is animated rather than loading: not measured.
  static const maxOpen = Duration(seconds: 15);

  static final _frames = <String, int>{};
  static final _slow = <String, int>{};
  static final _worst = <String, int>{};
  static final _opens = <String, List<int>>{};
  static String Function()? _screen;
  static bool _started = false;

  static String? _openName;
  static DateTime? _openAt;
  static DateTime? _lastFrameAt;
  static Timer? _watch;

  /// Starts timing frames. [screen] names the screen on display (the route
  /// path); [routes] says when it changes. Called once, from main.
  static void start(String Function() screen, [Listenable? routes]) {
    if (_started) return;
    _started = true;
    _screen = screen;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    SchedulerBinding.instance.addPersistentFrameCallback((_) => _lastFrameAt = DateTime.now());
    routes?.addListener(() => opened(screenName(screen()), DateTime.now()));
  }

  static void _onTimings(List<FrameTiming> timings) {
    final name = _screen?.call() ?? '?';
    for (final t in timings) {
      add(name, t.totalSpan.inMilliseconds);
    }
  }

  /// [name] was just shown, at [at]: its settling time starts.
  static void opened(String name, DateTime at) {
    if (name == _openName && _openAt != null) return;
    _openName = name;
    _openAt = at;
    _lastFrameAt = at;
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(milliseconds: 100), (_) => check(DateTime.now()));
  }

  /// Whether the screen being opened has gone still by [now].
  static void check(DateTime now) {
    final name = _openName, at = _openAt, last = _lastFrameAt;
    if (name == null || at == null || last == null) return;
    if (now.difference(at) > maxOpen) return _stopWatch();
    if (now.difference(last) < stillAfter) return;
    settled(name, last.difference(at).inMilliseconds);
    _stopWatch();
  }

  static void _stopWatch() {
    _watch?.cancel();
    _watch = null;
    _openAt = null;
  }

  /// [screen] took [ms] to settle.
  static void settled(String screen, int ms) {
    final list = _opens.putIfAbsent(screen, () => []);
    list.add(ms < 0 ? 0 : ms);
    if (list.length > 30) list.removeAt(0);
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
      _opens.remove(least);
    }
    _frames[name] = (_frames[name] ?? 0) + 1;
    if (ms > slowMs) _slow[name] = (_slow[name] ?? 0) + 1;
    if (ms > (_worst[name] ?? 0)) _worst[name] = ms;
  }

  static final _id = RegExp(r'^([0-9a-fA-F]{12,}|[0-9]+|tmdb[-:]?[0-9]+)$');

  /// A route path as a short name, without the ids: « /item/abc123/list »
  /// becomes « /item/list », « / » the Accueil.
  static String screenName(String path) {
    final parts = path
        .split('?')
        .first
        .split('/')
        .where((p) => p.isNotEmpty && !_id.hasMatch(p))
        .take(2)
        .toList();
    if (parts.isEmpty) return 'Accueil';
    return '/${parts.join('/')}';
  }

  /// The share of slow frames on [screen], from 0 to 100, or null if it was
  /// barely drawn (too few frames to say).
  static int? slowPercent(String screen) {
    final n = _frames[screen] ?? 0;
    if (n < 30) return null;
    return ((_slow[screen] ?? 0) * 100 / n).round();
  }

  /// The usual time [screen] takes to settle (the median), in ms, or null.
  static int? openMs(String screen) {
    final l = [...?_opens[screen]]..sort();
    if (l.isEmpty) return null;
    return l[l.length ~/ 2];
  }

  static String _sec(int ms) => '${(ms / 1000).toStringAsFixed(1).replaceAll('.', ',')} s';

  /// One line per screen, the jerkiest first: « /item : 18 % d'images
  /// saccadées, pire 240 ms (530 images) · prêt en 1,2 s ».
  static List<String> lines() {
    final names = _frames.keys.where((s) => slowPercent(s) != null || openMs(s) != null).toList()
      ..sort((a, b) => (slowPercent(b) ?? 0).compareTo(slowPercent(a) ?? 0));
    return [
      for (final s in names)
        [
          s,
          ' : ',
          if (slowPercent(s) != null)
            '${slowPercent(s)} % d’images saccadées, pire ${_worst[s]} ms (${_frames[s]} images)',
          if (slowPercent(s) != null && openMs(s) != null) ' · ',
          if (openMs(s) != null) 'prêt en ${_sec(openMs(s)!)} (${_opens[s]!.length} ouvertures)',
        ].join(),
    ];
  }

  static void reset() {
    _frames.clear();
    _slow.clear();
    _worst.clear();
    _opens.clear();
    _stopWatch();
    _openName = null;
  }
}
