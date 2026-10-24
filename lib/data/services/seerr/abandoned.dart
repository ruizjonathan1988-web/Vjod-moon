import 'dart:math' as math;

/// Titles the viewer started and walked away from: a film stopped early and
/// left for two weeks, a series dropped after its first episodes and left
/// for three. They say what the viewer doesn't want, so they shouldn't seed
/// recommendations, and what TMDB lists next to them counts against a title.
abstract final class Abandoned {
  static const movieAfter = Duration(days: 14);
  static const seriesAfter = Duration(days: 21);

  /// Past this share of a film, stopping is more likely a forgotten ending
  /// than a verdict.
  static const movieMaxPercent = 50.0;

  /// A series counts as dropped when no more than this share was watched
  /// and at least [seriesMinLeft] episodes were left.
  static const seriesMaxPercent = 30.0;
  static const seriesMinLeft = 3;

  /// How many abandoned titles get a Seerr call for what goes with them.
  static const maxLookups = 4;

  /// Whether a film in progress, from its Jellyfin user data, was left.
  static bool movie(Map<String, dynamic>? userData, DateTime now) {
    if (userData == null || userData['IsFavorite'] == true) return false;
    if (userData['Played'] == true) return false;
    final percent = (userData['PlayedPercentage'] as num?)?.toDouble() ?? 0;
    if (percent <= 0 || percent >= movieMaxPercent) return false;
    return _leftSince(userData['LastPlayedDate'], now, movieAfter);
  }

  /// Whether a started series, from its Jellyfin user data, was dropped.
  /// [lastEpisode] is when one of its episodes was last played, for servers
  /// that don't date the series itself.
  static bool series(
    Map<String, dynamic>? userData,
    DateTime now, {
    DateTime? lastEpisode,
  }) {
    if (userData == null || userData['IsFavorite'] == true) return false;
    final percent = (userData['PlayedPercentage'] as num?)?.toDouble() ?? 0;
    if (percent <= 0 || percent > seriesMaxPercent) return false;
    final left = (userData['UnplayedItemCount'] as num?)?.toInt() ?? 0;
    if (left < seriesMinLeft) return false;
    final own = DateTime.tryParse(userData['LastPlayedDate']?.toString() ?? '');
    final last = own == null || (lastEpisode?.isAfter(own) ?? false)
        ? lastEpisode
        : own;
    // Not dated at all and missing from the recent plays: long ago.
    if (last == null) return true;
    return now.difference(last) >= seriesAfter;
  }

  static bool _leftSince(Object? date, DateTime now, Duration after) {
    final last = DateTime.tryParse(date?.toString() ?? '');
    if (last == null) return false;
    return now.difference(last) >= after;
  }

  /// A factor on each candidate's score, by [forYouKey]-style key, from what
  /// TMDB lists next to the abandoned titles. Listed first next to one of
  /// them costs 40%; further down the list costs less; two abandoned titles
  /// agreeing cost more, never below [floor].
  static Map<String, double> penalties(
    Iterable<List<(String key, int position)>> listsByAbandoned, {
    double floor = 0.35,
  }) {
    final factors = <String, double>{};
    for (final list in listsByAbandoned) {
      final seen = <String>{};
      for (final (key, position) in list) {
        if (!seen.add(key)) continue;
        final cost = 0.4 / math.sqrt(position + 1);
        final next = (factors[key] ?? 1) * (1 - cost);
        factors[key] = next < floor ? floor : next;
      }
    }
    return factors;
  }
}
