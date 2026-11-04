// VJOD 4.25 : garder une émission du replay, par les trackers (Prowlarr via
// Ma TV 3.67). Rien ne part sans un appui.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moonfin/data/services/vjod/ma_tv_replay.dart';
import 'package:moonfin/data/services/vjod/replay_keep.dart';
import 'package:moonfin/data/services/vjod/tv_sources.dart';

const _server = TvSourcesServer(url: 'https://seedbox.example.com/iptv', key: 'K');

void main() {
  test('la recherche cite l’épisode quand il est connu', () {
    expect(ReplayKeep.queryFor(const ReplayItem(id: 'a', kind: 'iptv', chan: 'tf1', show: 'Koh-Lanta', season: 25, episode: 3)), 'Koh-Lanta S25E03');
    expect(ReplayKeep.queryFor(const ReplayItem(id: 'b', kind: 'iptv', chan: 'm6', show: 'Capital')), 'Capital');
  });

  test('résultats lus, puis envoi d’un seul', () async {
    final client = MockClient((req) async {
      if (req.method == 'GET') {
        expect(req.url.path, '/iptv/tv/api/fetch/search');
        expect(req.url.queryParameters['q'], 'Capital');
        return http.Response(
          jsonEncode({
            'results': [
              {'id': 'r1', 'title': 'Capital.2026.11.02.FRENCH.1080p', 'size': 2684354560, 'seeders': 40, 'indexer': 'Tracker A', 'age': 1},
            ],
            'may_grab': true,
          }),
          200,
        );
      }
      expect(jsonDecode(req.body), {'id': 'r1', 'show': 'Capital'});
      return http.Response(jsonEncode({'ok': true, 'via': 'library'}), 200);
    });
    final found = await ReplayKeep.search('Capital', client: client, server: _server);
    expect(found.mayGrab, isTrue);
    expect(found.results.single.detail, '2,5 Go · 40 sources · Tracker A · il y a 1 j');
    expect(await ReplayKeep.grab(found.results.single, show: 'Capital', client: client, server: _server), contains('bibliothèque Séries'));
  });

  test('Ma TV trop ancienne, ou profil non administrateur', () async {
    final old = MockClient((_) async => http.Response('not found', 404));
    expect((await ReplayKeep.search('Capital', client: old, server: _server)).error, contains('3.67'));
    final refused = MockClient((_) async => http.Response(jsonEncode({'error': 'réservé aux administrateurs de Jellyfin'}), 403));
    expect(await ReplayKeep.grab(const TrackerRelease(id: 'r1', title: 'x'), client: refused, server: _server), contains('administrateurs'));
  });

  test('garder les prochains épisodes', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/iptv/tv/api/replay/keep');
      final b = jsonDecode(req.body) as Map;
      expect(b['show'], 'Ici tout commence');
      return b['keep'] == true
          ? http.Response(jsonEncode({'keep': ['ici tout commence']}), 200)
          : http.Response(jsonEncode({'error': 'réservé aux administrateurs de Jellyfin'}), 403);
    });
    final r = MaTvReplay(httpClient: client, server: _server);
    expect(await r.setKeep('Ici tout commence', true), isNull);
    expect(await r.setKeep('Ici tout commence', false), contains('administrateurs'));
    expect(ReplayItem.fromJson({'id': 'x', 'kind': 'iptv', 'chan': 'tf1', 'show': 'Ici tout commence', 'kept': true}).kept, isTrue);
  });
}
