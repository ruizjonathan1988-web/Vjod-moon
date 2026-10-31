import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/services/vjod/catalogue_availability.dart';

void main() {
  group('comment regarder un titre', () {
    test('sur le serveur passe avant tout, même s\'il est aussi en IPTV', () {
      expect(catalogueAvailability(seerrStatus: SeerrMediaStatus.available, hasIptv: true), CatalogueAvailability.server);
      expect(catalogueAvailability(seerrStatus: SeerrMediaStatus.partiallyAvailable, hasIptv: false), CatalogueAvailability.server);
    });

    test('sinon IPTV, même déjà demandé', () {
      expect(catalogueAvailability(seerrStatus: SeerrMediaStatus.pending, hasIptv: true), CatalogueAvailability.iptv);
      expect(catalogueAvailability(seerrStatus: null, hasIptv: true), CatalogueAvailability.iptv);
    });

    test('sinon demandé, ou à demander', () {
      expect(catalogueAvailability(seerrStatus: SeerrMediaStatus.processing, hasIptv: false), CatalogueAvailability.requested);
      expect(catalogueAvailability(seerrStatus: null, hasIptv: false), CatalogueAvailability.toRequest);
      expect(catalogueAvailability(seerrStatus: SeerrMediaStatus.unknown, hasIptv: false), CatalogueAvailability.toRequest);
    });
  });

  group('le filtre en haut de la page', () {
    test('Tout garde tout', () {
      for (final a in CatalogueAvailability.values) {
        expect(catalogueFilterKeeps(0, a), isTrue);
      }
    });

    test('chaque filtre garde son genre', () {
      expect(catalogueFilterKeeps(1, CatalogueAvailability.server), isTrue);
      expect(catalogueFilterKeeps(1, CatalogueAvailability.iptv), isFalse);
      expect(catalogueFilterKeeps(2, CatalogueAvailability.iptv), isTrue);
      expect(catalogueFilterKeeps(2, CatalogueAvailability.toRequest), isFalse);
      expect(catalogueFilterKeeps(3, CatalogueAvailability.toRequest), isTrue);
      expect(catalogueFilterKeeps(3, CatalogueAvailability.requested), isTrue);
      expect(catalogueFilterKeeps(3, CatalogueAvailability.server), isFalse);
    });
  });

  group('la loupe', () {
    test('Films ne garde que les films, Séries que les séries', () {
      expect(catalogueSearchKeeps(series: false, mediaType: 'movie'), isTrue);
      expect(catalogueSearchKeeps(series: false, mediaType: 'tv'), isFalse);
      expect(catalogueSearchKeeps(series: true, mediaType: 'tv'), isTrue);
      expect(catalogueSearchKeeps(series: true, mediaType: 'movie'), isFalse);
      expect(catalogueSearchKeeps(series: true, mediaType: 'person'), isFalse);
      expect(catalogueSearchKeeps(series: false, mediaType: null), isFalse);
    });

    test('il faut deux lettres au moins', () {
      expect(catalogueSearchQuery(''), isNull);
      expect(catalogueSearchQuery('  d '), isNull);
      expect(catalogueSearchQuery(' Dune '), 'Dune');
    });
  });

  test('la loupe trouve les acteurs, les plus connus d\'abord, deux au plus', () {
    const film = SeerrDiscoverItem(id: 1, mediaType: 'movie', title: 'Venom');
    const a = SeerrDiscoverItem(id: 2, mediaType: 'person', name: 'Tom Hardy', popularity: 50);
    const b = SeerrDiscoverItem(id: 3, mediaType: 'person', name: 'Tom Hanks', popularity: 80);
    const c = SeerrDiscoverItem(id: 4, mediaType: 'person', name: 'Tom Holland', popularity: 10);
    final people = catalogueSearchPeople([film, a, b, c]);
    expect(people.map((p) => p.name), ['Tom Hanks', 'Tom Hardy']);
    expect(catalogueSearchPeople([film]), isEmpty);
  });
}
