import 'package:flutter/foundation.dart';

import '../../models/aggregated_item.dart';
import 'abandoned.dart';
import 'for_you_ranker.dart';
import 'seerr_api_models.dart';

/// What the library says about the viewer: what they watched, newest
/// first, what they marked as favourite, and what they gave up on.
typedef TasteHistory = ({
  List<AggregatedItem> recent,
  List<AggregatedItem> favorites,
  List<AggregatedItem> abandoned,
});

/// Builds the For You row: the viewer's history goes in, titles to request
/// come out.
///
/// The result is kept for a while per server, since every load costs one
/// Seerr call per seed and the home screen reloads often.
class ForYouService {
  ForYouService._();

  static final ForYouService instance = ForYouService._();

  static const cacheLifetime = Duration(minutes: 30);

  /// Seerr calls running at once while gathering recommendations.
  static const _concurrency = 4;

  final Map<String, _Snapshot> _cache = {};

  /// Loads under way, so the For You and Because rows loading side by side
  /// share one round of Seerr calls.
  final Map<String, Future<_Snapshot>> _inflight = {};

  /// Titles requested from the row this session. Seerr reports them as
  /// requested soon enough, but until the next fetch they'd come back.
  final Set<String> _requested = {};

  /// Counts the requests made this session, for the home screen to mark
  /// the cards it already shows.
  final ValueNotifier<int> requestedChanges = ValueNotifier(0);

  /// The titles requested this session, as [forYouKey] keys.
  Set<String> get requestedKeys => Set.unmodifiable(_requested);

  /// Remembers a request so the title stays out of For You and shows as
  /// requested on the cards already drawn.
  void markRequested(String mediaType, int tmdbId) {
    if (_requested.add(forYouKey(mediaType, tmdbId))) {
      requestedChanges.value++;
    }
  }

  void clearCache() => _cache.clear();

  @visibleForTesting
  void reset() {
    _cache.clear();
    _inflight.clear();
    _requested.clear();
  }

  Future<List<ForYouPick>> load({
    required String serverId,
    required Future<TasteHistory> Function()
    loadHistory,
    required Future<SeerrDiscoverPage> Function(TasteSeed seed)
    fetchRecommendations,
    Future<TasteExtras> Function()? loadExtras,
    TasteWeigher? weigh,
    Set<String> hidden = const {},
    bool blockAdult = true,
    bool forceRefresh = false,
    int limit = 30,
  }) async {
    final snapshot = await _snapshot(
      serverId: serverId,
      loadHistory: loadHistory,
      fetchRecommendations: fetchRecommendations,
      loadExtras: loadExtras,
      forceRefresh: forceRefresh,
    );
    if (snapshot.seeds.isEmpty) return const [];
    return ForYouRanker.rank(
      seeds: snapshot.seeds,
      recommendationsBySeed: snapshot.recommendations,
      excludeKeys: {..._requested, ...hidden, ...snapshot.abandoned},
      blockAdult: blockAdult,
      limit: limit,
      weigh: snapshot.weigh(weigh),
    );
  }

  /// "Because you watched" rows from the same history and recommendations
  /// as [load], without asking Seerr again.
  Future<List<BecauseRow>> loadBecauseRows({
    required String serverId,
    required Future<TasteHistory> Function()
    loadHistory,
    required Future<SeerrDiscoverPage> Function(TasteSeed seed)
    fetchRecommendations,
    Future<TasteExtras> Function()? loadExtras,
    TasteWeigher? weigh,
    Set<String> hidden = const {},
    bool blockAdult = true,
    bool forceRefresh = false,
    int rows = 2,
  }) async {
    final snapshot = await _snapshot(
      serverId: serverId,
      loadHistory: loadHistory,
      fetchRecommendations: fetchRecommendations,
      loadExtras: loadExtras,
      forceRefresh: forceRefresh,
    );
    if (snapshot.seeds.isEmpty) return const [];
    final exclude = {..._requested, ...hidden, ...snapshot.abandoned};
    final weighed = snapshot.weigh(weigh);
    // What leads the For You row stays there, so the same poster doesn't
    // show twice on one screen.
    final forYouLead = ForYouRanker.rank(
      seeds: snapshot.seeds,
      recommendationsBySeed: snapshot.recommendations,
      excludeKeys: exclude,
      blockAdult: blockAdult,
      limit: forYouLeadCount,
      weigh: weighed,
    );
    return ForYouRanker.becauseRows(
      seeds: snapshot.seeds,
      recommendationsBySeed: snapshot.recommendations,
      excludeKeys: {...exclude, for (final pick in forYouLead) pick.key},
      blockAdult: blockAdult,
      rows: rows,
      weigh: weighed,
    );
  }

  /// Hidden gems from the same recommendations, minus what the For You
  /// lead and the Because rows already show.
  Future<List<ForYouPick>> loadGems({
    required String serverId,
    required Future<TasteHistory> Function()
    loadHistory,
    required Future<SeerrDiscoverPage> Function(TasteSeed seed)
    fetchRecommendations,
    Future<TasteExtras> Function()? loadExtras,
    TasteWeigher? weigh,
    Set<String> hidden = const {},
    bool blockAdult = true,
    bool forceRefresh = false,
  }) async {
    final snapshot = await _snapshot(
      serverId: serverId,
      loadHistory: loadHistory,
      fetchRecommendations: fetchRecommendations,
      loadExtras: loadExtras,
      forceRefresh: forceRefresh,
    );
    if (snapshot.seeds.isEmpty) return const [];
    final exclude = {..._requested, ...hidden, ...snapshot.abandoned};
    final weighed = snapshot.weigh(weigh);
    final forYouLead = ForYouRanker.rank(
      seeds: snapshot.seeds,
      recommendationsBySeed: snapshot.recommendations,
      excludeKeys: exclude,
      blockAdult: blockAdult,
      limit: forYouLeadCount,
      weigh: weighed,
    );
    final leadKeys = {for (final pick in forYouLead) pick.key};
    final because = ForYouRanker.becauseRows(
      seeds: snapshot.seeds,
      recommendationsBySeed: snapshot.recommendations,
      excludeKeys: {...exclude, ...leadKeys},
      blockAdult: blockAdult,
      weigh: weighed,
    );
    return ForYouRanker.gems(
      seeds: snapshot.seeds,
      recommendationsBySeed: snapshot.recommendations,
      excludeKeys: {
        ...exclude,
        ...leadKeys,
        for (final row in because)
          for (final item in row.items) item.key,
      },
      blockAdult: blockAdult,
      weigh: weighed,
    );
  }

  /// The seeds and what TMDB recommends next to each, as the rows see them,
  /// for anything that ranks on its own terms (Tonight), with the titles to
  /// keep out: requested this session or given up on.
  Future<
    ({
      List<TasteSeed> seeds,
      Map<String, List<SeerrDiscoverItem>> recommendations,
      Set<String> exclude,
    })
  >
  loadRaw({
    required String serverId,
    required Future<TasteHistory> Function()
    loadHistory,
    required Future<SeerrDiscoverPage> Function(TasteSeed seed)
    fetchRecommendations,
    Future<TasteExtras> Function()? loadExtras,
    bool forceRefresh = false,
  }) async {
    final snapshot = await _snapshot(
      serverId: serverId,
      loadHistory: loadHistory,
      fetchRecommendations: fetchRecommendations,
      loadExtras: loadExtras,
      forceRefresh: forceRefresh,
    );
    return (
      seeds: snapshot.seeds,
      recommendations: snapshot.recommendations,
      exclude: {..._requested, ...snapshot.abandoned},
    );
  }

  /// How many For You picks the Because rows leave alone: about what a
  /// screen shows before scrolling the row.
  static const forYouLeadCount = 10;

  Future<_Snapshot> _snapshot({
    required String serverId,
    required Future<TasteHistory> Function()
    loadHistory,
    required Future<SeerrDiscoverPage> Function(TasteSeed seed)
    fetchRecommendations,
    Future<TasteExtras> Function()? loadExtras,
    required bool forceRefresh,
  }) {
    final cached = _cache[serverId];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.at) < cacheLifetime) {
      return Future.value(cached);
    }
    final running = _inflight[serverId];
    if (running != null) return running;
    final future = _gather(
      loadHistory,
      fetchRecommendations,
      loadExtras,
    ).then((snapshot) {
      _cache[serverId] = snapshot;
      return snapshot;
    });
    _inflight[serverId] = future;
    return future.whenComplete(() => _inflight.remove(serverId));
  }

  Future<_Snapshot> _gather(
    Future<TasteHistory> Function()
    loadHistory,
    Future<SeerrDiscoverPage> Function(TasteSeed seed) fetchRecommendations,
    Future<TasteExtras> Function()? loadExtras,
  ) async {
    final results = await Future.wait([
      loadHistory(),
      if (loadExtras != null)
        loadExtras().catchError((Object e) {
          // Extras sharpen the row; without them it still works.
          debugPrint('[ForYou] Extra taste signals failed: $e');
          return TasteExtras.none;
        }),
    ]);
    final history = results[0] as TasteHistory;
    final extras = results.length > 1
        ? results[1] as TasteExtras
        : TasteExtras.none;
    final abandoned = signalsFrom(history.abandoned);
    final dropped = {for (final signal in abandoned) signal.key};
    List<TasteSignal> kept(List<AggregatedItem> items) => [
      for (final signal in signalsFrom(items))
        if (!dropped.contains(signal.key)) signal,
    ];
    final seeds = ForYouRanker.buildSeeds(
      recent: kept(history.recent),
      favorites: kept(history.favorites),
      picked: extras.picked,
      watchlist: extras.watchlist,
      requested: extras.requested,
    );

    final recommendations = <String, List<SeerrDiscoverItem>>{};
    for (var start = 0; start < seeds.length; start += _concurrency) {
      final batch = seeds.skip(start).take(_concurrency);
      await Future.wait(
        batch.map((seed) async {
          try {
            final page = await fetchRecommendations(seed);
            recommendations[seed.key] = page.results;
          } catch (e) {
            // One title TMDB doesn't know shouldn't sink the whole row.
            debugPrint('[ForYou] No recommendations for ${seed.title}: $e');
          }
        }),
      );
    }
    // Trakt's picks need no call per seed: they join as one more seed.
    final withTrakt = extras.traktPicks.isEmpty
        ? seeds
        : [...seeds, ForYouRanker.traktSeed];
    if (extras.traktPicks.isNotEmpty) {
      recommendations[ForYouRanker.traktSeed.key] = extras.traktPicks;
    }
    return _Snapshot(
      at: DateTime.now(),
      seeds: withTrakt,
      recommendations: recommendations,
      abandoned: dropped,
      penalties: await _penalties(abandoned, fetchRecommendations),
    );
  }

  /// What TMDB lists next to the titles the viewer gave up on, as a factor
  /// on each candidate's score.
  static Future<Map<String, double>> _penalties(
    List<TasteSignal> abandoned,
    Future<SeerrDiscoverPage> Function(TasteSeed seed) fetchRecommendations,
  ) async {
    final lists = await Future.wait(
      abandoned.take(Abandoned.maxLookups).map((signal) async {
        try {
          final page = await fetchRecommendations(
            TasteSeed(
              tmdbId: signal.tmdbId,
              mediaType: signal.mediaType,
              title: signal.title,
              weight: 0,
            ),
          );
          return [
            for (final (position, item) in page.results.indexed)
              (forYouKey(item.mediaType ?? signal.mediaType, item.id), position),
          ];
        } catch (e) {
          debugPrint('[ForYou] No recommendations for ${signal.title}: $e');
          return const <(String, int)>[];
        }
      }),
    );
    return Abandoned.penalties(lists);
  }

  /// Library items that carry a TMDB id, as signals Seerr can look up.
  @visibleForTesting
  static List<TasteSignal> signalsFrom(List<AggregatedItem> items) => [
    for (final item in items)
      if (_signalFrom(item) case final signal?) signal,
  ];

  static TasteSignal? _signalFrom(AggregatedItem item) {
    final tmdbId = int.tryParse(item.tmdbId ?? '');
    if (tmdbId == null || tmdbId <= 0) return null;
    final mediaType = switch (item.type) {
      'Movie' => 'movie',
      'Series' => 'tv',
      _ => null,
    };
    if (mediaType == null) return null;
    final userData = item.rawData['UserData'];
    final plays = userData is Map ? (userData['PlayCount'] as num?) ?? 0 : 0;
    return TasteSignal(
      tmdbId: tmdbId,
      mediaType: mediaType,
      title: item.name,
      // Watched more than once: it clearly landed.
      strength: plays >= 2 ? 1.35 : 1,
    );
  }
}

/// What one round of Seerr calls brought back, for every row built on it.
class _Snapshot {
  final DateTime at;
  final List<TasteSeed> seeds;
  final Map<String, List<SeerrDiscoverItem>> recommendations;

  /// The titles the viewer gave up on, as [forYouKey] keys.
  final Set<String> abandoned;

  /// A factor below 1 for titles that go with what the viewer gave up on.
  final Map<String, double> penalties;

  const _Snapshot({
    required this.at,
    required this.seeds,
    required this.recommendations,
    this.abandoned = const {},
    this.penalties = const {},
  });

  /// [weigh] with the penalties on top.
  TasteWeigher? weigh(TasteWeigher? weigh) {
    if (penalties.isEmpty) return weigh;
    return (item, mediaType) =>
        (weigh?.call(item, mediaType) ?? 1.0) *
        (penalties[forYouKey(mediaType, item.id)] ?? 1.0);
  }
}

/// Interest the library's history doesn't hold: titles picked in the taste
/// questionnaire, on the Seerr watchlist, or requested, and what Trakt
/// recommends when an account is linked.
class TasteExtras {
  final List<TasteSignal> picked;
  final List<TasteSignal> watchlist;
  final List<TasteSignal> requested;

  /// Trakt's recommendations, best first, ready to rank rather than seeds.
  final List<SeerrDiscoverItem> traktPicks;

  const TasteExtras({
    this.picked = const [],
    this.watchlist = const [],
    this.requested = const [],
    this.traktPicks = const [],
  });

  static const none = TasteExtras();
}
