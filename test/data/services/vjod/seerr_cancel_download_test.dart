// VJOD 5.16: cancelling a Seerr request stops the download through Ma TV,
// unless someone else still asks for it.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/services/vjod/seerr_cancel_download.dart';
import 'package:moonfin/data/services/vjod/tv_sources.dart';

SeerrRequest req(int id, {int status = SeerrRequest.statusApproved, List<int>? seasons, bool is4k = false}) =>
    SeerrRequest(
      id: id,
      status: status,
      type: seasons == null ? 'movie' : 'tv',
      is4k: is4k,
      seasons: seasons == null
          ? null
          : [for (final s in seasons) SeerrSeasonRequest(id: id * 10 + s, seasonNumber: s, status: 2)],
    );

void main() {
  test('film : arrêté, sauf si quelqu\'un d\'autre le demande encore', () {
    expect(SeerrCancelDownload.forCancel(all: [req(1)], cancelled: {1}, isMovie: true, tmdbId: 42),
        {'type': 'movie', 'tmdb': 42});
    expect(SeerrCancelDownload.forCancel(all: [req(1), req(2)], cancelled: {1}, isMovie: true, tmdbId: 42), isNull);
    // une demande refusée ou une 4K ne retient pas le téléchargement normal
    expect(
      SeerrCancelDownload.forCancel(
          all: [req(1), req(2, status: SeerrRequest.statusDeclined), req(3, is4k: true)],
          cancelled: {1}, isMovie: true, tmdbId: 42),
      isNotNull,
    );
  });

  test('série : seulement les saisons que plus personne ne demande', () {
    final p = SeerrCancelDownload.forCancel(
        all: [req(1, seasons: [1, 2, 3]), req(2, seasons: [3])], cancelled: {1}, isMovie: false, tmdbId: 7, tvdbId: 70);
    expect(p, {'type': 'tv', 'tmdb': 7, 'tvdb': 70, 'seasons': [1, 2]});
    expect(
      SeerrCancelDownload.forCancel(all: [req(1, seasons: [3]), req(2, seasons: [3])], cancelled: {1}, isMovie: false, tmdbId: 7),
      isNull,
    );
    expect(
      SeerrCancelDownload.forCancel(all: [req(1, seasons: [1]), req(2, seasons: [])], cancelled: {1}, isMovie: false, tmdbId: 7),
      isNull,
      reason: 'une autre demande de toute la série garde tout',
    );
  });

  test('l\'appel à Ma TV, sans planter quand Ma TV est trop ancien', () async {
    SeerrCancelDownload.serverOf = () => TvSourcesServer.fromJson({'url': 'https://seedbox.example.com/iptv', 'key': 'K'});
    Map<String, dynamic>? sent;
    SeerrCancelDownload.httpClient = MockClient((r) async {
      expect(r.url.path, '/iptv/tv/api/seerr/cancel');
      expect(r.url.queryParameters['k'], 'K');
      sent = jsonDecode(r.body) as Map<String, dynamic>;
      return http.Response('{"downloads":1,"removed":["Dune retiré de Radarr"],"kept":[]}', 200);
    });
    expect(await SeerrCancelDownload.stop({'type': 'movie', 'tmdb': 42}), isTrue,
        reason: '${SeerrCancelDownload.lastError}');
    expect(sent, {'type': 'movie', 'tmdb': 42});
    SeerrCancelDownload.httpClient = MockClient((r) async => http.Response('not found', 404));
    expect(await SeerrCancelDownload.stop({'type': 'movie', 'tmdb': 42}), isFalse);
    SeerrCancelDownload.serverOf = () => null;
    expect(await SeerrCancelDownload.stop({'type': 'movie', 'tmdb': 42}), isFalse);
  });
}
