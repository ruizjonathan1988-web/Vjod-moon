import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../../repositories/seerr_repository.dart';
import '../betaseries/betaseries_client.dart';
import '../chart_cards.dart';
import 'for_you_ranker.dart';
import 'seerr_api_models.dart';

/// How many titles that only BetaSeries' members tie to a seed join its
/// list. Each one costs a call to Seerr for its card.
const _communityExtras = 3;

/// What goes with [seed]: TMDB's recommendations through Seerr, sharpened by
/// the titles BetaSeries' members tie to it.
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

/// What BetaSeries' members tie to [seed], nothing when it can't be had.
Future<List<int>> _communityIds(SeerrRepository repo, TasteSeed seed) async {
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
