import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/seerr_page_cache.dart';

void main() {
  const api = 'https://srv.example/jellyfin/Moonfin/Seerr/Api';
  setUp(SeerrPageCache.resetForTest);

  test('les pages lues sont gardées, pas ce qui est propre au spectateur ni ce qui écrit', () {
    expect(SeerrPageCache.cacheable('GET', '$api/discover/movies'), isTrue);
    expect(SeerrPageCache.cacheable('GET', '$api/discover/tv/upcoming'), isTrue);
    expect(SeerrPageCache.cacheable('GET', '$api/movie/603/similar'), isTrue);
    expect(SeerrPageCache.cacheable('GET', '$api/tv/1399'), isTrue);
    expect(SeerrPageCache.cacheable('GET', '$api/discover/watchlist'), isFalse);
    expect(SeerrPageCache.cacheable('GET', '$api/request'), isFalse);
    expect(SeerrPageCache.cacheable('GET', '$api/user/1/quota'), isFalse);
    expect(SeerrPageCache.cacheable('POST', '$api/request'), isFalse);
  });

  test('servie telle quelle si récente, servie puis redemandée ensuite, oubliée après un jour', () {
    final t = DateTime(2026, 11, 8, 20);
    expect(SeerrPageCache.useFor(t, t.add(const Duration(minutes: 1))), SeerrCacheUse.serve);
    expect(SeerrPageCache.useFor(t, t.add(const Duration(minutes: 30))), SeerrCacheUse.serveAndRefresh);
    expect(SeerrPageCache.useFor(t, t.add(const Duration(hours: 25))), SeerrCacheUse.none);
  });

  test('une page redemandée sort tout de suite, et se rafraîchit quand elle a quelques minutes', () {
    final t = DateTime(2026, 11, 8, 20);
    SeerrPageCache.store('k', {'results': [1, 2]}, t);
    var refreshed = 0;
    expect(SeerrPageCache.lookup('k', t.add(const Duration(minutes: 1)), refresh: () => refreshed++), {'results': [1, 2]});
    expect(refreshed, 0);
    expect(SeerrPageCache.lookup('k', t.add(const Duration(minutes: 10)), refresh: () => refreshed++), isNotNull);
    expect(refreshed, 1);
  });

  test('une demande faite vide tout, pour ne pas montrer un titre « à demander » déjà demandé', () {
    SeerrPageCache.store('k', {'a': 1}, DateTime(2026, 11, 8));
    SeerrPageCache.clear();
    expect(SeerrPageCache.length, 0);
  });
}
