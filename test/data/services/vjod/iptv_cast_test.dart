import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/iptv_cast.dart';

void main() {
  group('adresse de lecture', () {
    test('film de Ma TV avec qualité et fichier choisi', () {
      final r = IptvCastRequest.fromPlayUrl(
        'https://hote.example.com/iptv-checker/tv/xc/movie/vjod/CLE/123.mkv?q=1080&src=2',
      )!;
      expect(r.kind, 'movie');
      expect(r.id, '123');
      expect(r.extension, 'mkv');
      expect(r.query, {'kind': 'movie', 'id': '123', 'ext': 'mkv', 'q': '1080', 'src': '2'});
    });

    test('épisode', () {
      final r = IptvCastRequest.fromPlayUrl('https://hote.example.com/tv/xc/series/vjod/CLE/9001.mp4')!;
      expect(r.kind, 'series');
      expect(r.id, '9001');
      expect(r.query.containsKey('q'), isFalse);
    });

    test('la clé de Ma TV n\'est jamais renvoyée dans la demande', () {
      final r = IptvCastRequest.fromPlayUrl('https://hote.example.com/tv/xc/movie/vjod/SECRET/1.mkv')!;
      expect(r.query.values, isNot(contains('SECRET')));
    });

    test('autre chose : rien', () {
      expect(IptvCastRequest.fromPlayUrl('https://hote.example.com/tv/play/12.ts'), isNull);
      expect(IptvCastRequest.fromPlayUrl('pas une adresse'), isNull);
    });
  });

  group('envoi direct', () {
    test('un MP4 part tel quel', () {
      final s = directCastSource('https://h/tv/xc/movie/u/p/1.mp4', maTvTooOld: false);
      expect(s.ok, isTrue);
      expect(s.contentType, 'video/mp4');
    });

    test('un MKV : message clair, selon la version de Ma TV', () {
      expect(directCastSource('https://h/1.mkv', maTvTooOld: true).problem, iptvCastUpdateMaTv);
      expect(directCastSource('https://h/1.mkv', maTvTooOld: false).problem, iptvCastUnsupported);
    });
  });

  group('réponse de Ma TV', () {
    test('version préparée en HLS', () {
      final s = castSourceFromMaTv(200, '{"url":"https://h/tv/cast/abc/index.m3u8","type":"application/x-mpegURL"}')!;
      expect(s.ok, isTrue);
      expect(s.url, 'https://h/tv/cast/abc/index.m3u8');
    });

    test('type absent : HLS par défaut', () {
      expect(castSourceFromMaTv(200, '{"url":"https://h/x.m3u8"}')!.contentType, 'application/x-mpegURL');
    });

    test('adresse en http, erreur ou réponse cassée : refusée', () {
      expect(castSourceFromMaTv(200, '{"url":"http://h/x.m3u8"}'), isNull);
      expect(castSourceFromMaTv(503, '{"url":"https://h/x.m3u8"}'), isNull);
      expect(castSourceFromMaTv(200, 'pas du json'), isNull);
    });
  });

  group('reprise et messages de Ma TV 3.53', () {
    test('flux préparé depuis le point de reprise : la Chromecast part de zéro', () {
      final s = castSourceFromMaTv(200, '{"url":"https://h/tv/cast/abc/index.m3u8","offset":1195.0}')!;
      expect(s.offset, const Duration(seconds: 1195));
      expect(castStartTicks(s, const Duration(minutes: 20)), 0);
    });

    test('fichier envoyé tel quel : la Chromecast reprend elle-même', () {
      final s = directCastSource('https://h/1.mp4', maTvTooOld: false);
      expect(castStartTicks(s, const Duration(seconds: 90)), 900000000);
    });

    test('Ma TV refuse : son message en français est montré', () {
      final s = castSourceFromMaTv(503, '{"error":"ce fichier doit être converti et Ma TV en convertit déjà un"}')!;
      expect(s.ok, isFalse);
      expect(s.problem, 'Ma TV : Ce fichier doit être converti et Ma TV en convertit déjà un.');
    });
  });
}
