// Where each profile stopped in an IPTV film or series. Ma TV keeps it on the
// seedbox, per Jellyfin user, so a film started on the TV picks up on the
// phone. Every call fails quietly: without the seedbox, a film just starts
// from the beginning.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ma_tv.dart';
import 'xtream_catalog.dart';

/// What is playing: enough to save its place and to learn from it.
class IptvWatch {
  /// `movie` or `series`.
  final String kind;

  /// Ma TV's number for the film or the series.
  final String id;
  final String name;
  final String tmdb;
  final String poster;

  /// The episode, for a series: Ma TV's id ("account-number"), its format,
  /// season and number, and its title.
  final String ep;
  final String ext;
  final int season;
  final int episode;
  final String epName;

  const IptvWatch({
    required this.kind,
    required this.id,
    this.name = '',
    this.tmdb = '',
    this.poster = '',
    this.ep = '',
    this.ext = '',
    this.season = 0,
    this.episode = 0,
    this.epName = '',
  });

  bool get isSeries => kind == 'series';

  /// A film from the provider's catalogue.
  factory IptvWatch.movie(XtreamTitle t) => IptvWatch(
    kind: 'movie',
    id: t.id,
    name: t.name,
    tmdb: t.tmdbId,
    poster: t.poster,
    ext: t.extension,
  );

  /// Route parameters, prefixed so they never clash with the player's own.
  Map<String, String> toQuery() => {
    'w_kind': kind,
    'w_id': id,
    if (name.isNotEmpty) 'w_name': name,
    if (tmdb.isNotEmpty) 'w_tmdb': tmdb,
    if (poster.isNotEmpty) 'w_poster': poster,
    if (ep.isNotEmpty) 'w_ep': ep,
    if (ext.isNotEmpty) 'w_ext': ext,
    if (season > 0) 'w_season': '$season',
    if (episode > 0) 'w_episode': '$episode',
    if (epName.isNotEmpty) 'w_epname': epName,
  };

  static IptvWatch? fromQuery(Map<String, String> q) {
    final kind = q['w_kind'] ?? '';
    final id = q['w_id'] ?? '';
    if (id.isEmpty || (kind != 'movie' && kind != 'series')) return null;
    return IptvWatch(
      kind: kind,
      id: id,
      name: q['w_name'] ?? '',
      tmdb: q['w_tmdb'] ?? '',
      poster: q['w_poster'] ?? '',
      ep: q['w_ep'] ?? '',
      ext: q['w_ext'] ?? '',
      season: int.tryParse(q['w_season'] ?? '') ?? 0,
      episode: int.tryParse(q['w_episode'] ?? '') ?? 0,
      epName: q['w_epname'] ?? '',
    );
  }
}

/// A saved place.
class IptvProgress {
  final String kind;
  final String id;
  final String name;
  final String tmdb;
  final String poster;
  final Duration position;
  final Duration duration;

  /// Watched to the credits.
  final bool done;
  final DateTime at;
  final String ep;
  final String ext;
  final int season;
  final int episode;
  final String epName;

  const IptvProgress({
    required this.kind,
    required this.id,
    required this.name,
    required this.tmdb,
    required this.poster,
    required this.position,
    required this.duration,
    required this.done,
    required this.at,
    this.ep = '',
    this.ext = '',
    this.season = 0,
    this.episode = 0,
    this.epName = '',
  });

  bool get isSeries => kind == 'series';

  /// Whether this place is the episode [season] × [episode] of [epId]: the
  /// same file, or the same episode by its numbers when the series now comes
  /// from another provider (its episode ids are that provider's own).
  bool isEpisode(String epId, int season, int episode) =>
      ep == epId || (season > 0 && episode > 0 && this.season == season && this.episode == episode);

  /// How far along, 0 to 1.
  double get fraction => duration.inSeconds <= 0
      ? 0
      : (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0);

  /// Worth offering to resume: past the first minute, not finished.
  bool get resumable => !done && position.inSeconds >= 60;

  static IptvProgress? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = '${j['id'] ?? ''}';
    if (id.isEmpty) return null;
    int n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    final at = j['at'];
    return IptvProgress(
      kind: j['kind'] == 'series' ? 'series' : 'movie',
      id: id,
      name: '${j['name'] ?? ''}',
      tmdb: '${j['tmdb'] ?? ''}',
      poster: '${j['poster'] ?? ''}',
      position: Duration(seconds: n(j['pos'])),
      duration: Duration(seconds: n(j['dur'])),
      done: j['done'] == true,
      at: at is num
          ? DateTime.fromMillisecondsSinceEpoch((at * 1000).round())
          : DateTime.fromMillisecondsSinceEpoch(0),
      ep: '${j['ep'] ?? ''}',
      ext: '${j['ext'] ?? ''}',
      season: n(j['season']),
      episode: n(j['episode']),
      epName: '${j['ep_name'] ?? ''}',
    );
  }
}

/// Reads and writes the places on Ma TV.
class IptvProgressStore {
  IptvProgressStore._();

  static const _timeout = Duration(seconds: 8);

  /// Changes whenever a place is saved, so rows and pages can refresh.
  static final revision = StreamController<void>.broadcast();

  static ({Uri Function(String, [Map<String, String>]) endpoint, String user})? _ctx() {
    final client = MaTvClient();
    final server = client.server;
    final user = client.user;
    if (server == null || user == null || user.isEmpty) return null;
    return (endpoint: server.endpoint, user: user);
  }

  /// The place of [id]; failing that, of the same work ([tmdb]) watched
  /// under another number (another language, another provider).
  static Future<IptvProgress?> get(String kind, String id, {String tmdb = ''}) async {
    final c = _ctx();
    if (c == null || id.isEmpty) return null;
    try {
      final r = await http
          .get(c.endpoint('/tv/api/vod/progress', {
            'u': c.user,
            'kind': kind,
            'id': id,
            if (tmdb.isNotEmpty) 'tmdb': tmdb,
          }))
          .timeout(_timeout);
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map ? IptvProgress.fromJson(j['progress']) : null;
    } catch (_) {
      return null;
    }
  }

  /// What the profile has under way, the latest first.
  static Future<List<IptvProgress>> list() async {
    final c = _ctx();
    if (c == null) return const [];
    try {
      final r = await http
          .get(c.endpoint('/tv/api/vod/progress', {'u': c.user}))
          .timeout(_timeout);
      if (r.statusCode != 200) return const [];
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final items = j is Map ? j['items'] : null;
      return [
        for (final e in (items is List ? items : const []))
          if (IptvProgress.fromJson(e) case final p?) p,
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(IptvWatch w, Duration position, Duration duration) =>
      _post({
        'kind': w.kind,
        'id': w.id,
        'name': w.name,
        'tmdb': w.tmdb,
        'poster': w.poster,
        'pos': position.inSeconds,
        'dur': duration.inSeconds,
        'ext': w.ext,
        if (w.isSeries) ...{
          'ep': w.ep,
          'season': w.season,
          'episode': w.episode,
          'ep_name': w.epName,
        },
      });

  static Future<void> remove(String kind, String id) =>
      _post({'kind': kind, 'id': id, 'remove': true});

  static Future<void> _post(Map<String, Object?> body) async {
    final c = _ctx();
    if (c == null) return;
    try {
      final r = await http
          .post(
            c.endpoint('/tv/api/vod/progress'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({...body, 'user': c.user}),
          )
          .timeout(_timeout);
      if (r.statusCode == 200) revision.add(null);
    } catch (_) {}
  }
}
