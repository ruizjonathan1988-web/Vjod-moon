// Deleting a film, an episode, a season or a whole series from the server.
// Ma TV, on the seedbox, does the whole job: Jellyfin deletes the files (only
// for a profile Jellyfin allows to), Sonarr / Radarr stop watching what was
// deleted so it doesn't come back, and the torrent that still shared it is
// removed so the space is really freed. Without Ma TV, Jellyfin alone deletes
// the files.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ma_tv.dart';

class MediaDeleteResult {
  /// Null when it worked, else what went wrong (nothing was deleted then).
  final String? error;

  /// Bytes given back on the seedbox, when Ma TV knows.
  final int freed;

  /// Things worth knowing ("Sonarr ne le surveille plus", torrent kept…).
  final List<String> notes;

  /// Only Jellyfin deleted it: Sonarr / Radarr and the torrent weren't told.
  final bool jellyfinOnly;

  const MediaDeleteResult({this.error, this.freed = 0, this.notes = const [], this.jellyfinOnly = false});

  bool get ok => error == null;

  /// One line for the viewer.
  String summary(String name) {
    if (!ok) return error!;
    if (jellyfinOnly) return '« $name » supprimé (Ma TV absent : Sonarr / Radarr et le torrent non prévenus)';
    final gb = freed / (1 << 30);
    final space = freed <= 0
        ? ''
        : gb >= 1
        ? ' · ${gb.toStringAsFixed(1).replaceAll('.', ',')} Go libérés'
        : ' · ${(freed / (1 << 20)).round()} Mo libérés';
    return '« $name » supprimé du serveur$space';
  }
}

class MediaDeleter {
  MediaDeleter._();

  static const _timeout = Duration(seconds: 90);

  /// Deletes [itemId] for the profile whose Jellyfin token is [token].
  /// [jellyfinDelete] is the plain Jellyfin delete, used only when Ma TV
  /// isn't set up at all.
  static Future<MediaDeleteResult> delete({
    required String itemId,
    required String? token,
    required Future<void> Function() jellyfinDelete,
  }) async {
    final server = MaTvClient().server;
    if (server == null) {
      try {
        await jellyfinDelete();
        return const MediaDeleteResult(jellyfinOnly: true);
      } catch (e) {
        return MediaDeleteResult(error: "Jellyfin n'a pas pu le supprimer ($e)");
      }
    }
    if (token == null || token.isEmpty) {
      return const MediaDeleteResult(error: 'Profil non connecté, rien n’a été supprimé');
    }
    try {
      final r = await http
          .post(
            server.endpoint('/tv/api/media/delete'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'token': token, 'id': itemId}),
          )
          .timeout(_timeout);
      Object? j;
      try {
        j = jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {}
      if (r.statusCode != 200 || j is! Map) {
        final why = j is Map && j['error'] != null ? '${j['error']}' : 'Ma TV a répondu ${r.statusCode}';
        return MediaDeleteResult(error: '$why. Rien n’a été supprimé.');
      }
      return MediaDeleteResult(
        freed: j['freed'] is num ? (j['freed'] as num).toInt() : 0,
        notes: [for (final n in (j['notes'] is List ? j['notes'] as List : const [])) '$n'],
      );
    } on TimeoutException {
      return const MediaDeleteResult(
        error: 'Ma TV met du temps à répondre : la suppression continue peut-être, regarde dans un instant.',
      );
    } catch (_) {
      return const MediaDeleteResult(error: 'Ma TV ne répond pas. Rien n’a été supprimé, réessaie dans un instant.');
    }
  }
}
