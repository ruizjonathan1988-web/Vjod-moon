// VJOD 4.20: how long each service takes to answer on this device (Jellyfin,
// Ma TV, Seerr), the last 60 answers of each. Shown in « À propos » and sent
// to Ma TV every few minutes, so the Ma TV page tells which one is slow, on
// which device.
import 'dart:async';

import 'package:dio/dio.dart';

class VjodTimings {
  VjodTimings._();

  static const _keep = 60;
  static final _ms = <String, List<int>>{};
  static final _slow = <String, String>{};
  static int _changes = 0;

  /// One answer of [service] that took [d] ([what]: which call, kept for the
  /// slowest).
  static void add(String service, Duration d, {String what = ''}) {
    final list = _ms.putIfAbsent(service, () => <int>[]);
    final ms = d.inMilliseconds;
    if (what.isNotEmpty && (list.isEmpty || ms >= list.reduce((a, b) => a > b ? a : b))) _slow[service] = what;
    list.add(ms);
    if (list.length > _keep) list.removeAt(0);
    _changes++;
  }

  /// Times [call] as an answer of [service].
  static Future<T> time<T>(String service, Future<T> call, {String what = ''}) async {
    final sw = Stopwatch()..start();
    try {
      return await call;
    } finally {
      add(service, sw.elapsed, what: what);
    }
  }

  static int _at(List<int> sorted, double q) => sorted[((sorted.length - 1) * q).round()];

  /// Per service: the usual time (median), the slow ones (9 in 10 are
  /// faster), how many answers, and the slowest call.
  static Map<String, ({int median, int p90, int count, String slowest})> summary() => {
    for (final e in _ms.entries)
      if (e.value.isNotEmpty)
        e.key: (() {
          final s = [...e.value]..sort();
          return (median: _at(s, .5), p90: _at(s, .9), count: s.length, slowest: _slow[e.key] ?? '');
        })(),
  };

  static String fmt(int ms) => ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1).replaceAll('.', ',')} s';

  /// « Jellyfin 240 ms (lent : 1,2 s) » per service, the slowest first.
  static List<String> lines() {
    final s = summary().entries.toList()..sort((a, b) => b.value.p90.compareTo(a.value.p90));
    return [
      for (final e in s) '${e.key} : ${fmt(e.value.median)} d’habitude, ${fmt(e.value.p90)} quand c’est lent (${e.value.count} réponses)',
    ];
  }

  /// Whether something was timed since [since] (a value of [mark]).
  static int mark() => _changes;
  static bool changedSince(int since) => _changes != since;

  /// For tests.
  static void reset() {
    _ms.clear();
    _slow.clear();
    _changes = 0;
  }
}

/// Times every answer of a Dio client as [service].
class VjodTimingInterceptor extends Interceptor {
  final String service;
  VjodTimingInterceptor(this.service);

  static const _key = 'vjod_t0';

  static String _what(RequestOptions o) {
    final p = o.uri.path;
    // the kind of call, not the ids in it
    return p.replaceAll(RegExp(r'[0-9a-fA-F]{16,}|\d+'), '…');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_key] = DateTime.now().microsecondsSinceEpoch;
    handler.next(options);
  }

  void _done(RequestOptions o) {
    final t0 = o.extra[_key];
    if (t0 is! int) return;
    final path = o.uri.path;
    // playback progress pings and images say nothing about lists
    if (path.contains('/Sessions/Playing') || path.contains('/Images/')) return;
    VjodTimings.add(service, Duration(microseconds: DateTime.now().microsecondsSinceEpoch - t0), what: _what(o));
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _done(response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _done(err.requestOptions);
    handler.next(err);
  }
}

/// VJOD 4.22: what the Replay row of the Home did on this device, step by
/// step (asked, answered, put in place, taken away), shown in « À propos »
/// so a missing row says why without going through Ma TV.
class ReplayTrace {
  ReplayTrace._();

  static const _keep = 14;
  static final _lines = <String>[];

  static void note(String what) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _lines.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $what');
    if (_lines.length > _keep) _lines.removeAt(0);
  }

  static List<String> lines() => List.unmodifiable(_lines);

  /// For tests.
  static void reset() => _lines.clear();
}
