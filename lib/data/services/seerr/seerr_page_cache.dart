// VJOD 5.8: the rows and grids built from Seerr (Films, Séries, Bientôt, the
// catalogue's rows, a title's similar titles…) show at once. What Seerr
// answered last time is kept, in memory and on disk: a page asked again is
// served from it straight away, and quietly asked again in the background
// when it is a few minutes old, so the next visit is up to date. Anything
// that changes something (a request, a watchlist change) empties it, so a
// title just asked for never shows as still to ask.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// How a kept answer is used.
enum SeerrCacheUse { none, serve, serveAndRefresh }

class SeerrPageCache {
  SeerrPageCache._();

  /// Served as is, without asking again.
  static const fresh = Duration(minutes: 3);

  /// Served, then asked again in the background, until it is this old.
  static const usable = Duration(hours: 24);

  static const _max = 250;
  static const _fileName = 'seerr_pages_cache.json';
  static const refreshFlag = 'vjodSeerrCacheRefresh';

  static final _entries = <String, ({DateTime at, Object data})>{};
  static bool _loaded = false;
  static Future<void>? _loading;
  static Timer? _saveTimer;

  static final _cacheable = RegExp(
    r'/Moonfin/Seerr/Api/('
    r'discover/(?!watchlist)[a-z/]+'
    r'|(movie|tv)/\d+(/(similar|recommendations))?'
    r'|collection/\d+'
    r'|person/\d+(/combined_credits)?'
    r'|search'
    r')$',
  );

  /// Whether a [method] call on [path] is kept: lists and pages read, never
  /// the viewer's own (requests, watchlist, quota) nor anything written.
  static bool cacheable(String method, String path) =>
      method.toUpperCase() == 'GET' && _cacheable.hasMatch(path.split('?').first);

  /// How an answer kept since [at] is used [now].
  static SeerrCacheUse useFor(DateTime at, DateTime now) {
    final age = now.difference(at);
    if (age.isNegative || age > usable) return SeerrCacheUse.none;
    return age < fresh ? SeerrCacheUse.serve : SeerrCacheUse.serveAndRefresh;
  }

  static Object? lookup(String key, DateTime now, {void Function()? refresh}) {
    final e = _entries[key];
    if (e == null) return null;
    final use = useFor(e.at, now);
    if (use == SeerrCacheUse.none) {
      _entries.remove(key);
      return null;
    }
    // Most recently used last, so the oldest go first when it is full.
    _entries.remove(key);
    _entries[key] = e;
    if (use == SeerrCacheUse.serveAndRefresh) refresh?.call();
    return e.data;
  }

  static void store(String key, Object data, DateTime now) {
    _entries.remove(key);
    _entries[key] = (at: now, data: data);
    while (_entries.length > _max) {
      _entries.remove(_entries.keys.first);
    }
    _scheduleSave();
  }

  /// Something changed on Seerr: nothing kept is trusted any more.
  static void clear() {
    _entries.clear();
    _scheduleSave();
  }

  static int get length => _entries.length;

  @visibleForTesting
  static void resetForTest() {
    _entries.clear();
    _loaded = true;
    _saveTimer?.cancel();
  }

  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/$_fileName');

  /// Reads what the last session kept, once.
  static Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= () async {
      try {
        final f = await _file();
        if (f.existsSync()) {
          final raw = await f.readAsString();
          final j = await compute(jsonDecode, raw);
          if (j is Map && j['v'] == 1 && j['entries'] is List) {
            final now = DateTime.now();
            for (final e in j['entries'] as List) {
              if (e is! Map) continue;
              final at = DateTime.fromMillisecondsSinceEpoch((e['at'] as num?)?.toInt() ?? 0);
              if (useFor(at, now) == SeerrCacheUse.none) continue;
              _entries['${e['k']}'] = (at: at, data: e['d'] as Object);
            }
          }
        }
      } catch (_) {}
      _loaded = true;
    }();
  }

  static void _scheduleSave() {
    if (kIsWeb) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 5), () => unawaited(_save()));
  }

  static Future<void> _save() async {
    try {
      final body = {
        'v': 1,
        'entries': [
          for (final e in _entries.entries) {'k': e.key, 'at': e.value.at.millisecondsSinceEpoch, 'd': e.value.data},
        ],
      };
      final text = await compute(jsonEncode, body);
      await (await _file()).writeAsString(text, flush: true);
    } catch (_) {}
  }
}

/// Serves kept answers before anything else runs: put first.
class SeerrCacheReadInterceptor extends Interceptor {
  SeerrCacheReadInterceptor(this._dio);
  final Dio _dio;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!SeerrPageCache.cacheable(options.method, options.path)) {
      // A request, a watchlist change, a cancel: what is kept may be wrong.
      if (options.method.toUpperCase() != 'GET') SeerrPageCache.clear();
      return handler.next(options);
    }
    if (options.extra[SeerrPageCache.refreshFlag] == true) return handler.next(options);
    if (!kIsWeb) await SeerrPageCache.ensureLoaded();
    final key = options.uri.toString();
    final data = SeerrPageCache.lookup(
      key,
      DateTime.now(),
      refresh: () => unawaited(
        _dio
            .fetch<dynamic>(options.copyWith(extra: {...options.extra, SeerrPageCache.refreshFlag: true}))
            .then((_) {}, onError: (_) {}),
      ),
    );
    if (data == null) return handler.next(options);
    handler.resolve(Response<dynamic>(requestOptions: options, data: data, statusCode: 200));
  }
}

/// Keeps good answers once they are unwrapped: put last.
class SeerrCacheStoreInterceptor extends Interceptor {
  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final o = response.requestOptions;
    final code = response.statusCode ?? 0;
    final data = response.data;
    if (code >= 200 && code < 300 && data is Map && SeerrPageCache.cacheable(o.method, o.path)) {
      SeerrPageCache.store(o.uri.toString(), data, DateTime.now());
    }
    handler.next(response);
  }
}
