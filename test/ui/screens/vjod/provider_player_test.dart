import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/xtream_catalog.dart';
import 'package:moonfin/ui/screens/vjod/provider_player_screen.dart';

void main() {
  test('track languages are spelled out in French', () {
    expect(trackLanguageName('fre', null), 'Français');
    expect(trackLanguageName('rus', 'Дубляж'), 'Russe · Дубляж');
    expect(trackLanguageName('eng', 'eng'), 'Anglais');
    expect(trackLanguageName('', 'Commentaires'), 'Commentaires');
    expect(trackLanguageName('xyz', null), 'XYZ');
  });

  test('provider tags map to track codes', () {
    expect(trackCodesOfTag('FR'), contains('fre'));
    expect(trackCodesOfTag('cn'), contains('chi'));
    expect(trackCodesOfTag('MULTI'), isEmpty);
  });

  test('the player title names the version', () {
    const film = XtreamTitle(
      kind: XtreamKind.movie,
      id: '1',
      name: 'Dune (2021)',
      tag: 'RU',
      poster: '',
      extension: 'mkv',
      searchKey: 'dune (2021)',
    );
    expect(providerPlayerTitle(film, quality: '4K'), 'Dune (2021) · ${languageName('RU')} · 4K');
  });
}
