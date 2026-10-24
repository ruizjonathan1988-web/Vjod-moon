import 'package:flutter/foundation.dart';

import 'saga.dart';
import 'seerr_api_models.dart';

/// Finds the next film of the sagas the viewer is in the middle of.
///
/// Which saga a film belongs to comes from Seerr's movie details, and the
/// saga's films from its collection, so one load costs a call per recent
/// film and one per saga. Those answers barely change and are kept a while
/// per server; what to suggest is worked out fresh from them each time, so
/// a request made since drops out at once.
class SagaService {
  SagaService._();

  static final SagaService instance = SagaService._();

  static const cacheLifetime = Duration(hours: 2);

  /// Recent films looked up for a saga.
  static const maxFilms = 15;

  static const _concurrency = 4;

  final Map<String, _SagaSnapshot> _cache = {};
  final Map<String, Future<_SagaSnapshot>> _inflight = {};

  void clearCache() => _cache.clear();

  @visibleForTesting
  void reset() {
    _cache.clear();
    _inflight.clear();
  }

  Future<List<SagaPick>> load({
    required String serverId,
    required Future<List<WatchedFilm>> Function() loadWatched,
    required Future<int?> Function(int tmdbId) collectionOf,
    required Future<SeerrCollection> Function(int collectionId)
    fetchCollection,
    Set<String> exclude = const {},
    bool blockAdult = true,
    bool forceRefresh = false,
  }) async {
    final snapshot = await _snapshot(
      serverId,
      loadWatched,
      collectionOf,
      fetchCollection,
      forceRefresh,
    );
    return nextInSagas(
      watched: snapshot.watched,
      collectionOfFilm: snapshot.collectionOfFilm,
      collections: snapshot.collections,
      exclude: exclude,
      blockAdult: blockAdult,
    );
  }

  Future<_SagaSnapshot> _snapshot(
    String serverId,
    Future<List<WatchedFilm>> Function() loadWatched,
    Future<int?> Function(int tmdbId) collectionOf,
    Future<SeerrCollection> Function(int collectionId) fetchCollection,
    bool forceRefresh,
  ) {
    final cached = _cache[serverId];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.at) < cacheLifetime) {
      return Future.value(cached);
    }
    final running = _inflight[serverId];
    if (running != null) return running;
    final future = _gather(loadWatched, collectionOf, fetchCollection).then((
      snapshot,
    ) {
      _cache[serverId] = snapshot;
      return snapshot;
    });
    _inflight[serverId] = future;
    return future.whenComplete(() => _inflight.remove(serverId));
  }

  Future<_SagaSnapshot> _gather(
    Future<List<WatchedFilm>> Function() loadWatched,
    Future<int?> Function(int tmdbId) collectionOf,
    Future<SeerrCollection> Function(int collectionId) fetchCollection,
  ) async {
    final watched = await loadWatched();
    final lookups = watched.take(maxFilms).toList();

    final collectionOfFilm = <int, int>{};
    for (var start = 0; start < lookups.length; start += _concurrency) {
      await Future.wait(
        lookups.skip(start).take(_concurrency).map((film) async {
          try {
            final id = await collectionOf(film.tmdbId);
            if (id != null) collectionOfFilm[film.tmdbId] = id;
          } catch (e) {
            debugPrint('[Saga] No details for ${film.title}: $e');
          }
        }),
      );
    }

    final ids = collectionOfFilm.values.toSet().toList();
    final collections = <int, SeerrCollection>{};
    for (var start = 0; start < ids.length; start += _concurrency) {
      await Future.wait(
        ids.skip(start).take(_concurrency).map((id) async {
          try {
            collections[id] = await fetchCollection(id);
          } catch (e) {
            debugPrint('[Saga] Collection $id failed: $e');
          }
        }),
      );
    }

    return _SagaSnapshot(
      at: DateTime.now(),
      watched: watched,
      collectionOfFilm: collectionOfFilm,
      collections: collections,
    );
  }
}

class _SagaSnapshot {
  final DateTime at;
  final List<WatchedFilm> watched;
  final Map<int, int> collectionOfFilm;
  final Map<int, SeerrCollection> collections;

  const _SagaSnapshot({
    required this.at,
    required this.watched,
    required this.collectionOfFilm,
    required this.collections,
  });
}
