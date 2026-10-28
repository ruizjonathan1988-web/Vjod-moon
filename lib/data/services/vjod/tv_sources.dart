/// "Ma TV" of IPTV Checker, the seedbox app that feeds Jellyfin's live TV: each
/// channel of its lineup (fixed numbers, TF1 = 1…) is backed by several
/// provider streams, and its relay can switch between them while playing.
///
/// VJOD reads the sources of the channel on screen and asks the relay for
/// another one; the stream already playing changes source on the spot, so the
/// player never has to retune. The address and key come from the Jellyfin
/// collection "VJOD – TV" IPTV Checker writes, or from a code pasted by hand.
library;

import 'dart:async';
import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;

import '../../../preference/seerr_preferences.dart';

/// Where IPTV Checker's "Ma TV" answers, and the key its TV routes expect.
class TvSourcesServer {
  final String url;
  final String key;

  const TvSourcesServer({required this.url, required this.key});

  static TvSourcesServer? fromJson(Object? json) {
    if (json is! Map) return null;
    final url = _cleanUrl(json['url']?.toString());
    final key = json['key']?.toString().trim() ?? '';
    if (url == null || key.isEmpty) return null;
    return TvSourcesServer(url: url, key: key);
  }

  /// A code copied from IPTV Checker by hand: `https://host/path#key`.
  static TvSourcesServer? fromCode(String code) {
    final text = code.trim();
    final hash = text.lastIndexOf('#');
    if (hash <= 0) return null;
    return fromJson({'url': text.substring(0, hash), 'key': text.substring(hash + 1)});
  }

  Map<String, dynamic> toJson() => {'url': url, 'key': key};

  Uri endpoint(String path, [Map<String, String> query = const {}]) {
    final base = Uri.parse('$url$path');
    return base.replace(queryParameters: {...query, 'k': key});
  }

  static String? _cleanUrl(String? raw) {
    var url = (raw ?? '').trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    if (!uri.isScheme('http') && !uri.isScheme('https')) return null;
    return url;
  }
}

/// The server carried by a Jellyfin collection's overview (marker
/// `VJOD-TV:` followed by base64 JSON), or null.
TvSourcesServer? tvServerFromOverview(String? overview) {
  final match = RegExp(r'VJOD-TV:([A-Za-z0-9_\-+/=]+)').firstMatch(overview ?? '');
  if (match == null) return null;
  try {
    final raw = match.group(1)!.replaceAll('+', '-').replaceAll('/', '_');
    final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(raw))));
    return TvSourcesServer.fromJson(json);
  } catch (_) {
    return null;
  }
}

/// One provider stream behind a channel, as the relay ranks it.
class TvSource {
  final String key;
  final int rank;
  final String provider;
  final String streamName;
  final String quality;
  final int? height;
  final double? fps;
  final int? kbps;
  final int? openMs;
  final String? codec;
  final bool? ok;
  final int? testedAt;
  final bool chosen;
  final bool sticky;
  final bool playing;
  final int busy;

  const TvSource({
    required this.key,
    required this.rank,
    required this.provider,
    required this.streamName,
    required this.quality,
    this.height,
    this.fps,
    this.kbps,
    this.openMs,
    this.codec,
    this.ok,
    this.testedAt,
    this.chosen = false,
    this.sticky = false,
    this.playing = false,
    this.busy = 0,
  });

  factory TvSource.fromJson(Map<String, dynamic> j) => TvSource(
    key: j['k']?.toString() ?? '',
    rank: (j['n'] as num?)?.toInt() ?? 0,
    provider: j['provider']?.toString() ?? '',
    streamName: j['name']?.toString() ?? '',
    quality: j['quality']?.toString() ?? '',
    height: (j['h'] as num?)?.toInt(),
    fps: (j['fps'] as num?)?.toDouble(),
    kbps: (j['kbps'] as num?)?.toInt(),
    openMs: (j['ms'] as num?)?.toInt(),
    codec: j['codec']?.toString(),
    ok: j['ok'] is bool ? j['ok'] as bool : null,
    testedAt: (j['tested'] as num?)?.toInt(),
    chosen: j['pref'] == true,
    sticky: j['sticky'] == true,
    playing: j['playing'] == true,
    busy: (j['busy'] as num?)?.toInt() ?? 0,
  );

  /// "1080p", or the quality the provider announces when never measured.
  String get resolutionLabel {
    final h = height;
    if (h != null && h > 0) {
      if (h >= 2000) return '4K';
      return '${h}p';
    }
    return quality == 'ND' ? '' : quality;
  }

  /// "1080p · 50 i/s · 6,2 Mb/s · 0,8 s", the measured facts that set the rank.
  String details({bool french = true}) {
    final parts = <String>[];
    final res = resolutionLabel;
    if (res.isNotEmpty) parts.add(res);
    final f = fps;
    if (f != null && f > 0) parts.add('${f.round()} ${french ? 'i/s' : 'fps'}');
    final b = kbps;
    if (b != null && b > 0) parts.add('${_decimal(b / 1000, french)} Mb/s');
    final ms = openMs;
    if (ms != null && ms > 0) parts.add('${_decimal(ms / 1000, french)} s');
    return parts.join(' · ');
  }

  static String _decimal(double v, bool french) {
    final s = v.toStringAsFixed(1);
    return french ? s.replaceAll('.', ',') : s;
  }
}

/// A lineup channel and its sources, best first (or the chosen one first).
class TvChannelSources {
  final String id;
  final int number;
  final String name;
  final List<TvSource> sources;

  const TvChannelSources({
    required this.id,
    required this.number,
    required this.name,
    required this.sources,
  });

  factory TvChannelSources.fromJson(Map<String, dynamic> j) => TvChannelSources(
    id: j['id']?.toString() ?? '',
    number: (j['num'] as num?)?.toInt() ?? 0,
    name: j['name']?.toString() ?? '',
    sources: [
      for (final s in (j['sources'] as List? ?? const []))
        if (s is Map) TvSource.fromJson(Map<String, dynamic>.from(s)),
    ],
  );

  /// The source feeding the stream now, else the one a tune would open.
  TvSource? get current {
    for (final s in sources) {
      if (s.playing) return s;
    }
    return sources.isEmpty ? null : sources.first;
  }

  bool get hasChoice => sources.any((s) => s.chosen);
}

/// The digits of a Jellyfin channel number ("1", "01", "1.0" -> 1).
int? lineupNumber(String? channelNumber) {
  final raw = (channelNumber ?? '').trim();
  if (raw.isEmpty) return null;
  final whole = raw.split(RegExp(r'[.,]')).first.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(whole);
}

/// Talks to "Ma TV". Every call fails quietly (null) so the player keeps
/// working when the seedbox is unreachable or the channel isn't one of its own.
class TvSourcesClient {
  final http.Client? _http;
  final TvSourcesServer? _fixed;

  TvSourcesClient({http.Client? httpClient, TvSourcesServer? server})
    : _http = httpClient,
      _fixed = server;

  static const _timeout = Duration(seconds: 6);

  TvSourcesServer? get server {
    if (_fixed != null) return _fixed;
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<SeerrPreferences>()) return null;
    final raw = getIt<SeerrPreferences>().vjodTvSourcesJson;
    if (raw.isEmpty) return null;
    try {
      return TvSourcesServer.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  bool get isConfigured => server != null;

  Future<TvChannelSources?> channel(int number) async {
    final s = server;
    if (s == null) return null;
    try {
      final uri = s.endpoint('/tv/api/channel', {'num': '$number'});
      final r = await (_http?.get(uri) ?? http.get(uri)).timeout(_timeout);
      if (r.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(r.bodyBytes));
      return json is Map ? TvChannelSources.fromJson(Map<String, dynamic>.from(json)) : null;
    } catch (_) {
      return null;
    }
  }

  /// Picks [sourceKey] for the channel (null goes back to automatic). A
  /// [sticky] choice stays until changed; otherwise it lasts a few hours.
  Future<TvChannelSources?> prefer(
    String channelId,
    String? sourceKey, {
    bool sticky = false,
  }) async {
    final s = server;
    if (s == null) return null;
    try {
      final uri = s.endpoint('/tv/api/prefer');
      final body = jsonEncode({'id': channelId, 'src': sourceKey ?? '', 'sticky': sticky});
      const headers = {'Content-Type': 'application/json'};
      final r = await (_http?.post(uri, headers: headers, body: body) ??
              http.post(uri, headers: headers, body: body))
          .timeout(_timeout);
      if (r.statusCode != 200) return null;
      final json = jsonDecode(utf8.decode(r.bodyBytes));
      return json is Map ? TvChannelSources.fromJson(Map<String, dynamic>.from(json)) : null;
    } catch (_) {
      return null;
    }
  }
}

/// Saves the server read from Jellyfin or pasted by hand. Returns whether it
/// changed.
Future<bool> saveTvSourcesServer(TvSourcesServer server) async {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<SeerrPreferences>()) return false;
  final prefs = getIt<SeerrPreferences>();
  final json = jsonEncode(server.toJson());
  if (prefs.vjodTvSourcesJson == json) return false;
  await prefs.setVjodTvSourcesJson(json);
  return true;
}
