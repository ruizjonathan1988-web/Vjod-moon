import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/chart_cards.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';

SeerrDiscoverItem card(int id) =>
    SeerrDiscoverItem(id: id, title: 'tmdb $id', posterPath: '/p$id.jpg');

List<int> ids(List<SeerrDiscoverItem> cards) => [for (final c in cards) c.id];

void main() {
  group('chartCards', () {
    test('reuses a card another chart holds and fetches the rest', () async {
      final fetched = <int>[];
      final cards = await chartCards(
        [1, 2, 3],
        known: {2: card(2)},
        fetch: (id) async {
          fetched.add(id);
          return card(id);
        },
      );
      expect(ids(cards), [1, 2, 3]);
      expect(fetched, unorderedEquals([1, 3]));
    });

    test('leaves out a title whose card cannot be fetched', () async {
      final cards = await chartCards(
        [1, 2, 3],
        known: const {},
        fetch: (id) async => id == 2 ? throw StateError('404') : card(id),
      );
      expect(ids(cards), [1, 3]);
    });

    test('only looks at the first titles', () async {
      final cards = await chartCards(
        [for (var i = 1; i <= 20; i++) i],
        known: const {},
        fetch: (id) async => card(id),
        depth: 5,
      );
      expect(ids(cards), [1, 2, 3, 4, 5]);
    });
  });
}
