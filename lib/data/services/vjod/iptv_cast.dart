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

  /// Shown instead of casting, in French. Null when [url] is set.
  final String? problem;

  const IptvCastSource(this.url, this.contentType) : problem = null;
  const IptvCastSource.impossible(String message)
    : url = '',
      contentType = '',
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

/// Reads Ma TV's answer to `/tv/api/cast`: `{"url": "...", "type": "..."}`.
IptvCastSource? castSourceFromMaTv(int status, String body) {
  if (status != 200) return null;
  try {
    final json = jsonDecode(body);
    if (json is! Map) return null;
    final url = json['url']?.toString() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) return null;
    final type = json['type']?.toString() ?? '';
    return IptvCastSource(url, type.isEmpty ? 'application/x-mpegURL' : type);
  } catch (_) {
    return null;
  }
}

/// Finds what to send to the Chromecast for [playUrl].
Future<IptvCastSource> resolveIptvCast(String playUrl, {http.Client? client}) async {
  final server = TvSourcesClient().server;
  final request = IptvCastRequest.fromPlayUrl(playUrl);
  final fromMaTv = server != null && request != null && playUrl.startsWith(server.url);
  if (!fromMaTv) return directCastSource(playUrl, maTvTooOld: false);
  try {
    final uri = server.endpoint('/tv/api/cast', request.query);
    final r = await (client?.get(uri) ?? http.get(uri)).timeout(const Duration(seconds: 30));
    // An older Ma TV doesn't know the route.
    if (r.statusCode == 404) return directCastSource(playUrl, maTvTooOld: true);
    return castSourceFromMaTv(r.statusCode, utf8.decode(r.bodyBytes)) ??
        const IptvCastSource.impossible(iptvCastMaTvFailed);
  } catch (_) {
    return const IptvCastSource.impossible(iptvCastMaTvFailed);
  }
}
