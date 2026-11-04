// VJOD 4.25: keep a show of the replay. Two roads, nothing leaves without
// a press: Seerr asks Sonarr for the season (it searches the trackers and
// files it in the library), or the trackers are searched here through
// Prowlarr (Ma TV 3.67) and the chosen version is sent to the download.
import 'dart:async';
import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;

import '../../../util/accent_folding.dart';
import '../../repositories/seerr_repository.dart';
import 'ma_tv_replay.dart';
import 'tv_sources.dart';

/// One result of the trackers.
class TrackerRelease {
  final String id;
  final String title;
  final int size;
  final int seeders;
  final String indexer;
  final int? ageDays;

  const TrackerRelease({
    required this.id,
    required this.title,
    this.size = 0,
    this.seeders = 0,
    this.indexer = '',
    this.ageDays,
  });

  factory TrackerRelease.fromJson(Map<String, dynamic> j) => TrackerRelease(
    id: '${j['id'] ?? ''}',
    title: '${j['title'] ?? ''}',
    size: (j['size'] as num?)?.toInt() ?? 0,
    seeders: (j['seeders'] as num?)?.toInt() ?? 0,
    indexer: '${j['indexer'] ?? ''}',
    ageDays: (j['age'] as num?)?.toInt(),
  );

  /// « 2,4 Go · 40 sources · Tracker A · il y a 2 j »
  String get detail {
    String sz() {
      if (size <= 0) return '';
      final go = size / (1 << 30);
      return go >= 1
          ? '${go.toStringAsFixed(1).replaceAll('.', ',')} Go'
          : '${(size / (1 << 20)).round()} Mo';
    }

    final age = ageDays == null ? '' : (ageDays == 0 ? 'aujourd’hui' : 'il y a $ageDays j');
    return [
      sz(),
      '$seeders source${seeders > 1 ? 's' : ''}',
      indexer,
      age,
    ].where((s) => s.isNotEmpty).join(' · ');
  }
}

class TrackerSearch {
  final List<TrackerRelease> results;

  /// Whether this profile may send one to the download (Jellyfin admins).
  final bool mayGrab;

  /// Why nothing came, in French, or empty.
  final String error;

  const TrackerSearch({this.results = const [], this.mayGrab = false, this.error = ''});
}

class ReplayKeep {
  ReplayKeep._();

  static String _fold(String s) => foldForSearch(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// What to search on the trackers for [e]: the show, its episode when
  /// known (« Koh-Lanta S25E10 »).
  static String queryFor(ReplayItem e) =>
      e.season > 0 && e.episode > 0 ? '${e.show} S${_two(e.season)}E${_two(e.episode)}' : e.show;

  static Future<TrackerSearch> search(String query, {http.Client? client, TvSourcesServer? server}) async {
    final s = server ?? TvSourcesClient().server;
    if (s == null) return const TrackerSearch(error: 'Ma TV n’est pas réglée sur cet appareil.');
    try {
      final uri = s.endpoint('/tv/api/fetch/search', {'q': query});
      final r = await (client?.get(uri) ?? http.get(uri)).timeout(const Duration(seconds: 70));
      final body = utf8.decode(r.bodyBytes, allowMalformed: true);
      if (r.statusCode == 404) {
        return const TrackerSearch(error: 'Il faut Ma TV 3.67 sur la seedbox.');
      }
      final j = jsonDecode(body);
      if (r.statusCode != 200 || j is! Map) {
        return TrackerSearch(error: j is Map && j['error'] != null ? '${j['error']}' : 'Ma TV a répondu ${r.statusCode}.');
      }
      return TrackerSearch(
        results: [
          for (final x in (j['results'] as List? ?? const []))
            if (x is Map) TrackerRelease.fromJson(Map<String, dynamic>.from(x)),
        ],
        mayGrab: j['may_grab'] == true,
      );
    } on TimeoutException {
      return const TrackerSearch(error: 'Les trackers n’ont pas répondu à temps.');
    } catch (e) {
      return TrackerSearch(error: 'Recherche impossible : $e');
    }
  }

  /// Sends [r] to the download; the answer to show, in French.
  static Future<String> grab(TrackerRelease r, {http.Client? client, TvSourcesServer? server}) async {
    final s = server ?? TvSourcesClient().server;
    if (s == null) return 'Ma TV n’est pas réglée sur cet appareil.';
    try {
      final uri = s.endpoint('/tv/api/fetch/grab');
      final body = jsonEncode({'id': r.id});
      final res = await (client?.post(uri, headers: {'Content-Type': 'application/json'}, body: body) ??
              http.post(uri, headers: {'Content-Type': 'application/json'}, body: body))
          .timeout(const Duration(seconds: 40));
      final j = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (res.statusCode == 200 && j is Map && j['ok'] == true) {
        return j['via'] == 'qbittorrent'
            ? 'Envoyé à qBittorrent (catégorie « vjod »).'
            : 'Envoyé au téléchargement par Prowlarr.';
      }
      return j is Map && j['error'] != null ? '${j['error']}' : 'Ma TV a répondu ${res.statusCode}.';
    } catch (e) {
      return 'Envoi impossible : $e';
    }
  }

  /// The show in Seerr (TMDB), and the season to ask for: the episode's,
  /// else the latest one.
  static Future<({int tmdb, String name, int season})?> seerrMatch(ReplayItem e) async {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<SeerrRepository>() || e.show.isEmpty) return null;
    try {
      final repo = await getIt.getAsync<SeerrRepository>();
      final page = await repo.search(e.show, mediaType: 'tv', limit: 10).timeout(const Duration(seconds: 10));
      final want = _fold(e.show);
      for (final t in page.results) {
        if (t.mediaType != null && t.mediaType != 'tv') continue;
        final names = [t.name, t.originalName, t.title].whereType<String>().map(_fold);
        if (!names.contains(want)) continue;
        var season = e.season;
        if (season <= 0) {
          final d = await repo.getTvDetails(t.id).timeout(const Duration(seconds: 10));
          season = d.numberOfSeasons ?? 1;
        }
        return (tmdb: t.id, name: t.name ?? t.title ?? e.show, season: season < 1 ? 1 : season);
      }
    } catch (_) {}
    return null;
  }

  /// Asks Seerr for [m]'s season; the answer to show, in French.
  static Future<String> requestSeerr(({int tmdb, String name, int season}) m) async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.createRequest(mediaId: m.tmdb, mediaType: 'tv', seasons: [m.season]).timeout(const Duration(seconds: 20));
      return '« ${m.name} » saison ${m.season} demandée : elle arrivera dans ta bibliothèque.';
    } catch (e) {
      final s = '$e';
      if (s.contains('409') || s.toLowerCase().contains('already')) {
        return '« ${m.name} » saison ${m.season} est déjà demandée.';
      }
      return 'Seerr a refusé la demande : $s';
    }
  }
}
