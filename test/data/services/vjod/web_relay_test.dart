// VJOD 4.5: the web version (Safari on the iPad and iPhone) plays IPTV
// through Ma TV's relay. Only the plain decisions are tested here.
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/iptv_cast.dart';
import 'package:moonfin/data/services/vjod/web_iptv.dart';

void main() {
  group('quand passer par Ma TV', () {
    test('Safari : tout sauf le MP4', () {
      expect(webUsesRelayFirst(safari: true, extension: 'mkv'), isTrue);
      expect(webUsesRelayFirst(safari: true, extension: '.MKV'), isTrue);
      expect(webUsesRelayFirst(safari: true, extension: 'mp4'), isFalse);
      expect(webUsesRelayFirst(safari: true, extension: 'm4v'), isFalse);
    });

    test('autres navigateurs : le fichier d\'abord, sauf ce qu\'aucun ne lit', () {
      expect(webUsesRelayFirst(safari: false, extension: 'mkv'), isFalse);
      expect(webUsesRelayFirst(safari: false, extension: 'mp4'), isFalse);
      expect(webUsesRelayFirst(safari: false, extension: 'avi'), isTrue);
      expect(webUsesRelayFirst(safari: false, extension: 'ts'), isTrue);
    });
  });

  group('TV en direct', () {
    test('la chaîne et le profil, jamais la clé', () {
      final q = liveRelayQuery('https://hote.example.com/checker/tv/play/fr-tf1.ts?u=papy&k=SECRET')!;
      expect(q, {'kind': 'live', 'id': 'fr-tf1', 'u': 'papy'});
      expect(q.values, isNot(contains('SECRET')));
    });

    test('sans profil', () {
      expect(liveRelayQuery('https://hote.example.com/tv/play/tf1.ts?k=X'), {'kind': 'live', 'id': 'tf1'});
    });

    test('replay, retour en arrière ou film : rien', () {
      expect(liveRelayQuery('https://hote.example.com/tv/shift/tf1.ts?at=1'), isNull);
      expect(liveRelayQuery('https://hote.example.com/tv/replay/tf1.ts'), isNull);
      expect(liveRelayQuery('https://hote.example.com/tv/xc/movie/vjod/K/1.mkv'), isNull);
      expect(liveRelayQuery('pas une adresse'), isNull);
    });
  });

  group('arrêt de la préparation', () {
    test('index.m3u8 devient stop, au même endroit', () {
      expect(
        relayStopUri('https://hote.example.com/checker/tv/cast/abcDEF123_-xyz789012345/index.m3u8').toString(),
        'https://hote.example.com/checker/tv/cast/abcDEF123_-xyz789012345/stop',
      );
    });

    test('autre adresse : rien', () {
      expect(relayStopUri('https://hote.example.com/film.mp4'), isNull);
    });
  });

  group('reprise d\'un film', () {
    const r = IptvCastRequest(kind: 'movie', id: '12', extension: 'mkv');

    test('Ma TV prépare depuis 5 s avant l\'endroit quitté', () {
      expect(relayQuery(r, position: const Duration(minutes: 10))['start'], '595');
    });

    test('dans la première minute : depuis le début', () {
      expect(relayQuery(r, position: const Duration(seconds: 30)).containsKey('start'), isFalse);
    });
  });

  group('replay et enregistrements dans le navigateur (Ma TV 3.73)', () {
    test('un replay passe par le relais, avec son début, sa durée et ses capacités', () {
      final r = IptvCastRequest.fromPlayUrl(
        'https://tv.maison.example/checker/tv/replay/france5.ts?start=1794077143&dur=59&caps=h264%3Bmaxh%3D720&k=CLE',
      )!;
      expect(r.query, {'kind': 'replay', 'id': 'france5', 'ext': 'ts', 'at': '1794077143', 'dur': '59', 'caps': 'h264;maxh=720'});
    });

    test('un enregistrement aussi', () {
      final r = IptvCastRequest.fromPlayUrl('https://tv.maison.example/checker/tv/rec/e56d453c2072.ts?k=CLE')!;
      expect(r.query, {'kind': 'rec', 'id': 'e56d453c2072', 'ext': 'ts'});
    });

    test('un replay sans début ni durée : rien', () {
      expect(IptvCastRequest.fromPlayUrl('https://h.example.com/tv/replay/france5.ts'), isNull);
    });
  });
}
