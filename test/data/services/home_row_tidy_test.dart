import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/data/services/home_row_tidy.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';

AggregatedItem movie(String id, {String? tmdb}) => AggregatedItem(
  id: id,
  serverId: 's1',
  rawData: {
    'Name': id,
    'Type': 'Movie',
    if (tmdb != null) 'ProviderIds': {'Tmdb': tmdb},
  },
);

AggregatedItem series(String id) => AggregatedItem(
  id: id,
  serverId: 's1',
  rawData: {'Name': id, 'Type': 'Series'},
);

AggregatedItem episode(String id, String seriesId) => AggregatedItem(
  id: id,
  serverId: 's1',
  rawData: {'Name': id, 'Type': 'Episode', 'SeriesId': seriesId},
);

AggregatedItem seerr(String tmdb, {String type = 'movie', int? status}) =>
    AggregatedItem(
      id: tmdb,
      serverId: 'seerr',
      rawData: {
        'Name': 'tmdb $tmdb',
        'Type': type == 'tv' ? 'Series' : 'Movie',
        'SeerrMediaType': type,
        'SeerrStatus': ?status,
        'SeerrForYou': true,
      },
    );

HomeRow row(
  String id,
  HomeRowType type,
  List<AggregatedItem> items, {
  int? total,
}) => HomeRow(
  id: id,
  title: id,
  rowType: type,
  items: items,
  totalCount: total ?? items.length,
);

List<String> ids(HomeRow row) => [for (final i in row.items) i.id];

void main() {
  test('a title shown higher up leaves the browsing rows below', () {
    final rows = tidyHomeRows([
      row('resume', HomeRowType.resume, [movie('sing2')]),
      row('latest', HomeRowType.latestMedia, [
        movie('punisher'),
        movie('sing2'),
      ]),
      row('family', HomeRowType.pluginDynamic, [
        movie('sing2'),
        movie('nezha'),
      ]),
    ]);
    expect(ids(rows[1]), ['punisher']);
    expect(ids(rows[2]), ['nezha']);
  });

  test('rows with a list of their own keep everything', () {
    final rows = tidyHomeRows(
      [
        row('latest', HomeRowType.latestMedia, [movie('a'), movie('b')]),
        row('resume', HomeRowType.resume, [movie('a')]),
        row('top10', HomeRowType.pluginDynamic, [movie('b'), movie('c')]),
      ],
      keptRowIds: const {'top10'},
    );
    expect(ids(rows[1]), ['a']);
    expect(ids(rows[2]), ['b', 'c']);
  });

  test('an episode stands for its series', () {
    final rows = tidyHomeRows([
      row('nextUp', HomeRowType.nextUp, [episode('e12', 'solar')]),
      row('latest', HomeRowType.latestMedia, [series('solar'), series('pitt')]),
    ]);
    expect(ids(rows[1]), ['pitt']);
  });

  test('a Seerr card matches the library copy by its TMDB id', () {
    final rows = tidyHomeRows([
      row('latest', HomeRowType.latestMedia, [movie('lib1', tmdb: '42')]),
      row('forYou', HomeRowType.pluginDynamic, [seerr('42'), seerr('7')]),
    ]);
    expect(ids(rows[1]), ['7']);
  });

  test('a series and a film sharing a TMDB number stay apart', () {
    final rows = tidyHomeRows([
      row('a', HomeRowType.pluginDynamic, [seerr('42')]),
      row('b', HomeRowType.pluginDynamic, [seerr('42', type: 'tv')]),
    ]);
    expect(ids(rows[1]), ['42']);
  });

  test('a row with nothing new keeps what it had', () {
    final rows = tidyHomeRows([
      row('a', HomeRowType.latestMedia, [movie('x')]),
      row('b', HomeRowType.latestMedia, [movie('x')]),
    ]);
    expect(ids(rows[1]), ['x']);
  });

  test('the banner does not empty the rows', () {
    final rows = tidyHomeRows([
      row('bar', HomeRowType.mediaBar, [movie('x')]),
      row('latest', HomeRowType.latestMedia, [movie('x'), movie('y')]),
    ]);
    expect(ids(rows[1]), ['x', 'y']);
  });

  test('paging still knows how much is left', () {
    final rows = tidyHomeRows([
      row('resume', HomeRowType.resume, [movie('a')]),
      row('latest', HomeRowType.latestMedia, [movie('a'), movie('b')],
          total: 40),
    ]);
    expect(rows[1].totalCount, 39);
    expect(rows[1].hasMore, isTrue);
  });

  test('untouched rows are the same objects', () {
    final latest = row('latest', HomeRowType.latestMedia, [movie('a')]);
    expect(identical(tidyHomeRows([latest]).single, latest), isTrue);
  });

  test('a title requested this session shows as requested', () {
    final rows = tidyHomeRows(
      [
        row('gems', HomeRowType.pluginDynamic, [seerr('5'), seerr('6')]),
      ],
      requestedKeys: const {'movie:5'},
      requestableFlag: 'SeerrForYou',
    );
    final card = rows.single.items.first;
    expect(card.seerrStatus, SeerrMediaStatus.pending);
    expect(card.rawData.containsKey('SeerrForYou'), isFalse);
    expect(rows.single.items.last.seerrStatus, isNull);
  });

  test('a status Seerr already gave is kept', () {
    final rows = tidyHomeRows(
      [
        row('gems', HomeRowType.pluginDynamic, [
          seerr('5', status: SeerrMediaStatus.available),
        ]),
      ],
      requestedKeys: const {'movie:5'},
    );
    expect(rows.single.items.single.seerrStatus, SeerrMediaStatus.available);
  });
}
