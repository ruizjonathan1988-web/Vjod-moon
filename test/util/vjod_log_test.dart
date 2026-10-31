import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/vjod_log.dart';

void main() {
  group('les secrets IPTV ne vont pas dans les journaux', () {
    test('la clé Ma TV', () {
      expect(
        redactIptvSecrets('GET /tv/api/vod/tmdb?kind=movie&k=Ff6ME64EMuYowN4dlXjaKrry&ids=1'),
        'GET /tv/api/vod/tmdb?kind=movie&k=[REDACTED]&ids=1',
      );
    });

    test('le compte du fournisseur dans son API', () {
      expect(
        redactIptvSecrets('player_api.php?username=jean&password=secret123&action=get_vod_streams'),
        'player_api.php?username=[REDACTED]&password=[REDACTED]&action=get_vod_streams',
      );
    });

    test('le compte dans le chemin des films, séries et chaînes', () {
      expect(redactIptvSecrets('http://x/movie/jean/secret123/42.mkv'), 'http://x/movie/[REDACTED]/[REDACTED]/42.mkv');
      expect(redactIptvSecrets('/series/jean/secret123/7.mp4'), '/series/[REDACTED]/[REDACTED]/7.mp4');
      expect(redactIptvSecrets('/tv/xc/live/vjod/MACLE/12.ts'), '/tv/xc/live/[REDACTED]/[REDACTED]/12.ts');
    });

    test('le reste ne bouge pas', () {
      const text = 'Media3: buffer target 32MB, /api/v1/movie/550?language=fr';
      expect(redactIptvSecrets(text), text);
    });
  });
}
