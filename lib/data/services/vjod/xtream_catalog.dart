/// Reads the films and series of an Xtream IPTV provider straight from its
/// `player_api.php`, on demand, so a title can be found and played without
/// the media server holding a STRM file for it or scanning anything.
///
/// The parsing and matching here are plain functions so they can be tested
/// without a network; [XtreamCatalog] only fetches and keeps the result for
/// the session.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../util/accent_folding.dart';
import 'tv_playlists.dart';

enum XtreamKind { movie, series }

/// One film or series of the provider's catalogue.
class XtreamTitle {
  final XtreamKind kind;

  /// `stream_id` for a film, `series_id` for a series.
  final String id;

  /// The name without the provider's language prefix, e.g. `Dune (2021)`.
  final String name;

  /// The language prefix the provider put in front of the name (`FR`, `EN`,
  /// `RU`…), or empty.
  final String tag;
  final String poster;

  /// The file extension a film is served with (`mkv`, `mp4`…). Empty for a
  /// series, whose episodes each carry their own.
  final String extension;

  /// [name] folded for matching, computed once.
  final String searchKey;

  /// The TMDB id the provider filed the title under, or empty. Not every
  /// provider sends one.
  final String tmdbId;

  /// The year from the provider's fields or from a `(2021)` in the name.
  final int? year;

  const XtreamTitle({
    required this.kind,
    required this.id,
    required this.name,
    required this.tag,
    required this.poster,
    required this.extension,
    required this.searchKey,
    this.tmdbId = '',
    this.year,
  });

  /// The name with its language tag, as shown under a poster.
  String get label => tag.isEmpty ? name : '$name · $tag';
}

/// One episode of a provider series.
class XtreamEpisode {
  final String id;
  final int season;
  final int number;
  final String title;
  final String extension;
  final String plot;
  final String image;

  const XtreamEpisode({
    required this.id,
    required this.season,
    required this.number,
    required this.title,
    required this.extension,
    this.plot = '',
    this.image = '',
  });
}

/// A provider series with its episodes, grouped by season.
class XtreamSeriesInfo {
  final String plot;
  final String cover;
  final Map<int, List<XtreamEpisode>> seasons;

  const XtreamSeriesInfo({
    required this.plot,
    required this.cover,
    required this.seasons,
  });

  List<int> get seasonNumbers => seasons.keys.toList()..sort();
}

final _prefix = RegExp(
  r'^\s*[\[\|(]?\s*([A-Z][A-Z0-9\-]{1,9})(?:\s*-\s+|\s*[\]\|)]\s*)(.+)$',
);

/// Splits `FR - Dune (2021)` (or `|FR| Dune`, `[EN] Dune`) into
/// its language tag and the name behind it. A name without such a prefix
/// comes back whole with an empty tag; a colon is never read as one, so
/// `FBI: Most Wanted` keeps its name.
({String tag, String name}) splitProviderName(String raw) {
  final text = raw.trim();
  final match = _prefix.firstMatch(text);
  if (match == null) return (tag: '', name: text);
  final name = match.group(2)!.trim();
  if (name.isEmpty) return (tag: '', name: text);
  return (tag: match.group(1)!, name: name);
}

String _str(Object? value) => value == null ? '' : value.toString().trim();

int _int(Object? value, [int fallback = 0]) =>
    value is int ? value : int.tryParse(_str(value)) ?? fallback;

List<Object?> _list(Object? decoded) => decoded is List ? decoded : const [];

final _yearInName = RegExp(r'[\(\[]\s*((?:19|20)\d{2})\s*[\)\]]|\s-\s((?:19|20)\d{2})\s*$');
final _bareYearAtEnd = RegExp(r'\s((?:19|20)\d{2})\s*$');

/// The year of a provider entry: its own field when it sends one, else a
/// `(2021)` or a trailing year in the name.
int? _yearOf(Map entry, String name) {
  for (final key in const ['year', 'releaseDate', 'release_date', 'releasedate']) {
    final match = RegExp(r'(?:19|20)\d{2}').firstMatch(_str(entry[key]));
    if (match != null) return int.parse(match.group(0)!);
  }
  // A bare trailing number is left alone: in `Blade Runner 2049` it is the
  // title, not the year.
  final m = _yearInName.firstMatch(name);
  final y = m == null ? null : (m.group(1) ?? m.group(2));
  return y == null ? null : int.tryParse(y);
}

String _tmdbOf(Map entry) {
  for (final key in const ['tmdb', 'tmdb_id', 'tmdbId']) {
    final value = _str(entry[key]);
    if (RegExp(r'^\d+$').hasMatch(value) && value != '0') return value;
  }
  return '';
}

/// A title reduced to what two spellings of it share: folded, without the
/// year in brackets, the quality tags or the punctuation. `Dune : Deuxième
/// Partie (2024) [4K]` and `dune deuxieme partie` give the same key. A bare
/// trailing number stays, since it can be the title (`Blade Runner 2049`).
String titleMatchKey(String name) {
  var text = foldForSearch(name);
  text = text.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ');
  text = text.replaceAll(RegExp(r'\s-\s(?:19|20)\d{2}\s*$'), ' ');
  text = text.replaceAll(RegExp(r'&'), ' and ');
  text = text.replaceAll(RegExp(r"[^\p{L}\p{N}]+", unicode: true), ' ');
  text = text.replaceAll(RegExp(r'\b(?:4k|uhd|fhd|hd|sd|1080p|720p|2160p|multi|vostfr|vf|vo)\b'), ' ');
  return text.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// The films of a `get_vod_streams` answer. Entries without an id or a name
/// are skipped; a repeated id is kept once.
List<XtreamTitle> parseVodStreams(String body) {
  final seen = <String>{};
  final out = <XtreamTitle>[];
  for (final entry in _list(jsonDecode(body))) {
    if (entry is! Map) continue;
    final id = _str(entry['stream_id']);
    final raw = _str(entry['name']);
    if (id.isEmpty || raw.isEmpty || !seen.add(id)) continue;
    final split = splitProviderName(raw);
    final ext = _str(entry['container_extension']);
    out.add(
      XtreamTitle(
        kind: XtreamKind.movie,
        id: id,
        name: split.name,
        tag: split.tag,
        poster: _str(entry['stream_icon']),
        extension: ext.isEmpty ? 'mp4' : ext,
        searchKey: foldForSearch(split.name),
        tmdbId: _tmdbOf(entry),
        year: _yearOf(entry, split.name),
      ),
    );
  }
  return out;
}

/// The series of a `get_series` answer.
List<XtreamTitle> parseSeriesList(String body) {
  final seen = <String>{};
  final out = <XtreamTitle>[];
  for (final entry in _list(jsonDecode(body))) {
    if (entry is! Map) continue;
    final id = _str(entry['series_id']);
    final raw = _str(entry['name']);
    if (id.isEmpty || raw.isEmpty || !seen.add(id)) continue;
    final split = splitProviderName(raw);
    out.add(
      XtreamTitle(
        kind: XtreamKind.series,
        id: id,
        name: split.name,
        tag: split.tag,
        poster: _str(entry['cover']),
        extension: '',
        searchKey: foldForSearch(split.name),
        tmdbId: _tmdbOf(entry),
        year: _yearOf(entry, split.name),
      ),
    );
  }
  return out;
}

/// The seasons and episodes of a `get_series_info` answer. Providers send the
/// episodes either as a map keyed by season or as a list of season lists;
/// both are read.
XtreamSeriesInfo parseSeriesInfo(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map) {
    return const XtreamSeriesInfo(plot: '', cover: '', seasons: {});
  }
  final info = decoded['info'] is Map ? decoded['info'] as Map : const {};
  final rawEpisodes = decoded['episodes'];
  final groups = <MapEntry<int?, Object?>>[
    if (rawEpisodes is Map)
      for (final e in rawEpisodes.entries)
        MapEntry(int.tryParse(e.key.toString()), e.value)
    else if (rawEpisodes is List)
      for (final v in rawEpisodes) MapEntry(null, v),
  ];
  final seasons = <int, List<XtreamEpisode>>{};
  for (final group in groups) {
    for (final ep in _list(group.value)) {
      if (ep is! Map) continue;
      final id = _str(ep['id']);
      if (id.isEmpty) continue;
      final epInfo = ep['info'] is Map ? ep['info'] as Map : const {};
      final season = _int(ep['season'], group.key ?? 1);
      final number = _int(ep['episode_num']);
      final ext = _str(ep['container_extension']);
      final title = splitProviderName(_str(ep['title'])).name;
      (seasons[season] ??= []).add(
        XtreamEpisode(
          id: id,
          season: season,
          number: number,
          title: title.isEmpty ? 'Épisode $number' : title,
          extension: ext.isEmpty ? 'mkv' : ext,
          plot: _str(epInfo['plot']),
          image: _str(epInfo['movie_image']),
        ),
      );
    }
  }
  for (final list in seasons.values) {
    list.sort((a, b) => a.number.compareTo(b.number));
  }
  return XtreamSeriesInfo(
    plot: _str(info['plot']),
    cover: _str(info['cover']),
    seasons: seasons,
  );
}

/// The titles of [all] that match [query], best first: a name that starts
/// with the query, then one with a word that does, then one holding every
/// word of the query anywhere. Shorter names win a tie, so `Dune` comes
/// before `Dune: Part Two`.
/// Where [tag] comes in [preferred]: its place in the list, or after all of
/// them when it isn't there. Read loosely, so `CN` and `ZH` are one language,
/// as are `EN`, `UK` and `US`.
int languageRank(String tag, List<String> preferred) {
  if (preferred.isEmpty) return 0;
  final t = _canonicalTag(tag);
  for (var i = 0; i < preferred.length; i++) {
    if (_canonicalTag(preferred[i]) == t) return i;
  }
  return preferred.length;
}

String _canonicalTag(String tag) => switch (tag.toUpperCase()) {
  'ZH' || 'CHN' || 'CHINA' || 'CHINESE' => 'CN',
  'UK' || 'US' || 'USA' || 'ENG' => 'EN',
  'FRA' || 'FRENCH' || 'VF' || 'VFF' || 'VFQ' => 'FR',
  'RUS' || 'RUSSIA' => 'RU',
  final other => other,
};

/// [copies] with the profile's languages first, in its order, and the rest
/// after in the provider's order.
List<XtreamTitle> orderByLanguages(
  List<XtreamTitle> copies,
  List<String> preferred,
) {
  if (preferred.isEmpty) return copies;
  final indexed = copies.indexed.toList()
    ..sort((a, b) {
      final byLang = languageRank(a.$2.tag, preferred)
          .compareTo(languageRank(b.$2.tag, preferred));
      return byLang != 0 ? byLang : a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) e.$2];
}

/// Whether [tag] is one of the [preferred] languages.
bool isPreferredLanguage(String tag, List<String> preferred) =>
    preferred.isNotEmpty && languageRank(tag, preferred) < preferred.length;

List<XtreamTitle> searchTitles(
  List<XtreamTitle> all,
  String query, {
  int limit = 40,
  List<String> preferredTags = const [],
}) {
  final q = foldForSearch(query.trim());
  if (q.length < 2) return const [];
  final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final scored = <(int, XtreamTitle)>[];
  for (final title in all) {
    final key = title.searchKey;
    if (!words.every(key.contains)) continue;
    final rank = key.startsWith(q)
        ? 0
        : (key.contains(' $q') ? 1 : 2);
    scored.add((rank, title));
  }
  scored.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    if (byRank != 0) return byRank;
    final byLang = languageRank(a.$2.tag, preferredTags)
        .compareTo(languageRank(b.$2.tag, preferredTags));
    if (byLang != 0) return byLang;
    return a.$2.name.length.compareTo(b.$2.name.length);
  });
  return [for (final s in scored.take(limit)) s.$2];
}

/// The provider's copies of one title, every language it has them in: the
/// ones filed under [tmdbId], and the ones whose name is one of [titles]
/// with the same year give or take one (or no year to compare). Films match
/// films and series match series.
List<XtreamTitle> findProviderCopies(
  List<XtreamTitle> all, {
  required XtreamKind kind,
  int tmdbId = 0,
  List<String> titles = const [],
  int? year,
  int limit = 8,
}) {
  final tmdb = tmdbId > 0 ? '$tmdbId' : '';
  final keys = {
    for (final t in titles)
      if (titleMatchKey(t) case final k when k.isNotEmpty) k,
  };
  if (tmdb.isEmpty && keys.isEmpty) return const [];
  final byTmdb = <XtreamTitle>[];
  final byName = <XtreamTitle>[];
  for (final title in all) {
    if (title.kind != kind) continue;
    if (tmdb.isNotEmpty && title.tmdbId == tmdb) {
      byTmdb.add(title);
      continue;
    }
    // A title filed under another TMDB id is another title, whatever its name.
    if (tmdb.isNotEmpty && title.tmdbId.isNotEmpty) continue;
    final key = titleMatchKey(title.name);
    final y = title.year;
    if (keys.contains(key)) {
      if (year != null && y != null && (y - year).abs() > 1) continue;
      byName.add(title);
      continue;
    }
    // `Dune 2021` is `Dune` only when 2021 is the year being looked for.
    final bare = _bareYearAtEnd.firstMatch(key);
    if (bare != null &&
        year != null &&
        int.parse(bare.group(1)!) == year &&
        keys.contains(key.substring(0, bare.start).trim())) {
      byName.add(title);
    }
  }
  final seen = <String>{};
  return [
    for (final t in [...byTmdb, ...byName])
      if (seen.add(t.id)) t,
  ].take(limit).toList();
}

/// The provider's catalogue for one saved Xtream source. The film and series
/// lists are fetched once, the first time a search needs them, and kept for
/// the session; a failed fetch is retried on the next search.
class XtreamCatalog {
  final String base;
  final String username;
  final String password;

  XtreamCatalog._(this.base, this.username, this.password);

  static XtreamCatalog? _current;

  /// The catalogue of the first Xtream source in [playlists] that has a
  /// portal and credentials, or null when there is none. The same instance
  /// comes back while that source stays the same, so its lists are reused.
  static XtreamCatalog? forPlaylists(List<TvPlaylist> playlists) {
    for (final p in playlists) {
      if (p.kind != TvPlaylistKind.xtream) continue;
      final base = p.url.trim().replaceAll(RegExp(r'/+$'), '');
      if (base.isEmpty || p.username.isEmpty || p.password.isEmpty) continue;
      final current = _current;
      if (current != null &&
          current.base == base &&
          current.username == p.username &&
          current.password == p.password) {
        return current;
      }
      return _current = XtreamCatalog._(base, p.username, p.password);
    }
    return null;
  }

  static const _listTimeout = Duration(seconds: 90);
  static const _infoTimeout = Duration(seconds: 20);

  Future<List<XtreamTitle>>? _titles;

  Uri _api(String action, [Map<String, String> extra = const {}]) =>
      Uri.parse('$base/player_api.php').replace(
        queryParameters: {
          'username': username,
          'password': password,
          'action': action,
          ...extra,
        },
      );

  Future<String> _get(Uri uri, Duration timeout) async {
    final response = await http.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw StateError('Fournisseur IPTV : HTTP ${response.statusCode}');
    }
    // Providers often omit the charset, and the names are UTF-8.
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  Future<List<XtreamTitle>> _load() async {
    final results = await Future.wait([
      _get(_api('get_vod_streams'), _listTimeout)
          .then((body) => compute(parseVodStreams, body))
          .catchError((_) => <XtreamTitle>[]),
      _get(_api('get_series'), _listTimeout)
          .then((body) => compute(parseSeriesList, body))
          .catchError((_) => <XtreamTitle>[]),
    ]);
    final all = [...results[0], ...results[1]];
    if (all.isEmpty) throw StateError('Catalogue du fournisseur vide');
    return all;
  }

  /// Starts fetching the lists if they aren't yet, so the first search
  /// doesn't wait for the whole download.
  void warmUp() => unawaited(_all().then<void>((_) {}, onError: (_) {}));

  Future<List<XtreamTitle>> _all() {
    final future = _titles ??= _load();
    future.catchError((_) {
      if (identical(_titles, future)) _titles = null;
      return <XtreamTitle>[];
    });
    return future;
  }

  /// The provider's copies of a title, see [findProviderCopies]. Waits for
  /// the catalogue the first time.
  Future<List<XtreamTitle>> copiesOf({
    required XtreamKind kind,
    int tmdbId = 0,
    List<String> titles = const [],
    int? year,
  }) async => findProviderCopies(
    await _all(),
    kind: kind,
    tmdbId: tmdbId,
    titles: titles,
    year: year,
  );

  /// Films and series whose name matches [query], the [preferredTags]
  /// languages first among equally good matches.
  Future<List<XtreamTitle>> search(
    String query, {
    int limit = 40,
    List<String> preferredTags = const [],
  }) async => searchTitles(
    await _all(),
    query,
    limit: limit,
    preferredTags: preferredTags,
  );

  /// How many films and series the provider has in each language tag, most
  /// first. Titles without a tag are left out.
  Future<List<MapEntry<String, int>>> languageCounts() async {
    final counts = <String, int>{};
    for (final t in await _all()) {
      if (t.tag.isEmpty) continue;
      counts[t.tag] = (counts[t.tag] ?? 0) + 1;
    }
    return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// The seasons and episodes of a series.
  Future<XtreamSeriesInfo> seriesInfo(String seriesId) async => parseSeriesInfo(
    await _get(
      _api('get_series_info', {'series_id': seriesId}),
      _infoTimeout,
    ),
  );

  String _seg(String value) => Uri.encodeComponent(value);

  /// Where a film plays from.
  String movieUrl(XtreamTitle movie) =>
      '$base/movie/${_seg(username)}/${_seg(password)}/'
      '${movie.id}.${movie.extension}';

  /// Where an episode plays from.
  String episodeUrl(XtreamEpisode episode) =>
      '$base/series/${_seg(username)}/${_seg(password)}/'
      '${episode.id}.${episode.extension}';
}
