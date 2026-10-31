import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/catalogue_availability.dart';
import 'package:moonfin/data/services/vjod/simple_mode.dart';
import 'package:moonfin/ui/screens/detail/detail_buttons.dart';
import 'package:moonfin/ui/screens/detail/item_detail_screen.dart' show vjodFrontRow;
import 'package:server_core/server_core.dart';

void main() {
  group('un seul bouton par titre', () {
    test('Regarder quand ça se lit, sur le serveur ou en IPTV', () {
      expect(simpleActionFor(CatalogueAvailability.server), SimpleAction.watch);
      expect(simpleActionFor(CatalogueAvailability.iptv), SimpleAction.watch);
    });

    test('Demander sinon, Demandé une fois demandé', () {
      expect(simpleActionFor(CatalogueAvailability.toRequest), SimpleAction.request);
      expect(simpleActionFor(CatalogueAvailability.requested), SimpleAction.requested);
    });
  });

  group('le réglage rangé dans Jellyfin', () {
    test('lu seulement quand il vaut true', () {
      expect(simpleModeFromPrefs(const {'simpleMode': 'true'}), isTrue);
      expect(simpleModeFromPrefs(const {'simpleMode': 'false'}), isFalse);
      expect(simpleModeFromPrefs(const {}), isFalse);
    });

    test('écrit sans toucher au reste', () {
      const before = DisplayPreferences(id: 'vjod', sortBy: 'Name', customPrefs: {'autre': 'x'});
      final on = withSimpleMode(before, true);
      expect(on.customPrefs, {'autre': 'x', 'simpleMode': 'true'});
      expect(on.sortBy, 'Name');
      expect(withSimpleMode(on, false).customPrefs['simpleMode'], 'false');
      expect(withSimpleMode(const DisplayPreferences(id: ''), true).id, 'vjod');
    });
  });

  test('la fiche : le bouton principal, la bande-annonce, la liste, rien d\'autre devant', () {
    final row = vjodFrontRow<String>(
      primary: 'Regarder',
      byButton: {
        DetailButton.trailer: 'Bande-annonce',
        DetailButton.favorite: 'Favori',
        DetailButton.restart: 'Depuis le début',
        DetailButton.notForMe: 'Pas pour moi',
      },
      providerExtras: const [],
      ordered: DetailButton.values,
      keep: simpleModeFicheButtons,
    );
    expect(row, ['Regarder', 'Bande-annonce', 'Favori']);
  });

  test('un peu plus grand, sans casser les écrans', () {
    expect(simpleModeTextScale, greaterThan(1));
    expect(simpleModeTextScale, lessThanOrEqualTo(1.15));
  });
}
