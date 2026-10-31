import 'package:dio/dio.dart';
import 'package:server_core/server_core.dart';

class EmbyDisplayPreferencesApi implements DisplayPreferencesApi {
  final Dio _dio;
  final Map<String, _CacheEntry> _cache = {};
  static const _cacheDuration = Duration(minutes: 5);

  EmbyDisplayPreferencesApi(this._dio);

  @override
  Future<DisplayPreferences> getDisplayPreferences(
    String id, {
    String? client,
    String? userId,
  }) async {
    final cacheKey = '$id:${client ?? 'emby'}:${userId ?? ''}';
    final entry = _cache[cacheKey];
    if (entry != null &&
        DateTime.now().difference(entry.cachedAt) < _cacheDuration) {
      return entry.prefs;
    }

    final response = await _dio.get(
      '/DisplayPreferences/$id',
      queryParameters: {
        'client': client ?? 'emby',
        'userId': ?userId,
      },
    );
    final prefs =
        DisplayPreferences.fromJson(response.data as Map<String, dynamic>);
    _cache[cacheKey] = _CacheEntry(prefs, DateTime.now());
    return prefs;
  }

  @override
  Future<void> saveDisplayPreferences(
    String id,
    DisplayPreferences prefs, {
    String? client,
    String? userId,
  }) async {
    await _dio.post(
      '/DisplayPreferences/$id',
      data: prefs.toJson(),
      queryParameters: {
        'client': client ?? 'emby',
        'userId': ?userId,
      },
    );
    final cacheKey = '$id:${client ?? 'emby'}:${userId ?? ''}';
    _cache[cacheKey] = _CacheEntry(prefs, DateTime.now());
  }

  void invalidateCache() => _cache.clear();
}

class _CacheEntry {
  final DisplayPreferences prefs;
  final DateTime cachedAt;
  _CacheEntry(this.prefs, this.cachedAt);
}
