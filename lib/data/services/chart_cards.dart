import 'package:flutter/foundation.dart';

import '../utils/bounded_concurrency.dart';
import 'seerr/seerr_api_models.dart';

/// A chart made of TMDB ids, as the discovery cards the other charts are
/// made of.
///
/// Only the first [depth] titles are looked at. One that another chart
/// already holds reuses its card from [known], so only the rest costs a call
/// to [fetch], a few at a time so the server isn't flooded. A title whose
/// card can't be fetched is left out.
Future<List<SeerrDiscoverItem>> chartCards(
  List<int> chart, {
  required Map<int, SeerrDiscoverItem> known,
  required Future<SeerrDiscoverItem> Function(int tmdbId) fetch,
  int depth = 10,
}) async {
  Future<SeerrDiscoverItem?> cardOf(int tmdbId) async {
    final card = known[tmdbId];
    if (card != null) return card;
    try {
      return await fetch(tmdbId);
    } catch (e) {
      debugPrint('[Charts] No card for TMDB $tmdbId: $e');
      return null;
    }
  }

  final cards = await mapBounded(chart.take(depth).toList(), 4, cardOf);
  return [for (final card in cards) ?card];
}
