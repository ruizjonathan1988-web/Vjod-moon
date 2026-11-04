// VJOD 4.18: le replay des chaînes. Le catalogue vient de Ma TV, la vidéo
// est demandée par l'appareil à la chaîne ; une vidéo chiffrée part dans
// l'appli de la chaîne. Les tuiles de l'accueil gardent leur ordre de la
// semaine, les épinglées en tête.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moonfin/data/services/vjod/iptv_progress.dart';
import 'package:moonfin/data/services/vjod/ma_tv_replay.dart';
import 'package:moonfin/data/services/vjod/tv_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _server = TvSourcesServer(url: 'https://seedbox.example.com/iptv', key: 'K');

const _arteItem = ReplayItem(id: 'a1', kind: 'arte', chan: 'arte', show: 'Le dessous des cartes');
const _ftvItem = ReplayItem(id: 'f1', kind: 'ftv', chan: 'france-2', show: 'Envoyé spécial');

ReplayChannel _c(String id) => ReplayChannel(chan: id, name: id, count: 3);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('l’accueil du replay se lit', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/iptv/tv/api/replay/home');
      expect(req.url.queryParameters['k'], 'K');
      return http.Response(
        jsonEncode({
          'mine': [
            {'id': 'x', 'kind': 'ftv', 'chan': 'france-2', 'show': 'Cash Investigation', 'aired': 1700000000, 'followed': true},
          ],
          'mine_new': 1,
          'chans': [
            {'chan': 'france-2', 'name': 'France 2', 'new': 1, 'count': 12},
            {'chan': 'arte', 'name': 'Arte', 'new': 0, 'count': 4},
          ],
          'featured': [],
        }),
        200,
      );
    });
    final home = await MaTvReplay(httpClient: client, server: _server).home();
    expect(home, isNotNull);
    expect(home!.mineNew, 1);
    expect(home.mine.single.show, 'Cash Investigation');
    expect(home.mine.single.followed, isTrue);
    expect(home.channels.map((c) => c.name), ['France 2', 'Arte']);
    expect(home.channels.first.fresh, 1);
    expect(home.isEmpty, isFalse);
  });

  test('Ma TV trop ancien : pas de replay', () async {
    final client = MockClient((_) async => http.Response('not found', 404));
    expect(await MaTvReplay(httpClient: client, server: _server).home(), isNull);
  });

  test('Arte : la version française d’abord', () async {
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/tv/api/replay/item')) {
        return http.Response(jsonEncode({'ref': '111-000-A'}), 200);
      }
      expect(req.url.toString(), 'https://api.arte.tv/api/player/v2/config/fr/111-000-A');
      return http.Response(
        jsonEncode({
          'data': {
            'attributes': {
              'streams': [
                {'url': 'https://arte/vo.m3u8', 'versions': [{'shortLabel': 'VO'}]},
                {'url': 'https://arte/vostf.m3u8', 'versions': [{'shortLabel': 'VOSTF'}]},
                {'url': 'https://arte/vf.m3u8', 'versions': [{'shortLabel': 'VF'}]},
              ],
            },
          },
        }),
        200,
      );
    });
    final play = await MaTvReplay(httpClient: client, server: _server).playback(_arteItem);
    expect(play.inVjod, isTrue);
    expect(play.url, 'https://arte/vf.m3u8');
  });

  test('France Télévisions : adresse signée, et chiffré → appli de la chaîne', () async {
    var drm = false;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/tv/api/replay/item')) return http.Response(jsonEncode({'ref': 'SI-1'}), 200);
      if (req.url.host == 'k7.ftven.fr') {
        expect(req.url.path, '/videos/SI-1');
        return http.Response(jsonEncode({'video': {'url': 'https://ftv/master.m3u8', 'drm': drm}}), 200);
      }
      if (req.url.host == 'hdfauth.ftven.fr') {
        expect(req.url.queryParameters['url'], 'https://ftv/master.m3u8');
        return http.Response(jsonEncode({'url': 'https://ftv/master.m3u8?hdnea=signed'}), 200);
      }
      throw StateError('${req.url}');
    });
    final r = MaTvReplay(httpClient: client, server: _server);
    final ok = await r.playback(_ftvItem);
    expect(ok.url, 'https://ftv/master.m3u8?hdnea=signed');
    drm = true;
    final locked = await r.playback(_ftvItem);
    expect(locked.inVjod, isFalse);
    expect(locked.reason, 'chiffré');
  });

  test('une chaîne qui ne répond pas : l’appli de la chaîne', () async {
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/tv/api/replay/item')) return http.Response(jsonEncode({'ref': 'SI-1'}), 200);
      return http.Response('forbidden', 403);
    });
    final play = await MaTvReplay(httpClient: client, server: _server).playback(_ftvItem);
    expect(play.inVjod, isFalse);
  });

  test('ordre des tuiles : épinglées, puis la semaine, puis les nouvelles', () {
    final chans = [_c('arte'), _c('france-2'), _c('france-3'), _c('france-5')];
    final order = ReplayOrder.rank(chans, {'france-3': 5, 'arte': 2});
    expect(order, ['france-3', 'arte', 'france-2', 'france-5']);
    final arranged = ReplayOrder.arrange(
      [...chans, _c('france-4')],
      frozen: order,
      pins: ['france-5'],
    );
    expect(arranged.map((c) => c.chan), ['france-5', 'france-3', 'arte', 'france-2', 'france-4']);
  });

  test('l’ordre ne bouge pas avant la semaine suivante', () async {
    final chans = [_c('arte'), _c('france-2')];
    final monday = DateTime(2026, 11, 2, 10);
    expect((await ReplayOrder.sort(chans, now: monday)).map((c) => c.chan), ['arte', 'france-2']);
    for (var i = 0; i < 3; i++) {
      await ReplayOrder.noteOpen('france-2');
    }
    final friday = DateTime(2026, 11, 6, 20);
    expect((await ReplayOrder.sort(chans, now: friday)).map((c) => c.chan), ['arte', 'france-2']);
    final nextMonday = DateTime(2026, 11, 9, 8);
    expect((await ReplayOrder.sort(chans, now: nextMonday)).map((c) => c.chan), ['france-2', 'arte']);
    await ReplayOrder.togglePin('arte');
    expect((await ReplayOrder.sort(chans, now: nextMonday)).first.chan, 'arte');
    expect(await ReplayOrder.isPinned('arte'), isTrue);
  });

  test('noms des chaînes rapprochés du guide', () {
    expect(replayNameKey('France 2 HD'), 'france2');
    expect(replayNameKey('FR: France 2'), 'france2');
    expect(replayNameKey('france-2'), 'france2');
    expect(replayNameKey('ARTE FHD'), 'arte');
  });

  test('page de chaîne : jour par jour, et l’épisode suivant', () {
    final page = ReplayChannelPage.fromJson({
      'chan': 'france-2',
      'name': 'France 2',
      'shows': [
        {
          'show': 'Envoyé spécial',
          'items': [
            {'id': 'b', 'show': 'Envoyé spécial', 'aired': DateTime(2026, 10, 29, 21).millisecondsSinceEpoch ~/ 1000},
            {'id': 'a', 'show': 'Envoyé spécial', 'aired': DateTime(2026, 10, 22, 21).millisecondsSinceEpoch ~/ 1000, 'new': true},
          ],
        },
      ],
      'days': [
        {'day': '2026-11-02', 'items': []},
        {'day': '2026-11-01', 'items': []},
        {'day': '2026-10-29', 'items': [{'id': 'b', 'show': 'Envoyé spécial'}]},
        {'day': 'n’importe', 'items': []},
      ],
    });
    expect(page.days, hasLength(3));
    final now = DateTime(2026, 11, 2, 20);
    expect(page.days.map((d) => d.label(now)), ['Aujourd’hui', 'Hier', 'Jeu. 29 oct.']);
    final items = page.shows.single.items;
    expect(items.last.isNew, isTrue);
    expect(nextEpisode(items.last, items)?.id, 'b');
    expect(nextEpisode(items.first, items), isNull);
  });

  test('vu en direct : proposé à suivre', () {
    final home = ReplayHome.fromJson({
      'chans': [],
      'suggest': [
        {'id': 'x', 'kind': 'ftv', 'chan': 'france-2', 'show': 'Cash Investigation', 'live_at': 1762200000},
      ],
    });
    expect(home.suggest.single.show, 'Cash Investigation');
    expect(home.suggest.single.liveAt, DateTime.fromMillisecondsSinceEpoch(1762200000 * 1000));
  });

  test('un replay commencé garde sa place comme un film', () {
    const w = IptvWatch(kind: 'replay', id: 'ftv-0123456789', name: 'Envoyé spécial', poster: 'https://img/x.jpg');
    final back = IptvWatch.fromQuery(w.toQuery())!;
    expect(back.isReplay, isTrue);
    expect(back.id, 'ftv-0123456789');
    final p = IptvProgress.fromJson({'kind': 'replay', 'id': 'ftv-0123456789', 'name': 'Envoyé spécial', 'pos': 600, 'dur': 3600})!;
    expect(p.kind, 'replay');
    expect(p.resumable, isTrue);
  });

  test('TF1, M6… : un épisode du rattrapage IPTV', () {
    final e = ReplayItem.fromJson({'id': 'iptv-1', 'kind': 'iptv', 'chan': 'tf1', 'show': 'Koh-Lanta', 'aired': 1762200000, 'dur': 5400, 'src': 'tf1'});
    expect(e.isIptv, isTrue);
    expect(_arteItem.isIptv, isFalse);
  });
}
