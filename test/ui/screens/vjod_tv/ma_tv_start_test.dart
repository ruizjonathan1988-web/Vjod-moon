// VJOD 4.9: the TV tab never opens on Rechercher, Sports or Enregistrements
// (the remote seemed stuck there, the channel column being empty).
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/ma_tv.dart';
import 'package:moonfin/ui/screens/vjod_tv/ma_tv_screen.dart';

MaTvCategory _c(String id, String kind) => MaTvCategory(id: id, label: id, kind: kind, count: 1);

final _cats = [
  _c('search', 'search'),
  _c('sports', 'sports'),
  _c('rec', 'rec'),
  _c('recent', 'recent'),
  _c('all', 'all'),
  _c('t:Sport', 'theme'),
  _c('c:FR', 'country'),
];

void main() {
  test('la dernière catégorie regardée', () {
    expect(maTvStartCategory(_cats, 't:Sport'), 5);
  });

  test('jamais Rechercher, Sports ou Enregistrements, même retenus avant', () {
    expect(maTvStartCategory(_cats, 'search'), 6);
    expect(maTvStartCategory(_cats, 'sports'), 6);
    expect(maTvStartCategory(_cats, 'rec'), 6);
  });

  test('sans France : la première liste de chaînes', () {
    final cats = _cats.where((c) => c.id != 'c:FR').toList();
    expect(maTvStartCategory(cats, 'search'), 3);
  });

  test('les favoris passent avant la France', () {
    final cats = [..._cats, _c('fav', 'fav')];
    expect(maTvStartCategory(cats, ''), cats.length - 1);
  });
}
