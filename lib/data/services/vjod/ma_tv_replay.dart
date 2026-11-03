// The channels' own replay (VJOD 4.18, Ma TV 3.62): Ma TV keeps the
// catalogue of Arte and France 2 to 5 (three weeks, weather, news and daily
// games left out), VJOD shows it and plays the episode itself. The video is
// asked for by this device, from France, at the moment it plays: the
// channels keep their videos to French addresses, and the seedbox may not
// be one. An encrypted (DRM) episode is never played here: it opens in the
// channel's own app, last of all.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../util/tv_app_launcher.dart';
import '../../../util/vjod_log.dart';
import 'ma_tv.dart';
import 'tv_sources.dart';

@immutable
class ReplayItem {
  final String id;

  /// `arte` or `ftv` (France Télévisions).
  final String kind;

  /// `arte`, `france-2`…
  final String chan;
  final String show;
  final String title;
  final DateTime? aired;
  final Duration duration;
  final String description;
  final String image;

  /// The episode's page at the channel (its app opens on it).
  final String page;
  final int season;
  final int episode;
  final bool featured;
  final bool followed;

  /// Aired since this profile last opened « Mes émissions ».
  final bool isNew;

  const ReplayItem({
    required this.id,
    required this.kind,
    required this.chan,
    required this.show,
    this.title = '',
    this.aired,
    this.duration = Duration.zero,
    this.description = '',
    this.image = '',
    this.page = '',
    this.season = 0,
    this.episode = 0,
    this.featured = false,
    this.followed = false,
    this.isNew = false,
  });

  factory ReplayItem.fromJson(Map<String, dynamic> j) {
    final aired = (j['aired'] as num?)?.toInt() ?? 0;
    int n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    return ReplayItem(
      id: '${j['id'] ?? ''}',
      kind: '${j['kind'] ?? ''}',
      chan: '${j['chan'] ?? ''}',
      show: '${j['show'] ?? ''}',
      title: '${j['title'] ?? ''}',
      aired: aired > 0 ? DateTime.fromMillisecondsSinceEpoch(aired * 1000) : null,
      duration: Duration(seconds: (j['dur'] as num?)?.toInt() ?? 0),
      description: '${j['desc'] ?? ''}',
      image: '${j['img'] ?? ''}',
      page: '${j['page'] ?? ''}',
      season: n(j['season']),
      episode: n(j['episode']),
      featured: j['featured'] == true,
      followed: j['followed'] == true,
      isNew: j['new'] == true,
    );
  }

  /// « Lun. 2 nov. », the day it aired.
  String get dayLabel {
    final a = aired;
    if (a == null) return '';
    const days = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
    const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    return '${days[a.weekday - 1]} ${a.day == 1 ? '1er' : a.day} ${months[a.month - 1]}';
  }

  /// What the card says under the show: the episode, else the day.
  String get subtitle {
    if (season > 0 && episode > 0) return 'S$season · É$episode${title.isNotEmpty ? ' · $title' : ''}';
    if (title.isNotEmpty && title != show) return title;
    return dayLabel;
  }
}

@immutable
class ReplayChannel {
  final String chan;
  final String name;
  final int fresh;
  final int count;
  const ReplayChannel({required this.chan, required this.name, this.fresh = 0, this.count = 0});
}

@immutable
class ReplayHome {
  final List<ReplayItem> mine;
  final int mineNew;
  final List<ReplayChannel> channels;
  final List<ReplayItem> featured;
  const ReplayHome({this.mine = const [], this.mineNew = 0, this.channels = const [], this.featured = const []});

  bool get isEmpty => channels.every((c) => c.count == 0);

  factory ReplayHome.fromJson(Map<String, dynamic> j) => ReplayHome(
    mine: _items(j['mine']),
    mineNew: (j['mine_new'] as num?)?.toInt() ?? 0,
    channels: [
      for (final c in (j['chans'] as List? ?? const []))
        if (c is Map)
          ReplayChannel(
            chan: '${c['chan']}',
            name: '${c['name']}',
            fresh: (c['new'] as num?)?.toInt() ?? 0,
            count: (c['count'] as num?)?.toInt() ?? 0,
          ),
    ],
    featured: _items(j['featured']),
  );
}

@immutable
class ReplayShow {
  final String show;
  final bool followed;
  final List<ReplayItem> items;
  const ReplayShow({required this.show, this.followed = false, this.items = const []});
}

@immutable
class ReplayDay {
  final DateTime day;
  final List<ReplayItem> items;
  const ReplayDay({required this.day, this.items = const []});

  /// « Aujourd\u2019hui », « Hier », then « Lun. 2 nov. ».
  String label([DateTime? now]) {
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    final d = DateTime(day.year, day.month, day.day);
    final ago = today.difference(d).inDays;
    if (ago == 0) return 'Aujourd\u2019hui';
    if (ago == 1) return 'Hier';
    const wd = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
    const mo = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    return '${wd[d.weekday - 1]} ${d.day == 1 ? '1er' : d.day} ${mo[d.month - 1]}';
  }
}

/// The episode of the same show aired just after [e] in [list] (any order),
/// or null.
ReplayItem? nextEpisode(ReplayItem e, Iterable<ReplayItem> list) {
  final at = e.aired;
  if (at == null) return null;
  ReplayItem? best;
  for (final x in list) {
    final t = x.aired;
    if (x.id == e.id || x.show != e.show || t == null || !t.isAfter(at)) continue;
    if (best == null || t.isBefore(best.aired!)) best = x;
  }
  return best;
}

@immutable
class ReplayChannelPage {
  final String chan;
  final String name;
  final ReplayItem? prime;
  final List<ReplayShow> shows;

  /// Day by day, the latest first.
  final List<ReplayDay> days;
  const ReplayChannelPage({required this.chan, required this.name, this.prime, this.shows = const [], this.days = const []});

  factory ReplayChannelPage.fromJson(Map<String, dynamic> j) => ReplayChannelPage(
    chan: '${j['chan'] ?? ''}',
    name: '${j['name'] ?? ''}',
    prime: j['prime'] is Map ? ReplayItem.fromJson(Map<String, dynamic>.from(j['prime'] as Map)) : null,
    shows: [
      for (final s in (j['shows'] as List? ?? const []))
        if (s is Map)
          ReplayShow(show: '${s['show']}', followed: s['followed'] == true, items: _items(s['items'])),
    ],
    days: [
      for (final d in (j['days'] as List? ?? const []))
        if (d is Map && DateTime.tryParse('${d['day']}') != null)
          ReplayDay(day: DateTime.parse('${d['day']}'), items: _items(d['items'])),
    ],
  );
}

List<ReplayItem> _items(Object? list) => [
  for (final x in (list as List? ?? const []))
    if (x is Map) ReplayItem.fromJson(Map<String, dynamic>.from(x)),
];

/// How a replay episode plays: a stream VJOD's player reads, or the
/// channel's own app (encrypted episode, or the channel changed its format).
@immutable
class ReplayPlayback {
  final String? url;
  final String? reason;
  const ReplayPlayback.stream(String this.url) : reason = null;
  const ReplayPlayback.app(String this.reason) : url = null;
  bool get inVjod => url != null;
}

class MaTvReplay {
  MaTvReplay({http.Client? httpClient, TvSourcesServer? server}) : _http = httpClient, _server = server;

  final http.Client? _http;
  final TvSourcesServer? _server;

  static const _timeout = Duration(seconds: 12);
  static const _ua = 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

  TvSourcesServer? get server => _server ?? TvSourcesClient().server;
  String get _user => MaTvClient().user ?? '';

  Future<Object?> _get(String path, [Map<String, String> query = const {}]) async {
    final s = server;
    if (s == null) return null;
    try {
      final uri = s.endpoint(path, {...query, if (_user.isNotEmpty) 'u': _user});
      final r = await (_http?.get(uri) ?? http.get(uri)).timeout(_timeout);
      if (r.statusCode != 200) return null;
      return jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  /// The Home row: followed shows' new episodes and the channels. Null when
  /// Ma TV is older than 3.62 or can't be reached.
  Future<ReplayHome?> home() async {
    final j = await _get('/tv/api/replay/home');
    return j is Map ? ReplayHome.fromJson(Map<String, dynamic>.from(j)) : null;
  }

  Future<ReplayChannelPage?> channel(String chan) async {
    final j = await _get('/tv/api/replay/chan', {'c': chan});
    return j is Map ? ReplayChannelPage.fromJson(Map<String, dynamic>.from(j)) : null;
  }

  Future<List<ReplayItem>> search(String text) async {
    final j = await _get('/tv/api/replay/search', {'q': text});
    return j is Map ? _items(j['items']) : const [];
  }

  /// « Suivre », « Pas pour nous », the news and weather shown again, or the
  /// Home row seen (its badges reset).
  Future<bool> setPref({String? show, bool? follow, bool? hide, String? item, bool? showNoise, bool seen = false}) async {
    final s = server;
    if (s == null) return false;
    try {
      final body = jsonEncode({
        'user': _user,
        'show': ?show,
        'follow': ?follow,
        'hide': ?hide,
        'item': ?item,
        'show_noise': ?showNoise,
        if (seen) 'seen': true,
      });
      final uri = s.endpoint('/tv/api/replay/pref');
      final r = await (_http?.post(uri, headers: {'Content-Type': 'application/json'}, body: body) ??
              http.post(uri, headers: {'Content-Type': 'application/json'}, body: body))
          .timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ----------------------------------------------------------------- lecture
  /// Where the episode plays: the stream the channel serves this device, or
  /// its app when the episode is encrypted or can't be read.
  Future<ReplayPlayback> playback(ReplayItem item) async {
    try {
      final url = switch (item.kind) {
        'arte' => await _arte(item),
        'ftv' => await _ftv(item),
        _ => null,
      };
      if (url != null && url.isNotEmpty) return ReplayPlayback.stream(url);
    } on _Encrypted {
      return const ReplayPlayback.app('chiffré');
    } catch (e) {
      vjodLogError('Replay : lecture de ${item.kind}', e);
    }
    return const ReplayPlayback.app('illisible ici');
  }

  Future<Map<String, dynamic>> _json(Uri uri, [Map<String, String> headers = const {}]) async {
    final r = await (_http?.get(uri, headers: {'User-Agent': _ua, ...headers}) ??
            http.get(uri, headers: {'User-Agent': _ua, ...headers}))
        .timeout(_timeout);
    if (r.statusCode != 200) throw StateError('HTTP ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (j is! Map) throw const FormatException('réponse inattendue');
    return Map<String, dynamic>.from(j);
  }

  /// Arte: the player's settings for the programme; the French version
  /// first (VF, then original with French subtitles).
  Future<String?> _arte(ReplayItem item) async {
    final ref = item.id.isEmpty ? '' : await _ref(item);
    if (ref.isEmpty) return null;
    final j = await _json(Uri.parse('https://api.arte.tv/api/player/v2/config/fr/$ref'));
    final streams = ((j['data'] as Map?)?['attributes'] as Map?)?['streams'] as List? ?? const [];
    String? pick(bool Function(String label) ok) {
      for (final s in streams) {
        if (s is! Map) continue;
        final versions = s['versions'] as List? ?? const [];
        final label = versions.isEmpty ? '' : '${(versions.first as Map?)?['shortLabel'] ?? (versions.first as Map?)?['label'] ?? ''}';
        if (ok(label.toUpperCase())) return '${s['url'] ?? ''}';
      }
      return null;
    }
    return pick((l) => l == 'VF' || l.startsWith('VF ')) ??
        pick((l) => l.contains('VOSTF') || l.contains('STF')) ??
        pick((_) => true);
  }

  /// France Télévisions: the video's settings, then a signed address. An
  /// encrypted video goes to the app.
  Future<String?> _ftv(ReplayItem item) async {
    final ref = await _ref(item);
    if (ref.isEmpty) return null;
    final info = await _json(Uri.https('k7.ftven.fr', '/videos/$ref', {
      'country_code': 'FR',
      'capabilities': 'drm',
      'os': 'androidtv',
      'diffusion_mode': 'tunnel_first',
      'offline': 'false',
    }));
    final video = info['video'];
    if (video is! Map) return null;
    if (video['drm'] == true) throw const _Encrypted();
    final url = '${video['url'] ?? ''}';
    if (url.isEmpty) return null;
    final signed = await _json(Uri.https('hdfauth.ftven.fr', '/esi/TA', {'format': 'json', 'url': url}));
    return '${signed['url'] ?? ''}';
  }

  /// The episode's reference at the channel, kept by Ma TV with the item.
  Future<String> _ref(ReplayItem item) async {
    final j = await _get('/tv/api/replay/item', {'id': item.id});
    return j is Map ? '${j['ref'] ?? ''}' : '';
  }

  // ------------------------------------------------------- appli officielle
  /// The channel's app (its TV app on a box), on the episode's page when it
  /// can; false when nothing could open.
  static Future<bool> openOfficial(ReplayItem item, {bool tv = false}) async {
    final page = Uri.tryParse(item.page);
    if (page != null && page.hasScheme) {
      try {
        if (await launchUrl(page, mode: LaunchMode.externalNonBrowserApplication)) return true;
      } catch (_) {}
    }
    final pkg = officialApps[item.kind];
    if (pkg != null) {
      TvApp app(String p) => TvApp(id: p, label: p, package: p);
      for (final p in tv ? [pkg.tv, pkg.phone] : [pkg.phone]) {
        if (await TvAppLauncher.launch(app(p))) return true;
      }
      if (await TvAppLauncher.openStore(app(tv ? pkg.tv : pkg.phone))) return true;
    }
    if (page != null && page.hasScheme) {
      try {
        return await launchUrl(page, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    return false;
  }

  /// The channels' apps (phone, then TV box).
  static const officialApps = <String, ({String phone, String tv})>{
    'arte': (phone: 'tv.arte.plus7', tv: 'tv.arte.plus7'),
    'ftv': (phone: 'fr.francetv.pluzz', tv: 'fr.francetv.pluzz'),
  };
}

class _Encrypted implements Exception {
  const _Encrypted();
}

/// The order of the channel tiles on Home: the pinned ones first, then by
/// use, but frozen for the week so a tile never moves under the finger.
/// A channel new to the catalogue joins at the end.
class ReplayOrder {
  static const _usesKey = 'vjod_replay_uses';
  static const _orderKey = 'vjod_replay_order';
  static const _pinsKey = 'vjod_replay_pins';

  /// Week number since the epoch (weeks start on Monday).
  static int weekOf(DateTime t) => DateTime.utc(t.year, t.month, t.day).add(const Duration(days: 3)).millisecondsSinceEpoch ~/ (7 * 86400000);

  /// Pure: [channels] (Ma TV's order) arranged by [pins], then [frozen],
  /// then the rest in Ma TV's order.
  static List<ReplayChannel> arrange(List<ReplayChannel> channels, {List<String> frozen = const [], List<String> pins = const []}) {
    final by = {for (final c in channels) c.chan: c};
    final out = <ReplayChannel>[];
    final seen = <String>{};
    for (final id in [...pins, ...frozen, ...channels.map((c) => c.chan)]) {
      final c = by[id];
      if (c != null && seen.add(id)) out.add(c);
    }
    return out;
  }

  /// Pure: the week's order from the use counts (most used first, ties in
  /// Ma TV's order).
  static List<String> rank(List<ReplayChannel> channels, Map<String, int> uses) {
    final idx = {for (var i = 0; i < channels.length; i++) channels[i].chan: i};
    final ids = channels.map((c) => c.chan).toList()
      ..sort((a, b) {
        final u = (uses[b] ?? 0).compareTo(uses[a] ?? 0);
        return u != 0 ? u : idx[a]!.compareTo(idx[b]!);
      });
    return ids;
  }

  static Future<SharedPreferences?> _sp() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static Map<String, int> _uses(SharedPreferences sp) {
    try {
      final j = jsonDecode(sp.getString(_usesKey) ?? '{}');
      return {for (final e in (j as Map).entries) '${e.key}': (e.value as num).toInt()};
    } catch (_) {
      return {};
    }
  }

  static Future<List<String>> pins() async => (await _sp())?.getStringList(_pinsKey) ?? const [];

  static Future<bool> isPinned(String chan) async => (await pins()).contains(chan);

  static Future<void> togglePin(String chan) async {
    final sp = await _sp();
    if (sp == null) return;
    final p = List.of(sp.getStringList(_pinsKey) ?? const <String>[]);
    p.contains(chan) ? p.remove(chan) : p.add(chan);
    await sp.setStringList(_pinsKey, p);
  }

  /// A channel's page was opened: counts for next week's order.
  static Future<void> noteOpen(String chan) async {
    final sp = await _sp();
    if (sp == null) return;
    final u = _uses(sp);
    u[chan] = (u[chan] ?? 0) + 1;
    await sp.setString(_usesKey, jsonEncode(u));
  }

  /// [channels] in this week's order (computed once a week from the uses).
  static Future<List<ReplayChannel>> sort(List<ReplayChannel> channels, {DateTime? now}) async {
    final sp = await _sp();
    if (sp == null) return channels;
    final week = weekOf(now ?? DateTime.now());
    List<String> frozen = const [];
    try {
      final j = jsonDecode(sp.getString(_orderKey) ?? '{}') as Map;
      if (j['week'] == week) frozen = [for (final s in (j['order'] as List)) '$s'];
    } catch (_) {}
    if (frozen.isEmpty) {
      frozen = rank(channels, _uses(sp));
      await sp.setString(_orderKey, jsonEncode({'week': week, 'order': frozen}));
    }
    return arrange(channels, frozen: frozen, pins: sp.getStringList(_pinsKey) ?? const []);
  }
}

/// A channel's name reduced for matching Ma TV's guide (« France 2 HD »,
/// « FRANCE 2 », « france-2 » all give `france2`).
String replayNameKey(String s) {
  var k = s.toLowerCase().replaceFirst(RegExp(r'^\s*(fr|fra|france)\s*[:|]\s*'), '');
  k = k.replaceAll(RegExp(r'[^a-z0-9]'), '');
  return k.replaceFirst(RegExp(r'(uhd|fhd|hd|sd|4k)$'), '');
}

/// The logo Ma TV already has for each replay channel, by its replay id.
Future<Map<String, String>> replayLogos(List<ReplayChannel> channels) async {
  final all = await MaTvClient().allChannels().timeout(const Duration(seconds: 6), onTimeout: () => null).catchError((_) => null);
  if (all == null) return const {};
  final byName = <String, String>{};
  for (final c in all) {
    if (c.logo.isEmpty) continue;
    byName.putIfAbsent(replayNameKey(c.name), () => c.logo);
  }
  return {
    for (final c in channels)
      if (byName[replayNameKey(c.name)] ?? byName[replayNameKey(c.chan)] case final logo?) c.chan: logo,
  };
}
