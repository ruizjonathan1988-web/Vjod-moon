
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/services/home_highlights.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';

SeerrDiscoverItem _charted(int id, {String? poster = '/p.jpg'}) =>
    SeerrDiscoverItem(id: id, mediaType: 'movie', posterPath: poster);

AggregatedItem _item({
  String type = 'Movie',
  String? created,
  bool played = false,
  double? playedPercentage,
  double? rating,
  String id = 'x',
}) => AggregatedItem(
  id: id,
  serverId: 'server',
  rawData: {
    'Type': type,
    'ImageTags': {'Primary': 'tag'},
    if (type == 'Episode') 'SeriesId': 'series',
    'DateCreated': ?created,
    'CommunityRating': ?rating,
    'UserData': {
      'Played': played,
      'PlayedPercentage': ?playedPercentage,
    },
  },
);

void main() {
  group('chartPicks', () {
    test('keeps chart order, each title once, only with a poster', () {
      final picks = chartPicks([
        _charted(1),
        _charted(2, poster: null),
        _charted(3),
        _charted(1),
        _charted(4, poster: ''),
        _charted(5),
      ]);
      expect([for (final p in picks) p.id], [1, 3, 5]);
    });

    test('stops at ten', () {
      final picks = chartPicks([for (var i = 0; i < 30; i++) _charted(i)]);
      expect(picks, hasLength(10));
      expect(picks.first.id, 0);
    });
  });

  group('fuseCharts', () {
    List<int> ids(List<SeerrDiscoverItem> chart) => [for (final i in chart) i.id];

    test('a title in several charts shows once and ranks higher', () {
      final fused = fuseCharts([
        [_charted(1), _charted(2), _charted(3)],
        [_charted(4), _charted(2), _charted(5)],
      ]);
      expect(ids(fused), [2, 1, 4, 3, 5]);
    });

    test('equal points go to the title in more charts', () {
      // 1 tops one chart: 10 points. 2 is sixth in both: 5 + 5.
      List<SeerrDiscoverItem> chart(int top) => [
        _charted(top),
        for (var i = 1; i < 5; i++) _charted(top * 10 + i),
        _charted(2),
      ];
      final fused = fuseCharts([chart(1), chart(3)]);
      expect(fused.first.id, 2);
    });

    test('only the first ten of each chart count', () {
      final fused = fuseCharts([
        [for (var i = 0; i < 15; i++) _charted(i)],
      ]);
      expect(fused, hasLength(10));
    });

    test('an empty source changes nothing', () {
      final fused = fuseCharts([
        const [],
        [_charted(7), _charted(8)],
      ]);
      expect(ids(fused), [7, 8]);
    });
  });

  test('the year chart looks at the last twelve months', () {
    final window = yearChartWindow(DateTime(2026, 2, 5));
    expect(window.from, '2025-02-05');
    expect(window.to, '2026-02-05');
  });

  group('isFreshlyAdded', () {
    final now = DateTime.utc(2026, 10, 19, 20);

    test('a movie added three days ago and never started is new', () {
      expect(
        isFreshlyAdded(_item(created: '2026-10-16T10:00:00Z'), now: now),
        isTrue,
      );
    });

    test('an old, watched, started or undated title is not', () {
      expect(isFreshlyAdded(_item(created: '2026-09-01T10:00:00Z'), now: now),
          isFalse);
      expect(
        isFreshlyAdded(
          _item(created: '2026-10-18T10:00:00Z', played: true),
          now: now,
        ),
        isFalse,
      );
      expect(
        isFreshlyAdded(
          _item(created: '2026-10-18T10:00:00Z', playedPercentage: 12),
          now: now,
        ),
        isFalse,
      );
      expect(isFreshlyAdded(_item(), now: now), isFalse);
    });

    test('series and folders never carry it', () {
      expect(
        isFreshlyAdded(
          _item(type: 'Series', created: '2026-10-18T10:00:00Z'),
          now: now,
        ),
        isFalse,
      );
      expect(
        isFreshlyAdded(
          _item(type: 'Episode', created: '2026-10-18T10:00:00Z'),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('pickSurprise', () {
    test('prefers the first well-rated title', () {
      final pick = pickSurprise([
        _item(id: 'meh', rating: 5.1),
        _item(id: 'good', rating: 7.4),
        _item(id: 'great', rating: 8.9),
      ]);
      expect(pick?.id, 'good');
    });

    test('falls back to the first title, or nothing', () {
      expect(pickSurprise([_item(id: 'only', rating: 4)])?.id, 'only');
      expect(pickSurprise(const []), isNull);
    });
  });

  group('loose downloads', () {
    final now = DateTime.utc(2026, 10, 19, 20);

    test('an unidentified file is not new', () {
      final loose = AggregatedItem(
        id: 'raw',
        serverId: 'server',
        rawData: const {
          'Type': 'Movie',
          'DateCreated': '2026-10-18T10:00:00Z',
          'UserData': {'Played': false},
        },
      );
      expect(isFreshlyAdded(loose, now: now), isFalse);
    });
  });

  group('pickFamilyNight', () {
    test('best rated first, posterless dropped, no repeats', () {
      final picks = pickFamilyNight([
        _item(id: 'ok', rating: 6.4),
        _item(id: 'top', rating: 8.1),
        _item(id: 'low', rating: 4.0),
        _item(id: 'top', rating: 8.1),
        AggregatedItem(
          id: 'bare',
          serverId: 'server',
          rawData: const {'Type': 'Movie', 'CommunityRating': 9.0},
        ),
      ]);
      expect(picks.map((i) => i.id), ['top', 'ok', 'low']);
    });
  });

  group('films out at home', () {
    final now = DateTime(2026, 10, 21);

    test('reads every country of the details', () {
      final releases = parseFilmReleases({
        'releases': {
          'results': [
            {
              'iso_3166_1': 'FR',
              'release_dates': [
                {'type': 3, 'release_date': '2026-07-15T00:00:00.000Z'},
              ],
            },
            {
              'iso_3166_1': 'US',
              'release_dates': [
                {'type': 4, 'release_date': '2026-11-17T00:00:00.000Z'},
                {'type': 3, 'release_date': 'not a date'},
              ],
            },
          ],
        },
      });
      expect([for (final r in releases) r.type], [3, 4]);
    });

    test('details without dates give none', () {
      expect(parseFilmReleases({'title': 'x'}), isEmpty);
    });

    test('a film out on digital can be watched', () {
      expect(
        isOutAtHome([(type: 4, date: DateTime(2026, 10, 1))], now),
        isTrue,
      );
    });

    test('a film only in cinemas cannot yet', () {
      expect(
        isOutAtHome([
          (type: 3, date: DateTime(2026, 9, 1)),
          (type: 4, date: DateTime(2026, 12, 1)),
        ], now),
        isFalse,
      );
    });

    test('four months after cinemas it is taken as out', () {
      expect(
        isOutAtHome([(type: 3, date: DateTime(2026, 6, 1))], now),
        isTrue,
      );
    });

    test('a film with no dates gets the benefit of the doubt', () {
      expect(isOutAtHome(const [], now), isTrue);
    });
  });

  group('isWellRated', () {
    SeerrDiscoverItem rated(double average, int votes) => SeerrDiscoverItem(
      id: 1,
      voteAverage: average,
      voteCount: votes,
    );

    test('a title many rated poorly stays out', () {
      expect(isWellRated(rated(4.4, 1200)), isFalse);
    });

    test('a well rated title stays in', () {
      expect(isWellRated(rated(7.1, 1200)), isTrue);
    });

    test('a title just out keeps its chance', () {
      expect(isWellRated(rated(3.0, 12)), isTrue);
    });
  });

  test('tmdbDay pads month and day', () {
    expect(tmdbDay(DateTime(2026, 3, 7)), '2026-03-07');
  });

  group('takeTurns', () {
    SeerrDiscoverItem t(int id) => SeerrDiscoverItem(id: id);
    List<int> ids(List<SeerrDiscoverItem> row) => [for (final i in row) i.id];

    test('the lists take turns, each title once', () {
      final row = takeTurns([
        [t(1), t(2), t(3)],
        [t(10), t(1)],
        [t(20)],
      ], keyOf: tmdbKey);
      expect(ids(row), [1, 10, 20, 2, 3]);
    });

    test('empty lists are skipped', () {
      expect(ids(takeTurns([[], [t(5)]], keyOf: tmdbKey)), [5]);
      expect(takeTurns(const <List<int>>[]), isEmpty);
    });

    test('plain ids need no key', () {
      expect(
        takeTurns([
          [77338, 262391],
          [8265, 77338],
        ]),
        [77338, 8265, 262391],
      );
    });
  });
}
