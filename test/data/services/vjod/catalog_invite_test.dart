import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/deep_link_service.dart';
import 'package:moonfin/data/services/vjod/catalog_invite.dart';

void main() {
  const url = 'https://ava88:p%40ss@zen.usbx.me/vjod/catalog.json.gz';

  group('catalogue invitation', () {
    test('what is built is read back whole, login included', () {
      expect(parseCatalogInvite(buildCatalogInvite(url)), url);
    });

    test('found inside a message', () {
      final text = 'Salut ! Partage ça vers VJOD : ${buildCatalogInvite(url)} (à garder pour toi)';
      expect(parseCatalogInvite(text), url);
    });

    test('the bare address of the file counts', () {
      expect(parseCatalogInvite('Voilà $url.'), url);
    });

    test('anything else is none', () {
      expect(parseCatalogInvite(null), isNull);
      expect(parseCatalogInvite(''), isNull);
      expect(parseCatalogInvite('https://exemple.com/liste.m3u'), isNull);
      expect(parseCatalogInvite('moonfin://vjodcatalog?u=ftp%3A%2F%2Fx%2Fcatalog.json.gz'), isNull);
      expect(parseCatalogInvite('moonfin://vjodcatalog?u='), isNull);
    });
  });

  group('deep link', () {
    test('an invitation opens the TV tab with the address', () {
      final route = DeepLinkService.routeForDeepLink(Uri.parse(buildCatalogInvite(url)));
      expect(route, startsWith('/tv?catalog='));
      final back = Uri.parse(route!).queryParameters['catalog'];
      expect(back, url);
    });

    test('an invitation without address is none', () {
      expect(DeepLinkService.routeForDeepLink(Uri.parse('moonfin://vjodcatalog')), isNull);
    });
  });
}
