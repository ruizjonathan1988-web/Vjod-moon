// VJOD 4.20 : le temps de réponse de chaque service, d'habitude et quand
// c'est lent, pour « À propos » et la page Ma TV.
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/vjod_timings.dart';

void main() {
  setUp(VjodTimings.reset);

  test('médiane, lent, et l’appel le plus lent', () async {
    for (final ms in [100, 120, 110, 130, 2000]) {
      VjodTimings.add('Seerr', Duration(milliseconds: ms), what: ms == 2000 ? '/api/v1/search' : '/api/v1/x');
    }
    VjodTimings.add('Ma TV', const Duration(milliseconds: 40));
    final s = VjodTimings.summary();
    expect(s['Seerr']!.median, 120);
    expect(s['Seerr']!.p90, 2000);
    expect(s['Seerr']!.slowest, '/api/v1/search');
    expect(VjodTimings.lines().first, startsWith('Seerr : 120 ms d’habitude, 2,0 s quand c’est lent'));
  });

  test('time() compte même un appel qui échoue', () async {
    final mark = VjodTimings.mark();
    await expectLater(VjodTimings.time('Jellyfin', Future<void>.error('x')), throwsA('x'));
    expect(VjodTimings.changedSince(mark), isTrue);
    expect(VjodTimings.summary()['Jellyfin']!.count, 1);
  });
}
