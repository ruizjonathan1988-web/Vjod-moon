// VJOD 5.16: cancelling a Seerr request now stops the download too.
//
// Seerr only deletes the request: Radarr / Sonarr keep the title and the
// torrent goes on. Once Seerr has deleted it, Ma TV (IPTV Checker 3.91 and
// after) takes the download out of Radarr / Sonarr's queue and out of the
// torrent client, and drops the title, never touching anything that already
// has a file. Without Ma TV, or with an older one, nothing more happens.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../seerr/seerr_api_models.dart';
import 'ma_tv.dart';
import 'tv_sources.dart';

class SeerrCancelDownload {
  SeerrCancelDownload._();

  static http.Client? httpClient;

  /// The last failure, for the tests and the logs.
  static Object? lastError;
  static TvSourcesServer? Function() serverOf = () => MaTvClient().server;

  /// What to tell Ma TV for these requests: the type, the ids, the seasons.
  static Map<String, Object?> payload({
    required bool isMovie,
    required int tmdbId,
    int? tvdbId,
    Iterable<int> seasons = const [],
  }) => {
    'type': isMovie ? 'movie' : 'tv',
    'tmdb': tmdbId,
    if (tvdbId != null && tvdbId > 0) 'tvdb': tvdbId,
    if (!isMovie) 'seasons': (seasons.where((s) => s > 0).toSet().toList()..sort()),
  };

  /// What to stop once [cancelled] are gone, or null when nothing should:
  /// someone else still asks for the film, or for every cancelled season.
  /// The download stays for them (same quality only: a 4K request is apart).
  static Map<String, Object?>? forCancel({
    required List<SeerrRequest> all,
    required Set<int> cancelled,
    required bool isMovie,
    required int tmdbId,
    int? tvdbId,
  }) {
    if (tmdbId <= 0 && (tvdbId ?? 0) <= 0) return null;
    final gone = [for (final r in all) if (cancelled.contains(r.id)) r];
    if (gone.isEmpty) return null;
    final fourK = gone.first.is4k;
    final kept = [
      for (final r in all)
        if (!cancelled.contains(r.id) &&
            r.is4k == fourK &&
            (r.status == SeerrRequest.statusPending || r.status == SeerrRequest.statusApproved))
          r,
    ];
    if (isMovie) {
      if (kept.isNotEmpty) return null;
      return payload(isMovie: true, tmdbId: tmdbId, tvdbId: tvdbId);
    }
    Set<int> seasonsOf(Iterable<SeerrRequest> rs) => {
      for (final r in rs)
        for (final s in r.seasons ?? const <SeerrSeasonRequest>[]) s.seasonNumber,
    };
    final keptSeasons = seasonsOf(kept);
    final seasons = seasonsOf(gone).difference(keptSeasons);
    // A request without its seasons listed is the whole series: kept, it
    // keeps everything; cancelled, Ma TV stops every season without a file.
    if (kept.any((r) => (r.seasons ?? const []).isEmpty)) return null;
    if (seasons.isEmpty && gone.any((r) => (r.seasons ?? const []).isNotEmpty)) return null;
    return payload(isMovie: false, tmdbId: tmdbId, tvdbId: tvdbId, seasons: seasons);
  }

  /// True when Ma TV stopped something.
  static Future<bool> stop(Map<String, Object?> body) async {
    final server = serverOf();
    if (server == null) return false;
    try {
      final uri = server.endpoint('/tv/api/seerr/cancel');
      final client = httpClient;
      final encoded = jsonEncode(body);
      const headers = {'Content-Type': 'application/json'};
      final r = await (client != null
              ? client.post(uri, headers: headers, body: encoded)
              : http.post(uri, headers: headers, body: encoded))
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) {
        lastError = 'HTTP ${r.statusCode}';
        return false;
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      return j is Map &&
          (((j['downloads'] as num?) ?? 0) > 0 || ((j['removed'] as List?)?.isNotEmpty ?? false));
    } catch (e) {
      lastError = e;
      return false;
    }
  }
}
