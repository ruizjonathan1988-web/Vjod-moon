import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/jellyfin_vjod_config.dart';

void main() {
  // What the seedbox script writes for this address (config_overview).
  const overview =
      'Réglages automatiques de VJOD (catalogue IPTV de la seedbox). '
      'Ne pas modifier ni supprimer : la seedbox la met à jour chaque nuit.\n\n'
      'VJOD-CONFIG:eyJ2IjoxLCJjYXRhbG9nIjoiaHR0cHM6Ly9hdmE4ODpwJTQwc3NAemVuLnVzYngubWUvdmpvZC9jYXRhbG9nLmpzb24uZ3oifQ';

  test("reads the address the seedbox left in Jellyfin", () {
    expect(
      catalogUrlFromOverview(overview),
      'https://ava88:p%40ss@zen.usbx.me/vjod/catalog.json.gz',
    );
  });

  test('anything else is none', () {
    expect(catalogUrlFromOverview(null), isNull);
    expect(catalogUrlFromOverview('Une collection ordinaire'), isNull);
    expect(catalogUrlFromOverview('VJOD-CONFIG:pasdubase64!!'), isNull);
  });
}
