// Casting an IPTV film or episode to a Google Cast device (an old
// Chromecast without a remote, for instance).
//
// A Chromecast fetches the video itself and only plays a few formats (H.264
// with AAC sound, in MP4 or HLS; a 2nd-generation one tops out at 1080p
// 30 fps). So:
// - with Ma TV, Ma TV is asked for a version the Chromecast plays
//   (`/tv/api/cast`, Ma TV 3.53 and up): the same file when it already fits,
//   otherwise an HLS stream it prepares on the fly, behind a short-lived token
//   rather than Ma TV's key;
// - the same relay serves the web version: Safari (iPad, iPhone) plays none
//   of the IPTV files but plays this HLS, live channels included (3.54);
// - an older Ma TV, or a provider read directly: only an MP4 file is sent as
//   it is; anything else gets a clear message instead of a black screen.
//
// The decisions are plain functions, tested without a device.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'tv_sources.dart';
import 'web_iptv.dart' show extensionOfUrl;

/// What the player hands over: the Xtream play address split into its parts
/// (`…/tv/xc/movie/vjod/KEY/123.mkv?q=1080&src=2`).
class IptvCastRequest {
  final String kind; // 'movie' or 'series'
  final String id;
  final String extension;
  final String quality;
  final String source;

  const IptvCastRequest({
    required this.kind,
    required this.id,
    required this.extension,
    this.quality = '',
    this.source = '',
  });

  static IptvCastRequest? fromPlayUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    // kind / user / password / file, at the end of the address
    if (parts.length < 4) return null;
    final kind = parts[parts.length - 4];
    if (kind != 'movie' && kind != 'series') return null;
    final file = parts.last;
    final dot = file.lastIndexOf('.');
    final id = dot < 0 ? file : file.substring(0, dot);
    if (id.isEmpty) return null;
    return IptvCastRequest(
      kind: kind,
      id: id,
      extension: extensionOfUrl(url),
      quality: uri.queryParameters['q'] ?? '',
      source: uri.queryParameters['src'] ?? '',
    );
  }

  Map<String, String> get query => {
    'kind': kind,
    'id': id,
    if (extension.isNotEmpty) 'ext': extension,
    if (quality.isNotEmpty) 'q': quality,
    if (source.isNotEmpty) 'src': source,
  };
}

/// Where the Chromecast reads from, or why it can't.
class IptvCastSource {
  final String url;
  final String contentType;

  /// Where the stream already starts (Ma TV prepared it from the resume
  /// point), so the Chromecast is told to start at its beginning.
  final Duration offset;

  /// Shown instead of casting, in French. Null when [url] is set.
  final String? problem;

  const IptvCastSource(this.url, this.contentType, {this.offset = Duration.zero}) : problem = null;
  const IptvCastSource.impossible(String message)
    : url = '',
      contentType = '',
      offset = Duration.zero,
      problem = message;

  bool get ok => problem == null && url.isNotEmpty;
}

const iptvCastUpdateMaTv =
    'Ce fichier ne peut pas être casté tel quel (format non lu par la Chromecast). '
    'Mets Ma TV à jour (version 3.53 ou plus) pour qu\'elle prépare une version compatible.';

const iptvCastUnsupported =
    'Ce fichier ne peut pas être casté : la Chromecast ne lit que les vidéos MP4 en H.264. '
    'Choisis une autre version avec « Choisir le fichier ».';

const iptvCastMaTvFailed =
    'Ma TV n\'a pas pu préparer de version pour la Chromecast. Réessaie dans un moment.';

/// Sending the file as it is: only an MP4 has a chance on every Chromecast.
IptvCastSource directCastSource(String playUrl, {required bool maTvTooOld}) {
  if (extensionOfUrl(playUrl) == 'mp4') return IptvCastSource(playUrl, 'video/mp4');
  return IptvCastSource.impossible(maTvTooOld ? iptvCastUpdateMaTv : iptvCastUnsupported);
}

/// Reads Ma TV's answer to `/tv/api/cast`: `{"url": "...", "type": "...",
/// "offset": seconds}`, or `{"error": "..."}` (a French sentence) when it
/// can't, shown as it is.
IptvCastSource? castSourceFromMaTv(int status, String body) {
  try {
    final json = jsonDecode(body);
    if (json is! Map) return null;
    final error = json['error']?.toString() ?? '';
    if (status != 200) {
      if (error.isEmpty) return null;
      return IptvCastSource.impossible('Ma TV : ${error[0].toUpperCase()}${error.substring(1)}.');
    }
    final url = json['url']?.toString() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) return null;
    final type = json['type']?.toString() ?? '';
    final offset = json['offset'] is num ? (json['offset'] as num).toDouble() : 0.0;
    return IptvCastSource(
      url,
      type.isEmpty ? 'application/x-mpegURL' : type,
      offset: Duration(milliseconds: (offset * 1000).round()),
    );
  } catch (_) {
    return null;
  }
}

/// The Chromecast's start, in Google Cast ticks: Ma TV's stream already
/// starts at the resume point, a file sent as it is starts at zero.
int castStartTicks(IptvCastSource source, Duration position) =>
    source.offset > Duration.zero ? 0 : position.inMicroseconds * 10;

/// Asks Ma TV's relay (`/tv/api/cast`) for an HLS version of [query]: a film
/// or an episode (Ma TV 3.53 and up), a live channel (3.54 and up). Shared by
/// the Chromecast and the web version (Safari plays none of the IPTV files
/// but plays this). Null when Ma TV doesn't know the route (too old).
Future<IptvCastSource?> askMaTvRelay(Map<String, String> query, {http.Client? client}) async {
  final server = TvSourcesClient().server;
  if (server == null) return const IptvCastSource.impossible(iptvCastMaTvFailed);
  try {
    final uri = server.endpoint('/tv/api/cast', query);
    // Ma TV looks at the file (a few seconds, up to 45 when the source is slow).
    final r = await (client?.get(uri) ?? http.get(uri)).timeout(const Duration(seconds: 60));
    if (r.statusCode == 404) return null;
    return castSourceFromMaTv(r.statusCode, utf8.decode(r.bodyBytes)) ??
        const IptvCastSource.impossible(iptvCastMaTvFailed);
  } catch (_) {
    return const IptvCastSource.impossible(iptvCastMaTvFailed);
  }
}

/// Finds what to send to the Chromecast for [playUrl].
Future<IptvCastSource> resolveIptvCast(
  String playUrl, {
  String title = '',
  Duration position = Duration.zero,
  http.Client? client,
}) async {
  final server = TvSourcesClient().server;
  final request = IptvCastRequest.fromPlayUrl(playUrl);
  final fromMaTv = server != null && request != null && playUrl.startsWith(server.url);
  if (!fromMaTv) return directCastSource(playUrl, maTvTooOld: false);
  final source = await askMaTvRelay(relayQuery(request, position: position, title: title), client: client);
  // An older Ma TV doesn't know the route.
  return source ?? directCastSource(playUrl, maTvTooOld: true);
}

/// The relay's parameters for a film or an episode: Ma TV prepares the
/// stream from where it was left (5 s before), when past the first minute.
Map<String, String> relayQuery(IptvCastRequest request, {Duration position = Duration.zero, String title = ''}) => {
  ...request.query,
  if (position > const Duration(minutes: 1)) 'start': '${position.inSeconds - 5}',
  if (title.isNotEmpty) 'title': title,
};

// ------------------------------------------------------------------ web version
const webRelayUpdateMaTv =
    'Pour lire ceci dans le navigateur, Ma TV doit être à jour (version 3.54 ou plus). '
    'En attendant, regarde-le sur l\'appli.';

const webRelayNotMaTv =
    'Ce fichier ne se lit pas dans le navigateur. Regarde-le sur l\'appli.';

/// The relay's parameters for a live channel, from Ma TV's live address
/// (`…/tv/play/<channel>.ts?u=…&k=…`); null for any other address.
Map<String, String>? liveRelayQuery(String playUrl) {
  final uri = Uri.tryParse(playUrl);
  if (uri == null) return null;
  final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  if (parts.length < 3 || parts[parts.length - 3] != 'tv' || parts[parts.length - 2] != 'play') return null;
  final file = parts.last;
  final id = file.endsWith('.ts') ? file.substring(0, file.length - 3) : file;
  if (id.isEmpty) return null;
  final user = uri.queryParameters['u'] ?? '';
  return {'kind': 'live', 'id': id, if (user.isNotEmpty) 'u': user};
}

/// The address that stops Ma TV's preparation behind [hlsUrl]
/// (`…/tv/cast/<token>/index.m3u8` → `…/tv/cast/<token>/stop`), or null.
Uri? relayStopUri(String hlsUrl) {
  final uri = Uri.tryParse(hlsUrl);
  if (uri == null || !uri.path.contains('/tv/cast/')) return null;
  final parts = List.of(uri.pathSegments);
  if (parts.isEmpty) return null;
  parts[parts.length - 1] = 'stop';
  return uri.replace(pathSegments: parts, query: null);
}

/// Tells Ma TV it can stop preparing [hlsUrl] now (player closed, other
/// channel, jump in the film), instead of a few minutes later. Never fails.
Future<void> stopMaTvRelay(String? hlsUrl, {http.Client? client}) async {
  final uri = hlsUrl == null ? null : relayStopUri(hlsUrl);
  if (uri == null) return;
  try {
    await (client?.get(uri) ?? http.get(uri)).timeout(const Duration(seconds: 5));
  } catch (_) {}
}

/// The web version's film or episode through Ma TV's relay, from [playUrl]
/// (Ma TV's file address) and where to start.
Future<IptvCastSource> resolveWebRelay(String playUrl, {Duration position = Duration.zero}) async {
  final server = TvSourcesClient().server;
  final request = IptvCastRequest.fromPlayUrl(playUrl);
  if (server == null || request == null || !playUrl.startsWith(server.url)) {
    return const IptvCastSource.impossible(webRelayNotMaTv);
  }
  return await askMaTvRelay(relayQuery(request, position: position)) ??
      const IptvCastSource.impossible(webRelayUpdateMaTv);
}

/// The web version's live channel through Ma TV's relay.
Future<IptvCastSource> resolveWebLive(String liveUrl) async {
  final query = liveRelayQuery(liveUrl);
  if (query == null) return const IptvCastSource.impossible(webRelayNotMaTv);
  return await askMaTvRelay(query) ?? const IptvCastSource.impossible(webRelayUpdateMaTv);
}
