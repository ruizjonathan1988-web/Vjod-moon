import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/item_prefetch.dart';

void main() {
  setUp(ItemPrefetch.reset);
  final t = DateTime(2026, 11, 8, 20);

  test('une fiche demandée en avance sert une fois, tant qu’elle est récente', () async {
    var asked = 0;
    ItemPrefetch.warm('abc', (id) async {
      asked++;
      return {'Id': id};
    }, t);
    ItemPrefetch.warm('abc', (id) async => {'Id': id}, t.add(const Duration(seconds: 10)));
    expect(asked, 1);
    expect(await ItemPrefetch.take('abc', t.add(const Duration(seconds: 30))), {'Id': 'abc'});
    expect(ItemPrefetch.take('abc', t.add(const Duration(seconds: 31))), isNull);
  });

  test('trop vieille, elle n’est pas servie', () {
    ItemPrefetch.warm('abc', (id) async => {'Id': id}, t);
    expect(ItemPrefetch.take('abc', t.add(const Duration(minutes: 3))), isNull);
  });

  test('une affiche à peine survolée ne demande rien', () {
    var asked = 0;
    ItemPrefetch.selected('abc', (id) async {
      asked++;
      return {};
    });
    ItemPrefetch.selected('def', (id) async {
      asked++;
      return {};
    });
    ItemPrefetch.reset();
    expect(asked, 0);
  });
}
