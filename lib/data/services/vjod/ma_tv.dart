/// VJOD's own live TV, read straight from IPTV Checker's "Ma TV" on the
/// seedbox: categories (themes and countries), the channels of one category
/// with what is on now and next, the guide a few hours at a time, and the
/// relay address that plays a channel (with failover between sources, one
/// provider connection shared by everyone watching the same channel).
///
/// Jellyfin stays the sign-in and the say on who may watch TV, and hands
/// VJOD Ma TV's address (the "VJOD – TV" collection); the channels themselves
/// no longer wait on Jellyfin's guide import.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:server_core/server_core.dart';

import '../../../auth/repositories/session_repository.dart';
import '../../../preference/seerr_preferences.dart';
import '../../../util/platform_detection.dart';
import 'jellyfin_vjod_config.dart';
import 'tv_sources.dart';

class MaTvCategory {
  final String id;
  final String label;

  /// all, replay, theme, country, or (local) fav / recent.
  final String kind;
  final int count;

  const MaTvCategory({required this.id, required this.label, required this.kind, required this.count});

  factory MaTvCategory.fromJson(Map<String, dynamic> j) => MaTvCategory(
    id: j['id']?.toString() ?? '',
    label: j['label']?.toString() ?? '',
    kind: j['kind']?.toString() ?? '',
    count: (j['n'] as num?)?.toInt() ?? 0,
  );
}

class MaTvProgram {
  final String title;
  final DateTime start;
  final DateTime end;
  final String subtitle;
  final String description;
  final String image;
  final String category;
  final String episode;

  const MaTvProgram({
    required this.title,
    required this.start,
    required this.end,
    this.subtitle = '',
    this.description = '',
    this.image = '',
    this.category = '',
    this.episode = '',
  });

  static MaTvProgram? fromJson(Object? json) {
    if (json is! Map) return null;
    final s = (json['s'] as num?)?.toInt();
    final e = (json['e'] as num?)?.toInt();
    if (s == null || e == null) return null;
    return MaTvProgram(
      title: json['t']?.toString() ?? '',
      start: DateTime.fromMillisecondsSinceEpoch(s * 1000),
      end: DateTime.fromMillisecondsSinceEpoch(e * 1000),
      subtitle: json['st']?.toString() ?? '',
      description: json['d']?.toString() ?? '',
      image: json['i']?.toString() ?? '',
      category: json['c']?.toString() ?? '',
      episode: json['ep']?.toString() ?? '',
    );
  }

  bool isOnAt(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  /// 0..1 of the programme gone by at [t].
  double progressAt(DateTime t) {
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (t.difference(start).inSeconds / total).clamp(0.0, 1.0);
  }

  int get minutes => end.difference(start).inMinutes;
}

class MaTvChannel {
  final String id;
  final int number;
  final String name;
  final String logo;
  final String theme;
  final String country;
  final String quality;

  /// Days of replay the best provider keeps, 0 when none.
  final int replayDays;
  final MaTvProgram? now;
  final MaTvProgram? next;

  const MaTvChannel({
    required this.id,
    required this.number,
    required this.name,
    this.logo = '',
    this.theme = '',
    this.country = '',
    this.quality = '',
    this.replayDays = 0,
    this.now,
    this.next,
  });

  factory MaTvChannel.fromJson(Map<String, dynamic> j) => MaTvChannel(
    id: j['id']?.toString() ?? '',
    number: (j['num'] as num?)?.toInt() ?? 0,
    name: j['name']?.toString() ?? '',
    logo: j['logo']?.toString() ?? '',
    theme: j['theme']?.toString() ?? '',
    country: j['cc']?.toString() ?? '',
    quality: j['q']?.toString() ?? '',
    replayDays: (j['arc'] as num?)?.toInt() ?? 0,
    now: MaTvProgram.fromJson(j['now']),
    next: MaTvProgram.fromJson(j['next']),
  );

  /// The programme on at [t] among the two known, rolling over to the next
  /// one once the current has ended.
  MaTvProgram? programAt(DateTime t) {
    if (now != null && now!.isOnAt(t)) return now;
    if (next != null && next!.isOnAt(t)) return next;
    return null;
  }

  MaTvProgram? programAfter(DateTime t) {
    final cur = programAt(t);
    if (cur == now) return next;
    return null;
  }
}

/// Reads Ma TV. Every call fails quietly (null) so the screens can offer the
/// Jellyfin guide when the seedbox can't be reached.
class MaTvClient {
  MaTvClient({http.Client? httpClient, TvSourcesServer? server})
    : _http = httpClient,
      _fixed = server;

  final http.Client? _http;
  final TvSourcesServer? _fixed;

  static const _timeout = Duration(seconds: 8);
  static final Map<String, ({DateTime at, List<MaTvChannel> chans})> _chanCache = {};
  static ({DateTime at, List<MaTvCategory> cats})? _catCache;

  TvSourcesServer? get server => _fixed ?? TvSourcesClient().server;
  bool get isConfigured => server != null;

  /// The Jellyfin user, so source choices stay per profile.
  String? get user {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<SessionRepository>()) return null;
    return getIt<SessionRepository>().activeUserId;
  }

  TvSourcesClient sourcesClient() => TvSourcesClient(server: server, user: user, caps: MaTvDevice.capsSync);

  Future<Object?> _get(String path, [Map<String, String> query = const {}]) async {
    final s = server;
    if (s == null) return null;
    try {
      final uri = s.endpoint(path, query);
      final r = await (_http?.get(uri) ?? http.get(uri)).timeout(_timeout);
      if (r.statusCode != 200) return null;
      return jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  Future<List<MaTvCategory>?> categories({bool fresh = false}) async {
    final c = _catCache;
    if (!fresh && c != null && DateTime.now().difference(c.at) < const Duration(minutes: 5)) {
      return c.cats;
    }
    final json = await _get('/tv/api/cats');
    if (json is! Map || json['cats'] is! List) return c?.cats;
    final cats = [
      for (final x in json['cats'] as List)
        if (x is Map) MaTvCategory.fromJson(Map<String, dynamic>.from(x)),
    ];
    _catCache = (at: DateTime.now(), cats: cats);
    return cats;
  }

  /// The channels of [category] (`all`, `t:Sport`, `c:FR`…), with now/next.
  /// Kept a minute so zapping back and forth costs nothing.
  Future<List<MaTvChannel>?> channels(String category, {bool fresh = false}) async {
    final c = _chanCache[category];
    if (!fresh && c != null && DateTime.now().difference(c.at) < const Duration(minutes: 1)) {
      return c.chans;
    }
    final json = await _get('/tv/api/chans', {'cat': category});
    if (json is! Map || json['chans'] is! List) return c?.chans;
    final chans = [
      for (final x in json['chans'] as List)
        if (x is Map) MaTvChannel.fromJson(Map<String, dynamic>.from(x)),
    ];
    _chanCache[category] = (at: DateTime.now(), chans: chans);
    return chans;
  }

  /// Every known channel, for number entry.
  Future<List<MaTvChannel>?> allChannels() => channels('all');

  /// Some channels by id, in that order (favourites, recents): asks only for
  /// them rather than the whole lineup.
  Future<List<MaTvChannel>?> channelsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final json = await _get('/tv/api/chans', {'ids': ids.take(300).join(',')});
    if (json is! Map || json['chans'] is! List) return null;
    return [
      for (final x in json['chans'] as List)
        if (x is Map) MaTvChannel.fromJson(Map<String, dynamic>.from(x)),
    ];
  }

  /// Programmes of up to 100 channels between [from] and [to].
  Future<Map<String, List<MaTvProgram>>?> programs(List<String> ids, DateTime from, DateTime to) async {
    if (ids.isEmpty) return const {};
    final json = await _get('/tv/api/epg', {
      'ids': ids.take(100).join(','),
      'from': '${from.millisecondsSinceEpoch ~/ 1000}',
      'to': '${to.millisecondsSinceEpoch ~/ 1000}',
    });
    if (json is! Map || json['progs'] is! Map) return null;
    final out = <String, List<MaTvProgram>>{};
    (json['progs'] as Map).forEach((k, v) {
      out[k.toString()] = [
        if (v is List)
          for (final p in v)
            if (MaTvProgram.fromJson(p) case final MaTvProgram prog) prog,
      ];
    });
    return out;
  }

  Map<String, String> get _who => {
    if (user != null && user!.isNotEmpty) 'u': user!,
    if (MaTvDevice.capsSync.isNotEmpty) 'caps': MaTvDevice.capsSync,
  };

  /// The relay address playing [channel] live.
  Uri? liveUri(MaTvChannel channel) => server?.endpoint('/tv/play/${channel.id}.ts', _who);

  /// A past programme (or the current one from its start), when the provider
  /// keeps it.
  Uri? replayUri(MaTvChannel channel, MaTvProgram program) {
    final minutes = program.end.difference(program.start).inMinutes + 5;
    return server?.endpoint('/tv/replay/${channel.id}.ts', {
      'start': '${program.start.millisecondsSinceEpoch ~/ 1000}',
      'dur': '${minutes.clamp(5, 600)}',
      if (MaTvDevice.capsSync.isNotEmpty) 'caps': MaTvDevice.capsSync,
    });
  }

  static void forgetCache() {
    _chanCache.clear();
    _catCache = null;
  }
}

/// What the device decodes in hardware, asked once to Android: a box that
/// can't decode HEVC gets H.264 sources first instead of a stuttering picture.
class MaTvDevice {
  static const _channel = MethodChannel('vjod/matv');
  static String _caps = '';

  static String get capsSync => _caps;

  static Future<String> caps() async {
    if (_caps.isNotEmpty) return _caps;
    var hevc = true;
    if (PlatformDetection.isAndroid) {
      try {
        hevc = await _channel.invokeMethod<bool>('hasHevcDecoder') ?? true;
      } catch (_) {
        hevc = true;
      }
    }
    _caps = hevc ? 'h264,hevc' : 'h264';
    return _caps;
  }
}

/// Whether this Jellyfin profile may watch live TV (the server's "Allow Live
/// TV access"). Remembered for the session; an unreachable server keeps the
/// last answer rather than locking the family out.
class MaTvAccess {
  static bool? _allowed;

  static Future<bool> allowed() async {
    final known = _allowed;
    if (known != null) return known;
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<MediaServerClient>()) return true;
    try {
      final user = await getIt<MediaServerClient>().usersApi.getCurrentUser().timeout(const Duration(seconds: 6));
      final policy = user.policy;
      _allowed = policy == null || policy.enableLiveTvAccess || policy.isAdministrator;
    } catch (_) {
      return true;
    }
    return _allowed!;
  }

  static void reset() => _allowed = null;
}

/// Makes sure Ma TV's address is known, reading it from Jellyfin's "VJOD – TV"
/// collection when it isn't yet.
Future<bool> ensureMaTvConfigured() async {
  if (MaTvClient().isConfigured) return true;
  try {
    await syncVjodConfigFromServer();
  } catch (_) {}
  return MaTvClient().isConfigured;
}

/// Favourites, recents and the last channel, per profile.
class MaTvMemory {
  static SeerrPreferences? get _prefs {
    final getIt = GetIt.instance;
    return getIt.isRegistered<SeerrPreferences>() ? getIt<SeerrPreferences>() : null;
  }

  static List<String> get favorites => _prefs?.maTvFavorites ?? const [];
  static bool isFavorite(String id) => favorites.contains(id);

  static Future<bool> toggleFavorite(String id) async {
    final p = _prefs;
    if (p == null) return false;
    final list = [...p.maTvFavorites];
    final now = !list.remove(id);
    if (now) list.add(id);
    await p.setMaTvFavorites(list);
    return now;
  }

  static List<String> get recent => _prefs?.maTvRecent ?? const [];
  static String get lastChannel => _prefs?.maTvLastChannel ?? '';
  static String get lastCategory => _prefs?.maTvLastCategory ?? '';

  static Future<void> watched(String id, String category) async {
    final p = _prefs;
    if (p == null) return;
    final list = [id, ...p.maTvRecent.where((x) => x != id)];
    await p.setMaTvRecent(list);
    await p.setMaTvLastChannel(id);
    if (category.isNotEmpty) await p.setMaTvLastCategory(category);
  }
}
