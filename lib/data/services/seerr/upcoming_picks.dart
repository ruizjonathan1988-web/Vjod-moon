import 'dart:math' as math;

import 'for_you_ranker.dart';
import 'seerr_api_models.dart';

/// A title still to come out, with the seed that points at it when one does.
class UpcomingPick {
  final SeerrDiscoverItem item;

  /// Seerr's media type, `movie` or `tv`.
  final String mediaType;
  final double score;

  /// The title of the viewer's history that TMDB lists it next to, or null
  /// when it comes from Seerr's upcoming lists alone.
  final TasteSeed? because;

  const UpcomingPick({
    required this.item,
    required this.mediaType,
    required this.score,
    this.because,
  });

  String get key => forYouKey(mediaType, item.id);
}

/// What is coming out in the year ahead that the viewer would want, one
/// request away before it is even out.
///
/// What TMDB lists next to the viewer's seeds leads, scored like For You.
/// Seerr's upcoming lists, each title with its media type, fill in by
/// popularity and taste, well below anything a seed vouches for.
abstract final class UpcomingPicks {
  static const horizon = Duration(days: 365);

  /// What a title from Seerr's upcoming lists alone can score at most.
  static const _listWeight = 0.2;

  static List<UpcomingPick> rank({
    required List<TasteSeed> seeds,
    required Map<String, List<SeerrDiscoverItem>> recommendationsBySeed,
    List<(SeerrDiscoverItem, String)> upcoming = const [],
    Set<String> excludeKeys = const {},
    bool blockAdult = true,
    TasteWeigher? weigh,
    DateTime? now,
    int limit = 20,
  }) {
    final today = now ?? DateTime.now();
    final seedKeys = {for (final seed in seeds) seed.key};
    final candidates = <String, _Upcoming>{};

    bool fits(SeerrDiscoverItem item, String key) =>
        !seedKeys.contains(key) &&
        !excludeKeys.contains(key) &&
        isComing(item, now: today, blockAdult: blockAdult);

    for (final seed in seeds) {
      final recs = recommendationsBySeed[seed.key];
      if (recs == null) continue;
      for (final (position, item) in recs.indexed) {
        final mediaType = item.mediaType == 'tv' || item.mediaType == 'movie'
            ? item.mediaType!
            : seed.mediaType;
        final key = forYouKey(mediaType, item.id);
        if (!fits(item, key)) continue;
        candidates
            .putIfAbsent(key, () => _Upcoming(item, mediaType))
            .vouch(seed, seed.weight / math.sqrt(position + 1));
      }
    }
    for (final (item, mediaType) in upcoming) {
      final key = forYouKey(mediaType, item.id);
      if (!fits(item, key)) continue;
      final popularity = ((item.popularity ?? 0) / 100).clamp(0.0, 1.0);
      candidates
          .putIfAbsent(key, () => _Upcoming(item, mediaType))
          .listed(_listWeight * (0.25 + 0.75 * popularity));
    }

    final scored = <UpcomingPick>[];
    for (final c in candidates.values) {
      final taste = weigh?.call(c.item, c.mediaType) ?? 1.0;
      if (taste <= 0) continue;
      scored.add(
        UpcomingPick(
          item: c.item,
          mediaType: c.mediaType,
          score: c.score * taste,
          because: c.strongest,
        ),
      );
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }

  /// Out within [horizon], with a poster, not in the library or blocked.
  /// Already requested stays in: the card's pill says so.
  static bool isComing(
    SeerrDiscoverItem item, {
    required DateTime now,
    bool blockAdult = true,
  }) {
    if (blockAdult && item.adult) return false;
    final poster = item.posterPath;
    if (poster == null || poster.isEmpty) return false;
    final status = item.mediaInfo?.status;
    if (status == SeerrMediaStatus.available ||
        status == SeerrMediaStatus.partiallyAvailable ||
        status == SeerrMediaStatus.blocklisted) {
      return false;
    }
    final date = DateTime.tryParse(item.releaseDate ?? item.firstAirDate ?? '');
    if (date == null || !date.isAfter(now)) return false;
    return !date.isAfter(now.add(horizon));
  }
}

class _Upcoming {
  final SeerrDiscoverItem item;
  final String mediaType;
  final Map<String, (TasteSeed, double)> _bySeed = {};
  double _listed = 0;

  _Upcoming(this.item, this.mediaType);

  void vouch(TasteSeed seed, double contribution) {
    final previous = _bySeed[seed.key];
    if (previous != null && previous.$2 >= contribution) return;
    _bySeed[seed.key] = (seed, contribution);
  }

  void listed(double weight) => _listed = math.max(_listed, weight);

  double get score {
    final support = _bySeed.values.fold(0.0, (sum, e) => sum + e.$2);
    final agreement = 1 + 0.35 * math.max(0, _bySeed.length - 1);
    return support * agreement + _listed;
  }

  TasteSeed? get strongest => _bySeed.isEmpty
      ? null
      : _bySeed.values.reduce((a, b) => b.$2 > a.$2 ? b : a).$1;
}
