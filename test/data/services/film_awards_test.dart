import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/wikidata/film_awards_client.dart';

Map<String, Object?> row(String tmdb) => {
  'tmdb': {'type': 'literal', 'value': tmdb},
  'latest': {'type': 'literal', 'value': '2025'},
};

void main() {
  test('reads the TMDB ids in the order Wikidata gives them', () {
    final ids = parseAwardWinners({
      'results': {
        'bindings': [row('961077'), row('915935'), row('925102')],
      },
    });
    expect(ids, [961077, 915935, 925102]);
  });

  test('skips what is not a TMDB id, and repeats', () {
    final ids = parseAwardWinners({
      'results': {
        'bindings': [row('abc'), row('7'), row('7'), {'other': 1}],
      },
    });
    expect(ids, [7]);
  });

  test('a broken answer gives nothing', () {
    expect(parseAwardWinners(null), isEmpty);
    expect(parseAwardWinners({'results': {}}), isEmpty);
  });
}
