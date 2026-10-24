import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/for_you_ranker.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/services/seerr/upcoming_picks.dart';

final _now = DateTime(2026, 10, 22);

SeerrDiscoverItem _item(
  int id, {
  String releaseDate = '2027-03-01',
  int? status,
  double popularity = 50,
  String? poster = '/p.jpg',
}) => SeerrDiscoverItem(
  id: id,
  mediaType: 'movie',
  title: 'T$id',
  posterPath: poster,
  releaseDate: releaseDate,
  popularity: popularity,
  mediaInfo: status == null ? null : SeerrMediaInfo(status: status),
);

const _seed = TasteSeed(
  tmdbId: 1,
  mediaType: 'movie',
  title: 'Dune',
  weight: 1,
);

List<int> _ids(List<UpcomingPick> picks) => [for (final p in picks) p.item.id];

void main() {
  test('keeps only what comes out within the year', () {
    final picks = UpcomingPicks.rank(
      seeds: [_seed],
      recommendationsBySeed: {
        _seed.key: [
          _item(10),
          _item(11, releaseDate: '2025-01-01'),
          _item(12, releaseDate: '2028-06-01'),
          _item(13, releaseDate: ''),
        ],
      },
      now: _now,
    );
    expect(_ids(picks), [10]);
    expect(picks.single.because?.title, 'Dune');
  });

  test('what a seed vouches for leads the upcoming lists', () {
    final picks = UpcomingPicks.rank(
      seeds: [_seed],
      recommendationsBySeed: {
        _seed.key: [for (var i = 0; i < 10; i++) _item(100 + i)],
      },
      upcoming: [(_item(200, popularity: 900), 'movie')],
      now: _now,
    );
    expect(picks.last.item.id, 200);
    expect(picks.last.because, isNull);
  });

  test('popular upcoming titles come first among the listed ones', () {
    final picks = UpcomingPicks.rank(
      seeds: const [],
      recommendationsBySeed: const {},
      upcoming: [
        (_item(1, popularity: 5), 'movie'),
        (_item(2, popularity: 300), 'movie'),
      ],
      now: _now,
    );
    expect(_ids(picks), [2, 1]);
  });

  test('requested stays, held or blocked goes, and taste can drop', () {
    final picks = UpcomingPicks.rank(
      seeds: const [],
      recommendationsBySeed: const {},
      upcoming: [
        (_item(1, status: SeerrMediaStatus.pending), 'movie'),
        (_item(2, status: SeerrMediaStatus.blocklisted), 'movie'),
        (_item(3, status: SeerrMediaStatus.available), 'movie'),
        (_item(4, poster: null), 'movie'),
        (_item(5), 'movie'),
      ],
      weigh: (item, _) => item.id == 5 ? 0 : 1,
      now: _now,
    );
    expect(_ids(picks), [1]);
  });

  test('excluded keys and the seeds themselves stay out', () {
    final picks = UpcomingPicks.rank(
      seeds: [_seed],
      recommendationsBySeed: {
        _seed.key: [_item(1), _item(2)],
      },
      excludeKeys: {'movie:2'},
      now: _now,
    );
    expect(picks, isEmpty);
  });
}
