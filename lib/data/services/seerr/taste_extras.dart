import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../../repositories/seerr_repository.dart';
import '../chart_cards.dart';
import '../trakt/trakt_account.dart';
import 'for_you_ranker.dart';
import 'for_you_service.dart';
import 'seerr_api_models.dart';
import 'taste_profile.dart';

/// Picked favourites, the Seerr watchlist and the viewer's own requests,
/// as interest the watch history can't show, and Trakt's recommendations
/// when an account is linked.
Future<TasteExtras> loadTasteExtras(
  SeerrRepository repo,
  TasteProfile profile,
) async {
  final picked = [
    // An all-time favourite says three times what a liked title says.
    for (final pick in profile.pivots)
      TasteSignal(
        tmdbId: pick.tmdbId,
        mediaType: pick.mediaType,
        title: pick.title,
        strength: 3,
      ),
    for (final pick in profile.favorites)
      TasteSignal(
        tmdbId: pick.tmdbId,
        mediaType: pick.mediaType,
        title: pick.title,
      ),
  ];

  Future<List<TasteSignal>> watchlist() async {
    try {
      final page = await repo.getWatchlist(page: 1);
      return [
        for (final item in page.results)
          if (item.mediaType == 'movie' || item.mediaType == 'tv')
            TasteSignal(
              tmdbId: item.id,
              mediaType: item.mediaType!,
              title: item.displayTitle,
            ),
      ];
    } catch (e) {
      debugPrint('[ForYou] Watchlist signals failed: $e');
      return const [];
    }
  }

  Future<List<TasteSignal>> requested() async {
    try {
      final user = await repo.getCurrentUser();
      final response = await repo.getRequests(requestedBy: user.id, limit: 30);
      final now = DateTime.now();
      return [
        for (final request in response.results)
          if (request.status != SeerrRequest.statusDeclined &&
              request.media?.tmdbId != null)
            TasteSignal(
              tmdbId: request.media!.tmdbId!,
              mediaType: request.type == 'tv' ? 'tv' : 'movie',
              title: request.media!.title ?? request.media!.name ?? '',
              strength: ForYouRanker.requestStrength(
                status: request.media!.status,
                availableSince: request.media!.mediaAddedAt,
                now: now,
              ),
            ),
      ];
    } catch (e) {
      debugPrint('[ForYou] Request signals failed: $e');
      return const [];
    }
  }

  Future<List<SeerrDiscoverItem>> traktPicks() async {
    final trakt = GetIt.instance.isRegistered<TraktAccount>()
        ? GetIt.instance<TraktAccount>()
        : null;
    if (trakt == null || !trakt.isConnected) return const [];
    try {
      final [movies, series] = await Future.wait([
        for (final mediaType in const ['movie', 'tv'])
          trakt
              .recommendations(mediaType)
              .then(
                (ids) => chartCards(
                  ids,
                  known: const {},
                  fetch: (tmdbId) => repo.getDiscoverItem(mediaType, tmdbId),
                ),
              ),
      ]);
      // Films and series take turns, so neither crowds out the other.
      return [
        for (var i = 0; i < movies.length || i < series.length; i++) ...[
          if (i < movies.length) movies[i],
          if (i < series.length) series[i],
        ],
      ];
    } catch (e) {
      debugPrint('[ForYou] Trakt recommendations failed: $e');
      return const [];
    }
  }

  final (watchlistSignals, requestedSignals, suggestedByTrakt) = await (
    watchlist(),
    requested(),
    traktPicks(),
  ).wait;
  return TasteExtras(
    picked: picked,
    watchlist: watchlistSignals,
    requested: requestedSignals,
    traktPicks: suggestedByTrakt,
  );
}
