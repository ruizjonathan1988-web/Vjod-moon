import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/seed_recommendations.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';

SeerrDiscoverItem card(int id) => SeerrDiscoverItem(id: id, title: 'tmdb $id');

List<int> ids(List<SeerrDiscoverItem> cards) => [for (final c in cards) c.id];

void main() {
  test('a title TMDB and the members both name moves to the front', () {
    final merged = withCommunity(
      [card(1), card(2), card(3)],
      [3, 9],
      const [],
    );
    expect(ids(merged), [3, 1, 2]);
  });

  test("the members' own titles take turns with TMDB's", () {
    final merged = withCommunity(
      [card(1), card(2), card(3)],
      [8, 9],
      [card(8), card(9)],
    );
    expect(ids(merged), [1, 8, 2, 9, 3]);
  });

  test('without the members TMDB keeps its order', () {
    expect(ids(withCommunity([card(1), card(2)], const [], const [])), [1, 2]);
  });

  test('extras still show when TMDB has nothing', () {
    expect(ids(withCommunity(const [], [5], [card(5)])), [5]);
  });
}
