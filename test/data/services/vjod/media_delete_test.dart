import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/media_delete.dart';

void main() {
  test('the viewer is told what was freed', () {
    expect(const MediaDeleteResult(freed: 3 << 29).summary('Film'), '« Film » supprimé du serveur · 1,5 Go libérés');
    expect(const MediaDeleteResult(freed: 200 << 20).summary('Film'), '« Film » supprimé du serveur · 200 Mo libérés');
    expect(const MediaDeleteResult().summary('Film'), '« Film » supprimé du serveur');
    expect(const MediaDeleteResult(jellyfinOnly: true).summary('Film'), contains('Ma TV absent'));
    const failed = MediaDeleteResult(error: 'Ce profil n’a pas le droit');
    expect(failed.ok, isFalse);
    expect(failed.summary('Film'), 'Ce profil n’a pas le droit');
  });
}
