import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/vjod_smoothness.dart';

void main() {
  setUp(VjodSmoothness.reset);

  test('un écran se nomme par son adresse, sans les identifiants', () {
    expect(VjodSmoothness.screenName('/item/0123456789abcdef0123456789abcdef?x=1'), '/item');
    expect(VjodSmoothness.screenName('/item/0123456789abcdef0123456789abcdef/list'), '/item/list');
    expect(VjodSmoothness.screenName('/seerr/media/12345'), '/seerr/media');
    expect(VjodSmoothness.screenName('/'), 'Accueil');
  });

  test('la part d’images saccadées, l’écran le plus saccadé en premier', () {
    for (var i = 0; i < 100; i++) {
      VjodSmoothness.add('/item/0123456789abcdef0123456789abcdef', i < 25 ? 80 : 10);
      VjodSmoothness.add('/', i < 5 ? 40 : 8);
    }
    expect(VjodSmoothness.slowPercent('/item'), 25);
    expect(VjodSmoothness.slowPercent('Accueil'), 5);
    final lines = VjodSmoothness.lines();
    expect(lines.first, startsWith('/item : 25 %'));
    expect(lines.first, contains('pire 80 ms'));
  });

  test('trop peu d’images pour juger : rien n’est affiché', () {
    for (var i = 0; i < 10; i++) {
      VjodSmoothness.add('/search', 100);
    }
    expect(VjodSmoothness.slowPercent('/search'), isNull);
    expect(VjodSmoothness.lines(), isEmpty);
  });

  test('un écran est prêt quand plus rien ne bouge : le temps d’ouverture', () {
    final t0 = DateTime(2026, 11, 8, 20);
    VjodSmoothness.add('/item', 10);
    VjodSmoothness.opened('/item', t0);
    // Rien de dessiné depuis l'ouverture pendant 300 ms : prêt tout de suite.
    VjodSmoothness.check(t0.add(const Duration(milliseconds: 350)));
    expect(VjodSmoothness.openMs('/item'), 0);
    VjodSmoothness.settled('/item', 1200);
    VjodSmoothness.settled('/item', 800);
    expect(VjodSmoothness.openMs('/item'), 800);
    expect(VjodSmoothness.lines().single, contains('prêt en 0,8 s (3 ouvertures)'));
  });

  test('un écran toujours animé n’est pas mesuré', () {
    final t0 = DateTime(2026, 11, 8, 20);
    VjodSmoothness.opened('/live-tv', t0);
    VjodSmoothness.check(t0.add(const Duration(seconds: 16)));
    expect(VjodSmoothness.openMs('/live-tv'), isNull);
  });
}
