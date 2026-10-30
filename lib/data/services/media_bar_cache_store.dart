import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../util/platform_detection.dart';
import '../models/media_bar_slide_item.dart';

/// Keeps the slides of the big banner at the top of home, so a cold start
/// paints the last ones at once and swaps in the fresh ones when they arrive
/// (the rows below already work that way, see HomeRowCacheStore).
///
/// Single-slot, keyed by server, user and banner settings; best effort, never
/// throws to the caller.
class MediaBarCacheStore {
  static const _fileName = 'media_bar_cache.json';
  static const _maxAge = Duration(days: 3);
  static const _format = 1;

  Future<File> _file() async {
    final dir = PlatformDetection.isAppleTV
        ? await getApplicationCacheDirectory()
        : await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<MediaBarSlideItem>?> read(String key) async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      if (decoded['key'] != key || decoded['format'] != _format) return null;
      final savedAt = decoded['savedAt'];
      if (savedAt is! int) return null;
      final age = DateTime.now().millisecondsSinceEpoch - savedAt;
      if (age < 0 || age > _maxAge.inMilliseconds) return null;
      final raw = decoded['items'];
      if (raw is! List) return null;
      final items = [
        for (final m in raw)
          if (m is Map) ?slideFromJson(m.cast<String, dynamic>()),
      ];
      return items.isEmpty ? null : items;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, List<MediaBarSlideItem> items) async {
    if (items.isEmpty) return;
    try {
      final payload = jsonEncode({
        'key': key,
        'format': _format,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'items': [for (final i in items) slideToJson(i)],
      });
      await (await _file()).writeAsString(payload, flush: true);
    } catch (_) {}
  }

  static Map<String, dynamic> slideToJson(MediaBarSlideItem i) => {
    'itemId': i.itemId,
    'serverId': i.serverId,
    'title': i.title,
    'overview': i.overview,
    'backdropUrl': i.backdropUrl,
    'bannerUrl': i.bannerUrl,
    'logoUrl': i.logoUrl,
    'posterUrl': i.posterUrl,
    'officialRating': i.officialRating,
    'year': i.year,
    'genres': i.genres,
    'runtimeMs': i.runtime?.inMilliseconds,
    'communityRating': i.communityRating,
    'criticRating': i.criticRating,
    'tmdbId': i.tmdbId,
    'imdbId': i.imdbId,
    'itemType': i.itemType,
    'remoteTrailers': i.remoteTrailers,
    'kicker': i.kicker,
    'role': i.role,
    'caption': i.caption,
    'progress': i.progress,
  };

  static MediaBarSlideItem? slideFromJson(Map<String, dynamic> m) {
    final id = m['itemId'];
    final title = m['title'];
    if (id is! String || title is! String) return null;
    String? s(String k) => m[k] is String ? m[k] as String : null;
    final runtimeMs = m['runtimeMs'];
    final genres = m['genres'];
    final trailers = m['remoteTrailers'];
    return MediaBarSlideItem(
      itemId: id,
      serverId: s('serverId') ?? '',
      title: title,
      overview: s('overview'),
      backdropUrl: s('backdropUrl'),
      bannerUrl: s('bannerUrl'),
      logoUrl: s('logoUrl'),
      posterUrl: s('posterUrl'),
      officialRating: s('officialRating'),
      year: m['year'] is int ? m['year'] as int : null,
      genres: genres is List ? [for (final g in genres) if (g is String) g] : const [],
      runtime: runtimeMs is int ? Duration(milliseconds: runtimeMs) : null,
      communityRating: (m['communityRating'] as num?)?.toDouble(),
      criticRating: m['criticRating'] is int ? m['criticRating'] as int : null,
      tmdbId: s('tmdbId'),
      imdbId: s('imdbId'),
      itemType: s('itemType') ?? 'Movie',
      remoteTrailers: trailers is List
          ? [for (final t in trailers) if (t is Map) t.cast<String, dynamic>()]
          : const [],
      kicker: s('kicker'),
      role: s('role'),
      caption: s('caption'),
      progress: (m['progress'] as num?)?.toDouble(),
    );
  }
}
