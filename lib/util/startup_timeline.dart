import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Times the steps of a cold start (app ready, session, network, end of the
/// opening, home on screen, rows and banner filled) and keeps the last launch,
/// shown in Settings → About, so a slow start says where it lost its time.
///
/// Off until [start] is called from main, so tests and later screens never
/// record anything.
class StartupTimeline {
  StartupTimeline._();

  static const _key = 'vjod_startup_timeline';
  static final _watch = Stopwatch();
  static final _marks = <(String, int)>[];
  static bool _done = false;

  static void start() {
    if (_watch.isRunning) return;
    _watch.start();
    _marks.add(("Lancement de l'app", 0));
    // A launch that never reaches a full home (no server, error…) still
    // leaves what it got through.
    Timer(const Duration(seconds: 60), () => finish('Arrêt du chronomètre (60 s)'));
  }

  /// Notes [label] the first time it happens during this launch.
  static void mark(String label) {
    if (!_watch.isRunning || _done) return;
    if (_marks.any((m) => m.$1 == label)) return;
    _marks.add((label, _watch.elapsedMilliseconds));
  }

  static Future<void> finish(String label) async {
    if (!_watch.isRunning || _done) return;
    mark(label);
    _done = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key, [for (final m in _marks) '${m.$2}|${m.$1}']);
    } catch (_) {}
  }

  /// The steps of the last launch that finished timing, in milliseconds.
  static Future<List<(String, int)>> last() async {
    try {
      final p = await SharedPreferences.getInstance();
      return [
        for (final line in p.getStringList(_key) ?? const <String>[])
          if (line.contains('|'))
            (
              line.substring(line.indexOf('|') + 1),
              int.tryParse(line.substring(0, line.indexOf('|'))) ?? 0,
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// "4,4 s" style.
  static String seconds(int ms) =>
      '${(ms / 1000).toStringAsFixed(1).replaceAll('.', ',')} s';
}
