import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/deep_link_service.dart';

void main() {
  group('routeForDeepLink', () {
    test('returns null for non-moonfin schemes', () {
      expect(
        DeepLinkService.routeForDeepLink(
          Uri.parse('https://example.com/?id=abc'),
        ),
        isNull,
      );
    });

    test('returns null without an id', () {
      expect(
        DeepLinkService.routeForDeepLink(Uri.parse('moonfin://play?serverId=s1')),
        isNull,
      );
    });

    test('Aura : un titre TMDB ouvre sa fiche Regarder / Demander', () {
      expect(
        DeepLinkService.routeForDeepLink(Uri.parse('moonfin://tmdb?id=550&type=movie')),
        '/seerr/media/550?mediaType=movie',
      );
      expect(
        DeepLinkService.routeForDeepLink(Uri.parse('moonfin://tmdb?id=1396&type=tv&title=Breaking%20Bad')),
        '/seerr/media/1396?mediaType=tv&title=Breaking+Bad',
      );
      // Sans type, c'est un film.
      expect(
        DeepLinkService.routeForDeepLink(Uri.parse('moonfin://tmdb?id=550')),
        '/seerr/media/550?mediaType=movie',
      );
    });

    test('Aura : un identifiant TMDB absent ou bizarre est ignoré', () {
      expect(DeepLinkService.routeForDeepLink(Uri.parse('moonfin://tmdb')), isNull);
      expect(DeepLinkService.routeForDeepLink(Uri.parse('moonfin://tmdb?id=abc')), isNull);
      expect(DeepLinkService.routeForDeepLink(Uri.parse('moonfin://tmdb?id=../admin')), isNull);
    });

    test('routes item host without autoPlay', () {
      expect(
        DeepLinkService.routeForDeepLink(Uri.parse('moonfin://item?id=abc123')),
        '/item/abc123',
      );
    });

    test('routes play host with autoPlay', () {
      expect(
        DeepLinkService.routeForDeepLink(Uri.parse('moonfin://play?id=abc123')),
        '/item/abc123?autoPlay=true',
      );
    });

    test('forwards serverId', () {
      expect(
        DeepLinkService.routeForDeepLink(
          Uri.parse('moonfin://play?id=abc123&serverId=srv-1'),
        ),
        '/item/abc123?serverId=srv-1&autoPlay=true',
      );
    });

    test('forwards userId alongside serverId and autoPlay', () {
      expect(
        DeepLinkService.routeForDeepLink(
          Uri.parse('moonfin://play?id=abc123&serverId=srv-1&userId=user-1'),
        ),
        '/item/abc123?serverId=srv-1&userId=user-1&autoPlay=true',
      );
    });

    test('forwards userId alone on item host', () {
      expect(
        DeepLinkService.routeForDeepLink(
          Uri.parse('moonfin://item?id=abc123&userId=user-1'),
        ),
        '/item/abc123?userId=user-1',
      );
    });

    test('ignores empty serverId and userId', () {
      expect(
        DeepLinkService.routeForDeepLink(
          Uri.parse('moonfin://play?id=abc123&serverId=&userId='),
        ),
        '/item/abc123?autoPlay=true',
      );
    });
  });
}
