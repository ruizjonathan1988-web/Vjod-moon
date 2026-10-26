import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../../repositories/seerr_repository.dart';
import '../betaseries/betaseries_client.dart';
import '../chart_cards.dart';
import '../trakt/trakt_client.dart';
import 'for_you_ranker.dart';
import 'seerr_api_models.dart';

/// How many titles that only the communities (BetaSeries, Trakt) tie to a
/// seed join its list. Each one costs a call to Seerr for its card.
const _communityExtras = 4;

/// What goes with [seed]: TMDB's recommendations through Seerr, sharpened by
/// the titles BetaSeries' and Trakt's members tie to it. A title several of
/// them name moves to the front: a vote across sources.
///
/// A title both name moves to the front, and a few that only the members
/// name join the list, which brings in what TMDB rarely suggests, French
/// series above all. When BetaSeries can't help, TMDB's list stays as it is.
Future<SeerrDiscoverPage> seedRecommendations(
  SeerrRepository repo,
  TasteSeed seed,
) async {
  final isTv = seed.mediaType == 'tv';
  final community = _communityIds(repo, seed);
  final page = await (isTv
      ? repo.getTvRecommendations(seed.tmdbId)
      : repo.getMovieRecommendations(seed.tmdbId));
  final named = await community;
  if (named.isEmpty) return page;
  final listed = {for (final item in page.results) item.id};
  final extras = await chartCards(
    [
      for (final id in named)
        if (!listed.contains(id) && id != seed.tmdbId) id,
    ],
    known: const {},
    fetch: (tmdbId) => repo.getDiscoverItem(seed.mediaType, tmdbId),
    depth: _communityExtras,
  );
  return SeerrDiscoverPage(
    results: withCommunity(page.results, named, extras),
    totalPages: page.totalPages,
    totalResults: page.totalResults,
    page: page.page,
  );
}

/// What the communities tie to [seed]: BetaSeries' members and Trakt's.
/// A title both name comes first; then each one's list, taking turns.
Future<List<int>> _communityIds(SeerrRepository repo, TasteSeed seed) async {
  final lists = await Future.wait([
    _betaSeriesIds(repo, seed),
    _traktRelatedIds(seed),
  ]);
  return mergeCommunities(lists[0], lists[1]);
}

/// [a] and [b] as one list: what both name first, in [a]'s order, then the
/// rest of each, taking turns.
@visibleForTesting
List<int> mergeCommunities(List<int> a, List<int> b) {
  final inB = b.toSet();
  final both = [
    for (final id in a)
      if (inB.contains(id)) id,
  ];
  final bothSet = both.toSet();
  final restA = [
    for (final id in a)
      if (!bothSet.contains(id)) id,
  ];
  final restB = [
    for (final id in b)
      if (!bothSet.contains(id)) id,
  ];
  final out = <int>[...both];
  for (var i = 0; i < restA.length || i < restB.length; i++) {
    if (i < restA.length && !out.contains(restA[i])) out.add(restA[i]);
    if (i < restB.length && !out.contains(restB[i])) out.add(restB[i]);
  }
  return out;
}

/// What Trakt's members tie to [seed], nothing when it can't be had.
Future<List<int>> _traktRelatedIds(TasteSeed seed) async {
  if (seed.tmdbId <= 0) return const [];
  if (!GetIt.instance.isRegistered<TraktClient>()) return const [];
  try {
    return await GetIt.instance<TraktClient>().related(
      seed.mediaType,
      seed.tmdbId,
    );
  } catch (e) {
    debugPrint('[ForYou] No Trakt related for ${seed.title}: $e');
    return const [];
  }
}

/// What BetaSeries' members tie to [seed], nothing when it can't be had.
Future<List<int>> _betaSeriesIds(SeerrRepository repo, TasteSeed seed) async {
  if (!GetIt.instance.isRegistered<BetaSeriesClient>()) return const [];
  final betaSeries = GetIt.instance<BetaSeriesClient>();
  try {
    return seed.mediaType == 'tv'
        ? await betaSeries.similarShows(
            seed.tmdbId,
            tvdbIdOf: () async =>
                (await repo.getTvDetails(seed.tmdbId)).externalIds?.tvdbId,
          )
        : await betaSeries.similarMovies(seed.tmdbId);
  } catch (e) {
    debugPrint('[ForYou] No BetaSeries similars for ${seed.title}: $e');
    return const [];
  }
}

/// TMDB's list for a seed with what BetaSeries' members tie to it: the
/// titles both name first, in TMDB's order, then TMDB's others taking turns
/// with [extras], the cards of titles only the members name.
@visibleForTesting
List<SeerrDiscoverItem> withCommunity(
  List<SeerrDiscoverItem> tmdb,
  List<int> named,
  List<SeerrDiscoverItem> extras,
) {
  final ids = named.toSet();
  final confirmed = [
    for (final item in tmdb)
      if (ids.contains(item.id)) item,
  ];
  final others = [
    for (final item in tmdb)
      if (!ids.contains(item.id)) item,
  ];
  return [
    ...confirmed,
    for (var i = 0; i < others.length || i < extras.length; i++) ...[
      if (i < others.length) others[i],
      if (i < extras.length) extras[i],
    ],
  ];
}
