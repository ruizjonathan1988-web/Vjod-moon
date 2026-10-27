import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/secondary_library.dart';

void main() {
  test('a provider catalogue sits behind its own chip, after the others', () {
    expect(isProviderLibraryName('Films · Fournisseur'), isTrue);
    expect(isProviderLibraryName('Séries IPTV'), isTrue);
    expect(isProviderLibraryName('Films'), isFalse);
    expect(isSecondaryLibraryName('Films · Fournisseur'), isTrue);
    expect(isSecondaryLibraryName('Russian Movies'), isTrue);
    expect(isSecondaryLibraryName('Films'), isFalse);
    expect(libraryChipLabel('Films · Fournisseur', 'movies'), 'Fournisseur');
    expect(libraryChipLabel('Russian Shows', 'tvshows'), 'Séries RU');
    expect(libraryChipLabel('Films', 'movies'), 'Films');
    final order = ['Films · Fournisseur', 'Russian Movies', 'Films']
      ..sort((a, b) => libraryChipRank(a).compareTo(libraryChipRank(b)));
    expect(order, ['Films', 'Russian Movies', 'Films · Fournisseur']);
  });
}
