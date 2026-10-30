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
  static const _window = Duration(seconds: 60);
  static const _maxMarks = 60;
  static final _watch = Stopwatch();
  static final _marks = <(String, int)>[];
  static Timer? _save;

  static void start() {
    if (_watch.isRunning) return;
    _watch.start();
    _marks.add(("Lancement de l'app", 0));
  }

  /// Notes [label] the first time it happens during the first minute of this
  /// launch; what was noted is saved a moment later.
  static void mark(String label) {
    if (!_watch.isRunning || _watch.elapsed > _window) return;
    if (_marks.length >= _maxMarks) return;
    if (_marks.any((m) => m.$1 == label)) return;
    _marks.add((label, _watch.elapsedMilliseconds));
    _save?.cancel();
    _save = Timer(const Duration(seconds: 1), _write);
  }

  /// Kept for the calls that close a step; the timing goes on after it, so
  /// what comes later (the end of the opening, rows arriving) is noted too.
  static Future<void> finish(String label) async => mark(label);

  static Future<void> _write() async {
    try {
      final p = await SharedPreferences.getInstance();
      final sorted = [..._marks]..sort((a, b) => a.$2.compareTo(b.$2));
      await p.setStringList(_key, [for (final m in sorted) '${m.$2}|${m.$1}']);
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
