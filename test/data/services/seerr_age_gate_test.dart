import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/data/services/seerr/seerr_age_gate.dart';
import 'package:moonfin/util/parental_filter.dart';

AggregatedItem seerr(int id, {String type = 'movie'}) => AggregatedItem(
  id: '$id',
  serverId: 'seerr',
  rawData: {'Name': 'T$id', 'SeerrMediaType': type},
);

AggregatedItem owned(String id) =>
    AggregatedItem(id: id, serverId: 'server', rawData: {'Name': id});

void main() {
  group('parseAgeInfo', () {
    test('reads the French rating of a film before the American one', () {
      final info = parseAgeInfo({
        'releases': {
          'results': [
            {
              'iso_3166_1': 'US',
              'release_dates': [
                {'certification': 'R'},
              ],
            },
            {
              'iso_3166_1': 'FR',
              'release_dates': [
                {'certification': ''},
                {'certification': '12'},
              ],
            },
          ],
        },
        'genres': [
          {'id': 18, 'name': 'Drame'},
        ],
      });
      expect(info.certification, '12');
      expect(info.genres, [18]);
    });

    test('reads a series rating', () {
      final info = parseAgeInfo({
        'contentRatings': {
          'results': [
            {'iso_3166_1': 'US', 'rating': 'TV-MA'},
          ],
        },
      });
      expect(info.certification, 'TV-MA');
    });

    test('a rating from elsewhere only is ignored', () {
      final info = parseAgeInfo({
        'contentRatings': {
          'results': [
            {'iso_3166_1': 'BR', 'rating': 'L'},
          ],
        },
      });
      expect(info.certification, isNull);
    });
  });

  group('ageAllows', () {
    final child = ParentalFilter.fromRatings(['12']);

    test('blocks a rating at or above the one blocked', () {
      expect(ageAllows(child, (certification: '12', genres: [])), isFalse);
      expect(ageAllows(child, (certification: 'R', genres: [])), isFalse);
      expect(ageAllows(child, (certification: 'U', genres: [])), isTrue);
      expect(ageAllows(child, (certification: 'PG', genres: [])), isTrue);
    });

    test('an unrated title passes only as a children\'s genre', () {
      expect(ageAllows(child, (certification: null, genres: [18])), isFalse);
      expect(ageAllows(child, (certification: null, genres: [16])), isTrue);
      expect(ageAllows(child, (certification: null, genres: [10751])), isTrue);
    });
  });

  group('withAgeGate', () {
    test('drops what is refused or not known yet, keeps the library', () {
      final rows = withAgeGate(
        [
          HomeRow(
            id: 'top',
            title: 'Top',
            rowType: HomeRowType.pluginDynamic,
            items: [seerr(1), seerr(2), seerr(3, type: 'tv'), owned('a')],
          ),
        ],
        (type, id) => switch ((type, id)) {
          ('movie', 1) => true,
          ('movie', 2) => false,
          _ => null,
        },
      );
      expect(rows.single.items.map((i) => i.id), ['1', 'a']);
    });

    test('a row left empty goes, an untouched row stays as it was', () {
      final kept = HomeRow(
        id: 'lib',
        title: 'Lib',
        rowType: HomeRowType.latestMedia,
        items: [owned('a')],
      );
      final rows = withAgeGate([
        HomeRow(
          id: 'fr',
          title: 'Fr',
          rowType: HomeRowType.pluginDynamic,
          items: [seerr(1)],
        ),
        kept,
      ], (_, _) => false);
      expect(rows, [same(kept)]);
    });
  });

  group('SeerrAgeGate', () {
    test('looks a title up once and lets it through when it may', () async {
      var lookups = 0;
      final gate = SeerrAgeGate((type, id) async {
        lookups++;
        return (certification: 'U', genres: const <int>[]);
      });
      final child = ParentalFilter.fromRatings(['12']);
      expect(gate.allows('movie', 7, filter: child), isNull);
      expect(gate.allows('movie', 7, filter: child), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(gate.allows('movie', 7, filter: child), isTrue);
      expect(lookups, 1);
      expect(gate.version, 1);
    });

    test('lets everything through with no rating blocked', () {
      final gate = SeerrAgeGate((_, _) => throw StateError('no lookup'));
      expect(gate.allows('movie', 7, filter: ParentalFilter.none), isTrue);
    });
  });
}
