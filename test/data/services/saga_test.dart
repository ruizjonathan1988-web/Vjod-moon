import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/saga.dart';
import 'package:moonfin/data/services/seerr/saga_service.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';

SeerrDiscoverItem _film(
  int id,
  String date, {
  int? status,
  String? poster = '/p.jpg',
}) => SeerrDiscoverItem(
  id: id,
  mediaType: 'movie',
  title: 'Film $id',
  releaseDate: date,
  posterPath: poster,
  mediaInfo: status == null ? null : SeerrMediaInfo(status: status),
);

final _now = DateTime(2026, 10, 20);

void main() {
  final trilogy = SeerrCollection(
    id: 10,
    name: 'Trilogy',
    // Out of order on purpose: release order decides.
    parts: [_film(3, '2008-01-01'), _film(1, '2001-01-01'), _film(2, '2004-01-01')],
  );

  group('nextInSagas', () {
    test('suggests the film after the last one watched', () {
      final picks = nextInSagas(
        watched: [(tmdbId: 1, title: 'Film 1')],
        collectionOfFilm: {1: 10},
        collections: {10: trilogy},
        now: _now,
      );
      expect(picks.single.item.id, 2);
      expect(picks.single.afterTitle, 'Film 1');
    });

    test('jumps past what was watched, unreleased or excluded', () {
      final saga = SeerrCollection(
        id: 20,
        parts: [
          _film(1, '2001-01-01'),
          _film(2, '2004-01-01'),
          _film(3, '2030-01-01'),
          _film(4, '2005-01-01', status: SeerrMediaStatus.blocklisted),
          _film(5, '2006-01-01'),
          _film(6, '2007-01-01'),
        ],
      );
      final picks = nextInSagas(
        watched: [(tmdbId: 2, title: 'Film 2'), (tmdbId: 1, title: 'Film 1')],
        collectionOfFilm: {1: 20, 2: 20},
        collections: {20: saga},
        exclude: {'movie:5'},
        now: _now,
      );
      // Film 3 isn't out, 4 is blocked, 5 excluded: 6 it is, once.
      expect(picks.map((p) => p.item.id), [6]);
    });

    test('a finished saga or a lone film suggests nothing', () {
      expect(
        nextInSagas(
          watched: [(tmdbId: 3, title: 'Film 3')],
          collectionOfFilm: {3: 10},
          collections: {10: trilogy},
          now: _now,
        ),
        isEmpty,
      );
      expect(
        nextInSagas(
          watched: [(tmdbId: 9, title: 'Alone')],
          collectionOfFilm: const {},
          collections: const {},
          now: _now,
        ),
        isEmpty,
      );
    });
  });

  group('SagaService', () {
    setUp(() => SagaService.instance.reset());

    test('asks once per film and per saga, then caches', () async {
      var detailCalls = 0;
      var collectionCalls = 0;
      Future<List<SagaPick>> load({bool force = false}) =>
          SagaService.instance.load(
            serverId: 's',
            loadWatched: () async => [
              (tmdbId: 1, title: 'Film 1'),
              (tmdbId: 7, title: 'Other'),
            ],
            collectionOf: (id) async {
              detailCalls++;
              return id == 1 ? 10 : null;
            },
            fetchCollection: (id) async {
              collectionCalls++;
              return trilogy;
            },
            forceRefresh: force,
          );

      final first = await load();
      final second = await load();
      expect(detailCalls, 2);
      expect(collectionCalls, 1);
      expect(first.single.item.id, isNot(0));
      expect(second, hasLength(first.length));

      await load(force: true);
      expect(detailCalls, 4);
    });
  });
}
