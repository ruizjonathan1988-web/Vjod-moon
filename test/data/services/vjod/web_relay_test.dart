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
      final q = liveRelayQuery('https://hote.example.com/iptv-checker/tv/play/fr-tf1.ts?u=papy&k=SECRET')!;
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
        relayStopUri('https://hote.example.com/iptv-checker/tv/cast/abcDEF123_-xyz789012345/index.m3u8').toString(),
        'https://hote.example.com/iptv-checker/tv/cast/abcDEF123_-xyz789012345/stop',
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
}
