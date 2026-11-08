import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/vjod_smoothness.dart';

void main() {
  setUp(VjodSmoothness.reset);

  test('un écran se nomme par le début de son adresse', () {
    expect(VjodSmoothness.screenName('/item/abc123?x=1'), '/item');
    expect(VjodSmoothness.screenName('/'), 'Accueil');
  });

  test('la part d’images saccadées, l’écran le plus saccadé en premier', () {
    for (var i = 0; i < 100; i++) {
      VjodSmoothness.add('/item/1', i < 25 ? 80 : 10);
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
}
