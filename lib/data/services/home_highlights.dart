/// Small decisions behind the streaming-style touches on the home screen:
/// the Top 10 and French rows, the Surprise row and the New badge.
library;

import '../models/aggregated_item.dart';
import 'seerr/seerr_api_models.dart';

/// The titles of a Top 10, in chart order: each title once, and only what
/// has a poster to show, at most [limit] of them.
List<SeerrDiscoverItem> chartPicks(
  Iterable<SeerrDiscoverItem> chart, {
  int limit = 10,
}) {
  final picks = <SeerrDiscoverItem>[];
  final seen = <int>{};
  for (final item in chart) {
    if ((item.posterPath ?? '').isEmpty || !seen.add(item.id)) continue;
    picks.add(item);
    if (picks.length >= limit) break;
  }
  return picks;
}

/// Below this TMDB rating, a title enough people rated is popular rather
/// than good, and stays out of the Top 10.
const chartMinRating = 5.5;

/// Votes it takes before [chartMinRating] applies: a title just out has too
/// few for its rating to mean much.
const chartRatingMinVotes = 100;

/// Whether [item] deserves a place in a Top 10 on its rating.
bool isWellRated(SeerrDiscoverItem item) =>
    (item.voteCount ?? 0) < chartRatingMinVotes ||
    (item.voteAverage ?? 0) >= chartMinRating;

/// The streaming services whose charts make the Top 10, by TMDB provider id:
/// Netflix, Prime Video, Disney+, Apple TV+, Canal+, Max and Paramount+.
const chartStreamingServices = [8, 119, 337, 350, 381, 1899, 531];

/// One chart made of several, each title once.
///
/// A title earns points in every chart it is in, more the higher it ranks
/// among the first [depth], so one that tops several services comes first.
/// Ties go to the title in more charts, then to the best single rank, then
/// to the chart listed first.
List<SeerrDiscoverItem> fuseCharts(
  List<List<SeerrDiscoverItem>> charts, {
  int depth = 10,
}) {
  final points = <int, int>{};
  final count = <int, int>{};
  final best = <int, int>{};
  final first = <int, SeerrDiscoverItem>{};
  for (final chart in charts) {
    final seen = <int>{};
    for (final item in chart) {
      if (seen.length >= depth) break;
      if (!seen.add(item.id)) continue;
      final rank = seen.length - 1;
      points[item.id] = (points[item.id] ?? 0) + depth - rank;
      count[item.id] = (count[item.id] ?? 0) + 1;
      if (rank < (best[item.id] ?? depth)) best[item.id] = rank;
      first.putIfAbsent(item.id, () => item);
    }
  }
  final order = {for (final (i, id) in first.keys.indexed) id: i};
  final ids = first.keys.toList()
    ..sort((a, b) {
      final byPoints = points[b]!.compareTo(points[a]!);
      if (byPoints != 0) return byPoints;
      final byCharts = count[b]!.compareTo(count[a]!);
      if (byCharts != 0) return byCharts;
      final byRank = best[a]!.compareTo(best[b]!);
      if (byRank != 0) return byRank;
      return order[a]!.compareTo(order[b]!);
    });
  return [for (final id in ids) first[id]!];
}

/// A date the way TMDB filters on it.
String tmdbDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The release dates a "best of the year" chart looks at, as TMDB writes
/// them: the twelve months up to [now], so the chart is full in January too.
({String from, String to}) yearChartWindow(DateTime now) => (
  from: tmdbDay(DateTime(now.year - 1, now.month, now.day)),
  to: tmdbDay(now),
);

/// One list from several of a different nature, which take turns rather
/// than compete on points: the first of each, then the second of each, and
/// so on, each one once by [keyOf], itself when none is given.
List<T> takeTurns<T>(List<List<T>> lists, {Object? Function(T item)? keyOf}) {
  final row = <T>[];
  final seen = <Object?>{};
  final longest = lists.fold<int>(0, (m, l) => l.length > m ? l.length : m);
  for (var i = 0; i < longest; i++) {
    for (final list in lists) {
      if (i >= list.length) continue;
      final item = list[i];
      if (seen.add(keyOf == null ? item : keyOf(item))) row.add(item);
    }
  }
  return row;
}

/// What tells one title from another in a chart: its TMDB id.
Object tmdbKey(SeerrDiscoverItem item) => item.id;

/// One way a film came out, as TMDB records it: [type] 1 premiere, 2 and 3
/// cinemas, 4 digital, 5 disc, 6 television.
typedef FilmRelease = ({int type, DateTime date});

/// The release dates in a film's details from Seerr, every country together.
List<FilmRelease> parseFilmReleases(Map<String, dynamic> details) {
  final releases = details['releases'];
  final countries = releases is Map ? releases['results'] : null;
  if (countries is! List) return const [];
  return [
    for (final country in countries)
      if (country is Map && country['release_dates'] is List)
        for (final release in country['release_dates'] as List)
          if (release is Map &&
              release['type'] is int &&
              DateTime.tryParse('${release['release_date']}') != null)
            (
              type: release['type'] as int,
              date: DateTime.parse('${release['release_date']}'),
            ),
  ];
}

/// How long after cinemas a film can be watched at home in France, when
/// TMDB has no digital date for it.
const cinemaToHome = Duration(days: 120);

/// Whether a film with [releases] can be watched at home by [now]: out on
/// digital, disc or television somewhere, or in cinemas long enough ago.
/// A film with no dates at all is given the benefit of the doubt.
bool isOutAtHome(List<FilmRelease> releases, DateTime now) {
  if (releases.isEmpty) return true;
  for (final release in releases) {
    if (release.date.isAfter(now)) continue;
    if (release.type >= 4) return true;
    if ((release.type == 2 || release.type == 3) &&
        now.difference(release.date) >= cinemaToHome) {
      return true;
    }
  }
  return false;
}

/// How long a title counts as new on its card.
const freshlyAddedWindow = Duration(days: 10);

/// Whether a card gets the New badge: a movie or episode added lately that
/// nobody started yet. Series are left out, since adding an episode doesn't
/// date the series itself.
bool isFreshlyAdded(AggregatedItem item, {DateTime? now}) {
  final type = item.type;
  if (type != 'Movie' && type != 'Episode') return false;
  // A file the server couldn't identify has no poster and no series: a
  // loose download, not something new to watch.
  if (type == 'Movie' && item.primaryImageTag == null) return false;
  if (type == 'Episode' && item.rawData['SeriesId'] == null) return false;
  if (item.isPlayed) return false;
  if ((item.playedPercentage ?? 0) > 0) return false;
  final created = item.dateCreated;
  if (created == null) return false;
  final age = (now ?? DateTime.now()).difference(created);
  return !age.isNegative && age <= freshlyAddedWindow;
}

/// The first well-rated title of a random draw, or the first one at all
/// when none is, so the Surprise row has something to offer.
AggregatedItem? pickSurprise(
  List<AggregatedItem> randomDraw, {
  double minRating = 6.5,
}) {
  for (final item in randomDraw) {
    if ((item.communityRating ?? 0) >= minRating) return item;
  }
  return randomDraw.isEmpty ? null : randomDraw.first;
}

/// Genre names a family film can carry. The server names genres in its
/// metadata language, so English and French both appear.
const familyGenreNames = [
  'Family',
  'Familial',
  'Famille',
  'Animation',
  'Kids',
  'Children',
  'Jeunesse',
];

/// Family night: unwatched family films, best rated first among a random
/// draw so the row changes from one evening to the next.
List<AggregatedItem> pickFamilyNight(
  List<AggregatedItem> randomDraw, {
  int limit = 15,
  double minRating = 6.0,
}) {
  final seen = <String>{};
  final rated = <AggregatedItem>[];
  final rest = <AggregatedItem>[];
  for (final item in randomDraw) {
    if (!seen.add(item.id)) continue;
    if (item.primaryImageTag == null) continue;
    if ((item.communityRating ?? 0) >= minRating) {
      rated.add(item);
    } else {
      rest.add(item);
    }
  }
  rated.sort(
    (a, b) => (b.communityRating ?? 0).compareTo(a.communityRating ?? 0),
  );
  return [...rated, ...rest].take(limit).toList();
}
