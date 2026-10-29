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
import 'xtream_cache_store.dart';

enum XtreamKind { movie, series }

/// The provider account a catalogue was read with, as the seedbox hands it
/// out so the devices follow whatever account Jellyfin is set to.
class XtreamAccount {
  final String portal;
  final String username;
  final String password;

  const XtreamAccount({
    required this.portal,
    required this.username,
    required this.password,
  });

  bool get isComplete =>
      portal.isNotEmpty && username.isNotEmpty && password.isNotEmpty;

  Map<String, String> toJson() => {
    'portal': portal,
    'username': username,
    'password': password,
  };

  static XtreamAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final account = XtreamAccount(
      portal: normalizePortal(_str(raw['portal'])),
      username: _str(raw['username']),
      password: _str(raw['password']),
    );
    return account.isComplete ? account : null;
  }

  /// As a saved TV source, so it can stand in for a profile's own.
  TvPlaylist toPlaylist() => TvPlaylist(
    id: 'seedbox',
    name: 'Seedbox',
    url: portal,
    kind: TvPlaylistKind.xtream,
    username: username,
    password: password,
  );
}

/// The same provider address however it was typed: lower-case host, no
/// default port, no trailing slash. `http://Hote:80/` is `http://hote`. The
/// seedbox script does the same, so both name an account alike.
String normalizePortal(String url) {
  final text = url.trim();
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) {
    return text.replaceAll(RegExp(r'/+$'), '');
  }
  final scheme = uri.scheme.isEmpty ? 'http' : uri.scheme.toLowerCase();
  final defaultPort =
      (scheme == 'http' && uri.port == 80) ||
      (scheme == 'https' && uri.port == 443);
  final port = uri.hasPort && !defaultPort ? ':${uri.port}' : '';
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  return '$scheme://${uri.host.toLowerCase()}$port$path';
}

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

  /// The qualities this copy comes in, best first (`4K`, `1080p`, `720p`,
  /// `SD`). Ma TV lists every quality it keeps for the title; a provider read
  /// directly gives at most the one written in the name. Empty when unknown.
  final List<String> qualities;

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
    this.qualities = const [],
  });

  /// A title as Ma TV's search answers it (`/tv/api/vod/...`).
  factory XtreamTitle.fromMaTv(Map j) {
    final kind = j['kind'] == 'series' ? XtreamKind.series : XtreamKind.movie;
    final name = _str(j['name']);
    final year = _int(j['year']);
    return XtreamTitle(
      kind: kind,
      id: _str(j['id']),
      name: name,
      tag: _str(j['tag']),
      poster: _str(j['poster']),
      extension: kind == XtreamKind.movie
          ? (_str(j['ext']).isEmpty ? 'mp4' : _str(j['ext']))
          : '',
      searchKey: foldForSearch(name),
      tmdbId: _str(j['tmdb']),
      year: year > 0 ? year : null,
      qualities: [
        for (final q in (j['qualities'] is List ? j['qualities'] as List : const []))
          if (_str(q).isNotEmpty) _str(q),
      ],
    );
  }

  /// The name with its language tag, as shown under a poster.
  String get label => tag.isEmpty ? name : '$name · $tag';
}

/// One file of a title at Ma TV, to pick on the title's page: which provider
/// (its domain), in which of its categories, quality and format.
class MaTvVodSource {
  final int source;
  final String provider;
  final String category;
  final String quality;
  final String extension;

  const MaTvVodSource({
    required this.source,
    required this.provider,
    this.category = '',
    this.quality = '',
    this.extension = '',
  });

  factory MaTvVodSource.fromJson(Map j) => MaTvVodSource(
    source: _int(j['src']),
    provider: _str(j['provider']),
    category: _str(j['category']),
    quality: _str(j['quality']),
    extension: _str(j['ext']),
  );

  /// `fournisseur.com · FILMS 4K · mkv`
  String get details => [
    provider,
    if (category.isNotEmpty) category,
    if (extension.isNotEmpty) extension,
  ].join(' · ');
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

const _qualityHeights = {'4K': 2160, '1080p': 1080, '720p': 720, 'SD': 480};

final _qualityPatterns = [
  ('4K', RegExp(r'\b(?:4k|uhd|2160p?)\b', caseSensitive: false)),
  ('1080p', RegExp(r'\b(?:fhd|1080p?)\b', caseSensitive: false)),
  ('720p', RegExp(r'\b(?:hd|720p?)\b', caseSensitive: false)),
  ('SD', RegExp(r'\b(?:sd|480p?|576p?)\b', caseSensitive: false)),
];

/// The quality a provider writes in a name (`Dune 4K`, `Dune [FHD]`), as
/// `4K`, `1080p`, `720p` or `SD`; empty when the name says nothing.
String providerQuality(String raw) {
  for (final (label, re) in _qualityPatterns) {
    if (re.hasMatch(raw)) return label;
  }
  return '';
}

/// The qualities of a catalogue entry: Ma TV's `qualities` list, else the one
/// in the name.
List<String> _qualitiesOf(Map entry, String raw) {
  final listed = [
    for (final q in _str(entry['qualities']).split(','))
      if (q.trim().isNotEmpty) q.trim(),
  ];
  if (listed.isNotEmpty) return listed;
  final q = providerQuality(raw);
  return q.isEmpty ? const [] : [q];
}

/// The quality to play by default among [qualities]: the best one no taller
/// than [maxHeight] (the device's ceiling), else the lightest. Empty when the
/// list is.
String defaultQuality(List<String> qualities, int maxHeight) {
  if (qualities.isEmpty) return '';
  final sorted = [...qualities]
    ..sort((a, b) => (_qualityHeights[b] ?? 0).compareTo(_qualityHeights[a] ?? 0));
  for (final q in sorted) {
    if ((_qualityHeights[q] ?? 0) <= maxHeight) return q;
  }
  return sorted.last;
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
        qualities: _qualitiesOf(entry, raw),
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
        qualities: _qualitiesOf(entry, raw),
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

const _languageNames = {
  'FR': 'Français',
  'EN': 'Anglais',
  'RU': 'Russe',
  'CN': 'Chinois',
  'ES': 'Espagnol',
  'IT': 'Italien',
  'DE': 'Allemand',
  'PT': 'Portugais',
  'BR': 'Brésilien',
  'AR': 'Arabe',
  'TR': 'Turc',
  'NL': 'Néerlandais',
  'PL': 'Polonais',
  'JP': 'Japonais',
  'JA': 'Japonais',
  'KR': 'Coréen',
  'KO': 'Coréen',
  'TH': 'Thaï',
  'IN': 'Indien',
  'HI': 'Hindi',
  'UA': 'Ukrainien',
  'UK': 'Anglais',
  'GR': 'Grec',
  'SE': 'Suédois',
  'NO': 'Norvégien',
  'DK': 'Danois',
  'FI': 'Finnois',
  'RO': 'Roumain',
  'HU': 'Hongrois',
  'CZ': 'Tchèque',
  'IR': 'Persan',
  'IL': 'Hébreu',
  'VN': 'Vietnamien',
  'PH': 'Philippin',
  'AL': 'Albanais',
  'EX-YU': 'Ex-Yougoslavie',
  'MULTI': 'Multilingue',
  'MULTI-LANG': 'Multilingue',
  'MULTI-SUB': 'Multilingue',
};

/// The language behind a provider tag, spelled out in French (`RU` →
/// `Russe`). A tag it doesn't know comes back as it is.
String languageName(String tag) =>
    _languageNames[_canonicalTag(tag)] ?? _languageNames[tag.toUpperCase()] ?? tag;

/// The short words a play button carries for [tag]: `en russe`, or the tag
/// itself when the language isn't a known one.
String languageButtonPhrase(String tag) {
  if (tag.isEmpty) return '';
  final name = languageName(tag);
  if (name == tag || name == 'Multilingue' || name == 'Ex-Yougoslavie') {
    return '· $name';
  }
  return 'en ${name.toLowerCase()}';
}

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

/// The catalogue as it is saved on the device: when it was fetched and one
/// compact row per title.
String encodeCatalogCache(
  ({int fetchedAtMs, List<XtreamTitle> titles}) cache,
) => jsonEncode({
  'v': 1,
  'fetchedAt': cache.fetchedAtMs,
  'titles': [
    for (final t in cache.titles)
      [
        t.kind == XtreamKind.series ? 's' : 'm',
        t.id,
        t.name,
        t.tag,
        t.poster,
        t.extension,
        t.tmdbId,
        t.year ?? 0,
        t.qualities.join(','),
      ],
  ],
});

/// Reads back what [encodeCatalogCache] wrote, or the file the seedbox
/// prepares each night (the same rows, plus the [account] they were read
/// with), or null for anything else.
({
  int fetchedAtMs,
  List<XtreamTitle> titles,
  String account,
  XtreamAccount? provider,
})?
decodeCatalogCache(String data) {
  try {
    final decoded = jsonDecode(data);
    if (decoded is! Map || decoded['v'] != 1) return null;
    final fetchedAt = decoded['fetchedAt'];
    if (fetchedAt is! int) return null;
    final titles = <XtreamTitle>[];
    for (final row in _list(decoded['titles'])) {
      if (row is! List || row.length < 8) continue;
      final name = _str(row[2]);
      final year = _int(row[7]);
      titles.add(
        XtreamTitle(
          kind: row[0] == 's' ? XtreamKind.series : XtreamKind.movie,
          id: _str(row[1]),
          name: name,
          tag: _str(row[3]),
          poster: _str(row[4]),
          extension: _str(row[5]),
          searchKey: foldForSearch(name),
          tmdbId: _str(row[6]),
          year: year > 0 ? year : null,
          qualities: row.length > 8
              ? [
                  for (final q in _str(row[8]).split(','))
                    if (q.isNotEmpty) q,
                ]
              : const [],
        ),
      );
    }
    return (
      fetchedAtMs: fetchedAt,
      titles: titles,
      account: _str(decoded['account']),
      provider: XtreamAccount.fromJson(decoded['provider']),
    );
  } catch (_) {
    return null;
  }
}

/// A short stable name for a provider account, to file its catalogue under
/// without writing the password into a file name.
String catalogCacheKey(String base, String username) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode('$base|$username')) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
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
      final base = normalizePortal(p.url);
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

  // Ma TV merges the catalogues of many accounts (a few hundred thousand
  // titles): the lists take a while to arrive and to read.
  static const _listTimeout = Duration(minutes: 4);
  // Ma TV asks every provider of the title at once and may take up to 40 s
  // to find one with something behind it.
  static const _infoTimeout = Duration(seconds: 60);

  Future<List<XtreamTitle>>? _titles;

  /// Bumped each time a catalogue lands in memory, so posters can tag what
  /// the provider has without waiting on it.
  static final loaded = ValueNotifier<int>(0);

  /// What the catalogue in use is doing, in words for the settings screen:
  /// where it comes from, how many films and series, or why it failed.
  static final status = ValueNotifier<String>('');

  /// When each catalogue (by [_cacheKey]) last failed to load. A failed one
  /// is passed over for a while so another source can stand in.
  static final _failedAt = <String, DateTime>{};
  static const failurePause = Duration(minutes: 30);

  /// Whether this catalogue failed to load a short while ago.
  bool get recentlyFailed {
    final at = _failedAt[_cacheKey];
    return at != null && DateTime.now().difference(at) < failurePause;
  }

  /// Where this catalogue is read from, in words.
  String get sourceName => isMaTv ? 'Ma TV' : (Uri.tryParse(base)?.host ?? base);

  // ---------------------------------------------------------------- Ma TV
  // Ma TV merges several providers into a few hundred thousand titles: far
  // too many to keep on a phone or a TV box and to go through on each page.
  // So the seedbox is asked instead (a page, a row of posters, a search),
  // and nothing of it is kept on the device.

  /// Whether this is Ma TV's catalogue, searched on the seedbox.
  bool get isMaTv => base.endsWith('/tv/xc');

  static const _maTvTimeout = Duration(seconds: 15);

  Uri _vodApi(String what, Map<String, String> query) =>
      Uri.parse('${base.substring(0, base.length - 6)}/tv/api/vod/$what')
          .replace(queryParameters: {...query, 'k': password});

  Future<Object?> _maTvGet(String what, Map<String, String> query) async {
    final body = await _get(_vodApi(what, query), _maTvTimeout);
    return jsonDecode(body);
  }

  static List<XtreamTitle> _titlesOf(Object? list) => [
    for (final j in (list is List ? list : const []))
      if (j is Map) XtreamTitle.fromMaTv(j),
  ];

  /// Posters' answers, by `kind:tmdb` (an empty list for a title Ma TV lacks).
  final _byTmdbRemote = <String, List<XtreamTitle>>{};
  final _askedTmdb = <String>{};
  final _pendingTmdb = <XtreamKind, Set<String>>{};
  Timer? _tmdbTimer;

  List<XtreamTitle> _copiesNowRemote(XtreamKind kind, String tmdbId) {
    final key = '${kind.name}:$tmdbId';
    final known = _byTmdbRemote[key];
    if (known != null) return known;
    if (_askedTmdb.add(key)) {
      (_pendingTmdb[kind] ??= <String>{}).add(tmdbId);
      // The posters of a row ask together, in one request.
      _tmdbTimer ??= Timer(const Duration(milliseconds: 250), _askTmdb);
    }
    return const [];
  }

  Future<void> _askTmdb() async {
    _tmdbTimer = null;
    final batches = {
      for (final e in _pendingTmdb.entries) e.key: e.value.toList(),
    };
    _pendingTmdb.clear();
    var found = false;
    for (final MapEntry(key: kind, value: ids) in batches.entries) {
      for (var i = 0; i < ids.length; i += 150) {
        final part = ids.sublist(i, i + 150 > ids.length ? ids.length : i + 150);
        try {
          final answer = await _maTvGet('tmdb', {
            'kind': kind.name,
            'ids': part.join(','),
          });
          for (final id in part) {
            final copies = answer is Map ? _titlesOf(answer[id]) : const <XtreamTitle>[];
            _byTmdbRemote['${kind.name}:$id'] = copies;
            if (copies.isNotEmpty) found = true;
          }
        } catch (_) {
          // Asked again the next time these posters show.
          for (final id in part) {
            _askedTmdb.remove('${kind.name}:$id');
          }
        }
      }
    }
    if (found) loaded.value++;
  }

  /// The files Ma TV keeps for [copy], to choose from; empty for another
  /// provider or when it doesn't answer.
  Future<List<MaTvVodSource>> sourcesOf(XtreamTitle copy) async {
    if (!isMaTv) return const [];
    try {
      final answer = await _maTvGet('sources', {
        'kind': copy.kind.name,
        'id': copy.id,
      });
      final list = answer is Map && answer['sources'] is List
          ? answer['sources'] as List
          : const [];
      return [
        for (final j in list)
          if (j is Map) MaTvVodSource.fromJson(j),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Checks that Ma TV answers and has a catalogue, for the settings line.
  /// A Ma TV without one is passed over for a while (see [recentlyFailed]).
  Future<void> _checkMaTv() async {
    try {
      final answer = await _maTvGet('langs', const {});
      final langs = answer is Map && answer['langs'] is List
          ? answer['langs'] as List
          : const [];
      var total = 0;
      for (final l in langs) {
        if (l is List && l.length > 1) total += _int(l[1]);
      }
      if (langs.isEmpty) {
        throw StateError('catalogue pas encore construit (Relire films et séries)');
      }
      _failedAt.remove(_cacheKey);
      status.value =
          'Ma TV : $total titres en ${langs.length} langues, cherchés sur la seedbox';
      // What an earlier version downloaded of it is no longer needed.
      unawaited(deleteCatalogCache(_cacheKey));
    } catch (e) {
      _failedAt[_cacheKey] = DateTime.now();
      status.value = 'Ma TV : échec (${_why(e)})';
    }
  }

  /// Said after the counts when the last fetch came back incomplete.
  String _statusNote = '';

  void _loadedStatus(List<XtreamTitle> all, {String note = ''}) {
    final films = all.where((t) => t.kind == XtreamKind.movie).length;
    final series = all.length - films;
    final at = _fetchedAt;
    final when = at == null
        ? ''
        : ', lu le ${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')} '
              'à ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    status.value = '$sourceName : $films films, $series séries$when$note';
  }

  static String _why(Object e) {
    if (e is TimeoutException) return 'trop long à arriver';
    final text = e.toString();
    return text.startsWith('Bad state: ') ? text.substring(11) : text;
  }

  Map<String, List<XtreamTitle>>? _byTmdb;

  void _index(List<XtreamTitle> all) {
    final m = <String, List<XtreamTitle>>{};
    for (final t in all) {
      if (t.tmdbId.isEmpty) continue;
      (m['${t.kind.name}:${t.tmdbId}'] ??= []).add(t);
    }
    _byTmdb = m;
    _failedAt.remove(_cacheKey);
    _loadedStatus(all, note: _statusNote);
    loaded.value++;
  }

  /// The copies of a TMDB title in the catalogue already in memory: empty
  /// while it loads (then [loaded] fires) or when the provider lacks it.
  List<XtreamTitle> copiesNow(XtreamKind kind, String tmdbId) {
    if (isMaTv) return _copiesNowRemote(kind, tmdbId);
    final index = _byTmdb;
    if (index == null) {
      warmUp();
      return const [];
    }
    return index['${kind.name}:$tmdbId'] ?? const [];
  }

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

  /// How old the catalogue may get before the daily refresh fetches it
  /// again.
  static const maxAge = Duration(hours: 24);

  /// With a seedbox preparing it, how often the device looks for the
  /// night's file. It is small, so twice a day costs little and catches the
  /// new one the morning after.
  static const serverCheckAge = Duration(hours: 12);

  /// Where the seedbox publishes the catalogue each night, login included,
  /// or empty to ask the provider directly. Set by whoever hands this
  /// catalogue out.
  String serverCatalogUrl = '';

  /// Told when the seedbox's file was read with another provider account
  /// than this catalogue's, with that account. Whoever hands catalogues out
  /// switches to it; the file is already saved under the new account.
  void Function(XtreamAccount account)? onServerAccount;

  /// When the catalogue in memory was fetched from the provider.
  DateTime? _fetchedAt;
  bool _refreshing = false;

  String get _cacheKey => catalogCacheKey(base, username);

  Future<List<XtreamTitle>> _fetchFromProvider() async {
    status.value = 'Lecture du catalogue sur $sourceName…';
    final errors = <String>[];
    Future<List<XtreamTitle>> list(
      String action,
      String what,
      List<XtreamTitle> Function(String) parse,
    ) => _get(_api(action), _listTimeout)
        .then((body) => compute(parse, body))
        .catchError((Object e) {
          errors.add('$what : ${_why(e)}');
          return <XtreamTitle>[];
        });
    final results = await Future.wait([
      list('get_vod_streams', 'films', parseVodStreams),
      list('get_series', 'séries', parseSeriesList),
    ]);
    final all = [...results[0], ...results[1]];
    if (all.isEmpty) {
      throw StateError(
        errors.isEmpty ? 'catalogue vide' : errors.join(' ; '),
      );
    }
    if (errors.isNotEmpty) {
      // Half a catalogue is kept for now but neither saved nor dated, so the
      // next check (within the hour) fetches it again instead of keeping it
      // a whole day.
      _fetchedAt = null;
      _statusNote = ' (incomplet : ${errors.join(' ; ')})';
      return all;
    }
    _statusNote = '';
    final now = DateTime.now();
    _fetchedAt = now;
    unawaited(_save(now, all));
    return all;
  }

  Future<void> _save(DateTime at, List<XtreamTitle> titles) async {
    final data = await compute(
      encodeCatalogCache,
      (fetchedAtMs: at.millisecondsSinceEpoch, titles: titles),
    );
    await writeCatalogCache(_cacheKey, data);
  }

  /// The seedbox's file when it is for this account and newer than [than];
  /// null otherwise or when it can't be had. Saved on the device as is.
  Future<List<XtreamTitle>?> _fetchFromServer({DateTime? than}) async {
    final url = serverCatalogUrl.trim();
    if (url.isEmpty) return null;
    final body = await fetchServerCatalog(url);
    if (body == null) return null;
    final cache = await compute(decodeCatalogCache, body);
    if (cache == null || cache.titles.isEmpty) return null;
    final provider = cache.provider;
    // The seedbox follows Jellyfin's account. A file read with another one
    // means the account changed there: it is saved for that account, and the
    // device moves over to it.
    if (provider != null &&
        catalogCacheKey(provider.portal, provider.username) != _cacheKey) {
      await writeCatalogCache(
        catalogCacheKey(provider.portal, provider.username),
        body,
      );
      onServerAccount?.call(provider);
      return null;
    }
    // A file made for another provider account is someone else's catalogue.
    if (cache.account.isNotEmpty && cache.account != _cacheKey) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(cache.fetchedAtMs);
    if (than != null && !at.isAfter(than)) return null;
    _fetchedAt = at;
    unawaited(writeCatalogCache(_cacheKey, body));
    return cache.titles;
  }

  /// The saved catalogue when there is one, however old (the daily refresh
  /// takes care of its age); else the seedbox's; else the provider's.
  Future<List<XtreamTitle>> _load() async {
    final saved = await readCatalogCache(_cacheKey);
    if (saved != null) {
      final cache = await compute(decodeCatalogCache, saved);
      if (cache != null && cache.titles.isNotEmpty) {
        _fetchedAt = DateTime.fromMillisecondsSinceEpoch(cache.fetchedAtMs);
        return cache.titles;
      }
    }
    return await _fetchFromServer() ?? _fetchFromProvider();
  }

  /// Loads the catalogue into memory (from the device when it was saved
  /// there), so searches and pages find it ready.
  void warmUp() {
    if (isMaTv) {
      if (status.value.isEmpty) unawaited(_checkMaTv());
      return;
    }
    unawaited(_all().then<void>((_) {}, onError: (_) {}));
  }

  /// Loads the catalogue, then fetches it again from the provider when it is
  /// older than [maxAge]. The old one keeps answering until the new one has
  /// fully arrived, and stays if the provider fails.
  Future<void> ensureFresh() async {
    if (isMaTv) return _checkMaTv();
    try {
      await _all();
    } catch (_) {
      return;
    }
    final at = _fetchedAt;
    final age = at == null ? null : DateTime.now().difference(at);
    final hasServer = serverCatalogUrl.trim().isNotEmpty;
    if (_refreshing ||
        (age != null && age < (hasServer ? serverCheckAge : maxAge))) {
      return;
    }
    _refreshing = true;
    try {
      // The seedbox's file first; the provider only when there is none, or
      // when the seedbox has missed a night and the catalogue is past a day
      // and a half.
      var fresh = await _fetchFromServer(than: at);
      if (fresh == null &&
          (!hasServer || age == null || age > maxAge + serverCheckAge)) {
        fresh = await _fetchFromProvider();
      }
      if (fresh == null) return;
      _titles = Future.value(fresh);
      _index(fresh);
    } catch (_) {
      // Tried again at the next check.
    } finally {
      _refreshing = false;
    }
  }

  Future<List<XtreamTitle>> _all() {
    if (isMaTv) return Future.value(const <XtreamTitle>[]);
    final fresh = _titles == null;
    final future = _titles ??= _load();
    if (fresh) {
      unawaited(future.then<void>(_index, onError: (Object _) {}));
    }
    future.catchError((Object e) {
      if (identical(_titles, future)) _titles = null;
      _failedAt[_cacheKey] = DateTime.now();
      status.value = '$sourceName : échec (${_why(e)})';
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
  }) async {
    if (isMaTv) {
      final answer = await _maTvGet('find', {
        'kind': kind.name,
        if (tmdbId > 0) 'tmdb': '$tmdbId',
        't': titles.where((t) => t.trim().isNotEmpty).join('\n'),
        if (year != null) 'year': '$year',
      });
      return _titlesOf(answer is Map ? answer['copies'] : null);
    }
    return _copiesOfLocal(
      kind: kind,
      tmdbId: tmdbId,
      titles: titles,
      year: year,
    );
  }

  Future<List<XtreamTitle>> _copiesOfLocal({
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
  }) async {
    if (isMaTv) {
      if (foldForSearch(query.trim()).length < 2) return const [];
      final answer = await _maTvGet('search', {
        'q': query.trim(),
        'limit': '$limit',
        if (preferredTags.isNotEmpty) 'prefer': preferredTags.join(','),
      });
      return _titlesOf(answer is Map ? answer['titles'] : null);
    }
    return searchTitles(
      await _all(),
      query,
      limit: limit,
      preferredTags: preferredTags,
    );
  }

  /// How many films and series the provider has in each language tag, most
  /// first. Titles without a tag are left out.
  Future<List<MapEntry<String, int>>> languageCounts() async {
    if (isMaTv) {
      final answer = await _maTvGet('langs', const {});
      return [
        for (final l in (answer is Map && answer['langs'] is List
            ? answer['langs'] as List
            : const []))
          if (l is List && l.length > 1) MapEntry(_str(l[0]), _int(l[1])),
      ];
    }
    final counts = <String, int>{};
    for (final t in await _all()) {
      if (t.tag.isEmpty) continue;
      counts[t.tag] = (counts[t.tag] ?? 0) + 1;
    }
    return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// The seasons and episodes of a series.
  /// With a [quality] Ma TV knows for the title, the episodes come from a copy
  /// in that quality when it still has one.
  Future<XtreamSeriesInfo> seriesInfo(
    String seriesId, {
    String quality = '',
    int? source,
  }) async {
    if (isMaTv) {
      // Ma TV's own address: on the Ultra.cc seedbox the proxy refuses
      // player_api.php (404), so the episodes never came. An older Ma TV
      // without it falls back to player_api.php.
      try {
        return parseSeriesInfo(
          await _get(
            _vodApi('info', {
              'kind': 'series',
              'id': seriesId,
              if (quality.isNotEmpty) 'q': quality,
              if (source != null) 'src': '$source',
            }),
            _infoTimeout,
          ),
        );
      } on StateError catch (e) {
        if (!e.message.contains('404')) rethrow;
      }
    }
    return parseSeriesInfo(
      await _get(
        _api('get_series_info', {
          'series_id': seriesId,
          if (quality.isNotEmpty) 'q': quality,
          if (source != null && isMaTv) 'src': '$source',
        }),
        _infoTimeout,
      ),
    );
  }

  String _seg(String value) => Uri.encodeComponent(value);

  /// Where a film plays from. A [quality] is asked for only when the title
  /// comes in several (Ma TV then plays that copy first, the others as a
  /// fallback); a provider read directly never sees it.
  /// A [source] picked on the page (Ma TV's file number) is played first.
  String movieUrl(XtreamTitle movie, {String quality = '', int? source}) {
    final query = [
      if (quality.isNotEmpty && movie.qualities.length > 1)
        'q=${Uri.encodeQueryComponent(quality)}',
      if (source != null && isMaTv) 'src=$source',
    ];
    return '$base/movie/${_seg(username)}/${_seg(password)}/'
        '${movie.id}.${movie.extension}'
        '${query.isEmpty ? '' : '?${query.join('&')}'}';
  }

  /// Where an episode plays from.
  String episodeUrl(XtreamEpisode episode) =>
      '$base/series/${_seg(username)}/${_seg(password)}/'
      '${episode.id}.${episode.extension}';
}
