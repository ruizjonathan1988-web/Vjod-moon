import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/jellyfin_vjod_config.dart';

void main() {
  // What the seedbox script writes (config_overview) for this account.
  const overview =
      'Réglages automatiques de VJOD (catalogue IPTV de la seedbox). '
      'Ne pas modifier ni supprimer : la seedbox la met à jour chaque nuit.\n\n'
      'VJOD-CONFIG:eyJ2IjoyLCJwcm92aWRlciI6eyJwb3J0YWwiOiJodHRwOi8va2ltb3JhMy5jbG5kZi5jb20iLCJ1c2VybmFtZSI6IlUiLCJwYXNzd29yZCI6IlAifX0';

  test('reads the provider account the seedbox left in Jellyfin', () {
    final config = configFromOverview(overview)!;
    expect(config.provider!.portal, 'http://kimora3.clndf.com');
    expect(config.provider!.username, 'U');
    expect(config.provider!.password, 'P');
    expect(config.catalogUrl, isNull);
  });

  test('anything else is none', () {
    expect(configFromOverview(null), isNull);
    expect(configFromOverview('Une collection ordinaire'), isNull);
    expect(configFromOverview('VJOD-CONFIG:pasdubase64!!'), isNull);
  });
}
