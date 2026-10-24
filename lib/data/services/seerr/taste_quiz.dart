import 'dart:math' as math;

import 'seerr_api_models.dart';
import 'taste_profile.dart';

/// A title the questionnaire shows: a poster to rate or to pick in a duel.
class QuizTitle {
  final int tmdbId;

  /// `movie` or `tv`.
  final String mediaType;
  final String title;
  final String? posterPath;
  final Set<TasteGenre> genres;
  final int? year;
  final double rating;
  final int votes;
  final String? language;

  /// A full image URL, for titles the library knows rather than TMDB.
  final String? imageUrl;

  const QuizTitle({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.posterPath,
    this.genres = const {},
    this.year,
    this.rating = 0,
    this.votes = 0,
    this.language,
    this.imageUrl,
  });

  String get key => '$mediaType:$tmdbId';

  bool get isMovie => mediaType == 'movie';

  /// Well known yet splitting opinion: many votes for a middling average.
  bool get divisive => votes >= 2000 && rating >= 6.0 && rating <= 7.4;

  TastePick toPick() => TastePick(
    tmdbId: tmdbId,
    mediaType: mediaType,
    title: title,
    posterPath: posterPath,
    genres: genres,
  );

  static QuizTitle? fromSeerr(SeerrDiscoverItem item, {String? type}) {
    final mediaType = item.mediaType ?? type;
    if (mediaType != 'movie' && mediaType != 'tv') return null;
    final poster = item.posterPath;
    if (poster == null || poster.isEmpty) return null;
    final date = mediaType == 'tv' ? item.firstAirDate : item.releaseDate;
    return QuizTitle(
      tmdbId: item.id,
      mediaType: mediaType!,
      title: item.displayTitle,
      posterPath: poster,
      genres: TasteGenre.of(item.genreIds, mediaType),
      year: date != null && date.length >= 4
          ? int.tryParse(date.substring(0, 4))
          : null,
      rating: item.voteAverage ?? 0,
      votes: item.voteCount ?? 0,
      language: item.originalLanguage,
    );
  }
}

/// How familiar the next posters should be.
enum QuizFamiliarity {
  /// The viewer knows few of them: only the most famous.
  famous,
  normal,

  /// The viewer has seen nearly everything: dig deeper.
  deeper,
}

/// What the grid answers so far say about where to go next.
class QuizSoFar {
  final List<QuizTitle> liked;
  final List<QuizTitle> meh;
  final List<QuizTitle> disliked;
  final int unseen;

  const QuizSoFar({
    this.liked = const [],
    this.meh = const [],
    this.disliked = const [],
    this.unseen = 0,
  });

  int get shown => liked.length + meh.length + disliked.length + unseen;

  QuizFamiliarity get familiarity {
    if (shown == 0) return QuizFamiliarity.normal;
    final seenShare = 1 - unseen / shown;
    if (seenShare < 0.4) return QuizFamiliarity.famous;
    if (seenShare > 0.8) return QuizFamiliarity.deeper;
    return QuizFamiliarity.normal;
  }

  /// Genres turned down twice or more: no use showing more of them.
  Set<TasteGenre> get exhaustedGenres {
    final count = <TasteGenre, int>{};
    for (final title in disliked) {
      for (final genre in title.genres) {
        count[genre] = (count[genre] ?? 0) + 1;
      }
    }
    return {
      for (final e in count.entries)
        if (e.value >= 2) e.key,
    };
  }
}

/// Picks a page of posters to rate.
///
/// The first page covers ground on purpose: several kinds of genre, three
/// decades with one before 2000, French and other non-English titles,
/// animation and series. Later pages lean on what the earlier ones said:
/// next to each title liked, something of another genre or decade from its
/// recommendations, then the rest of the pool by how famous it is.
List<QuizTitle> pickGridPage({
  required List<QuizTitle> pool,
  int count = 8,
  Set<String> exclude = const {},
  TasteMediaPref mediaPref = TasteMediaPref.both,
  Set<TasteGenre> avoided = const {},
  QuizSoFar soFar = const QuizSoFar(),
  Map<String, List<QuizTitle>> recommendationsOfLiked = const {},
  DateTime? now,
  math.Random? random,
}) {
  final thisYear = (now ?? DateTime.now()).year;
  final blocked = {...avoided, ...soFar.exhaustedGenres};
  final familiarity = soFar.familiarity;

  bool usable(QuizTitle t) {
    if (exclude.contains(t.key)) return false;
    if (t.genres.any(blocked.contains)) return false;
    if (mediaPref == TasteMediaPref.movies && !t.isMovie) return false;
    if (mediaPref == TasteMediaPref.series && t.isMovie) return false;
    return switch (familiarity) {
      QuizFamiliarity.famous => t.votes >= 5000 || (!t.isMovie && t.votes >= 1500),
      QuizFamiliarity.normal => true,
      QuizFamiliarity.deeper => true,
    };
  }

  final candidates = pool.where(usable).toList()
    ..sort((a, b) {
      if (familiarity == QuizFamiliarity.deeper) {
        // Past the blockbusters: well rated, a little less voted.
        final ra = a.rating * math.log(1 + a.votes) / (a.votes > 20000 ? 2 : 1);
        final rb = b.rating * math.log(1 + b.votes) / (b.votes > 20000 ? 2 : 1);
        return rb.compareTo(ra);
      }
      return b.votes.compareTo(a.votes);
    });

  final page = <QuizTitle>[];
  final covered = <TasteGenre>{};
  bool taken(QuizTitle t) => page.any((p) => p.key == t.key);

  void take(QuizTitle t) {
    page.add(t);
    covered.addAll(t.genres);
  }

  /// The first candidate that meets [rule], preferring one that brings a
  /// genre not on the page yet.
  void satisfy(bool Function(QuizTitle) rule) {
    if (page.length >= count) return;
    QuizTitle? fallback;
    for (final t in candidates) {
      if (taken(t) || !rule(t)) continue;
      if (!t.genres.every(covered.contains)) {
        take(t);
        return;
      }
      fallback ??= t;
    }
    if (fallback != null) take(fallback);
  }

  // Next to what was liked: a neighbour of another genre or decade.
  for (final liked in soFar.liked) {
    final recs = recommendationsOfLiked[liked.key];
    if (recs == null) continue;
    if (page.length >= count ~/ 2) break;
    for (final rec in recs) {
      if (!usable(rec) || taken(rec)) continue;
      final otherGenre = rec.genres.isNotEmpty &&
          !rec.genres.every(liked.genres.contains);
      final otherDecade = rec.year != null &&
          liked.year != null &&
          (rec.year! ~/ 10) != (liked.year! ~/ 10);
      if (otherGenre || otherDecade) {
        take(rec);
        break;
      }
    }
  }

  if (soFar.shown == 0) {
    satisfy((t) => t.year != null && t.year! < 2000);
    satisfy((t) => t.language == 'fr');
    satisfy((t) => t.language != null && t.language != 'en' && t.language != 'fr');
    satisfy((t) => t.genres.contains(TasteGenre.animation));
    if (mediaPref != TasteMediaPref.movies) {
      satisfy((t) => !t.isMovie);
      satisfy((t) => !t.isMovie);
    }
    satisfy((t) => t.year != null && t.year! >= 2000 && t.year! < 2015);
    satisfy((t) => t.year != null && t.year! >= thisYear - 6);
  }
  // About one in three splits opinion: that is where answers say most.
  final divisiveTarget = (count / 3).floor();
  var divisive = page.where((t) => t.divisive).length;
  while (divisive < divisiveTarget && page.length < count) {
    final before = page.length;
    satisfy((t) => t.divisive);
    if (page.length == before) break;
    divisive++;
  }
  // The rest: new genres first, then simply the most famous.
  while (page.length < count) {
    final before = page.length;
    satisfy((_) => true);
    if (page.length == before) break;
  }

  if (random != null) page.shuffle(random);
  return page;
}

/// Two posters opposed on one axis of taste.
class QuizDuel {
  final TasteAxis axis;

  /// The first pole's title.
  final QuizTitle left;

  /// The second pole's title.
  final QuizTitle right;

  const QuizDuel(this.axis, this.left, this.right);
}

/// Builds a duel for [axis] from well-known titles: one clearly on each side,
/// alike otherwise where possible.
QuizDuel? buildDuel(
  TasteAxis axis, {
  required List<QuizTitle> pool,
  Set<String> used = const {},
  Set<TasteGenre> avoided = const {},
  DateTime? now,
}) {
  final thisYear = (now ?? DateTime.now()).year;
  bool has(QuizTitle t, Set<TasteGenre> set) => t.genres.any(set.contains);
  const dark = {
    TasteGenre.horror,
    TasteGenre.thriller,
    TasteGenre.crime,
    TasteGenre.war,
  };
  const light = {TasteGenre.comedy, TasteGenre.family, TasteGenre.animation};
  const real = {
    TasteGenre.documentary,
    TasteGenre.history,
    TasteGenre.drama,
    TasteGenre.crime,
  };
  const imaginary = {TasteGenre.fantasy, TasteGenre.scifi};
  const fast = {TasteGenre.action, TasteGenre.thriller};
  const spectacle = {TasteGenre.adventure, TasteGenre.action, TasteGenre.scifi};
  const intimate = {TasteGenre.drama, TasteGenre.romance};

  final (bool Function(QuizTitle) first, bool Function(QuizTitle) second) =
      switch (axis) {
        TasteAxis.darkLight => (
          (QuizTitle t) => has(t, dark) && !t.genres.contains(TasteGenre.comedy),
          (QuizTitle t) => has(t, light) && !has(t, dark),
        ),
        TasteAxis.realImaginary => (
          (QuizTitle t) => has(t, real) && !has(t, {...imaginary, TasteGenre.animation}),
          (QuizTitle t) => has(t, imaginary),
        ),
        TasteAxis.slowFast => (
          (QuizTitle t) =>
              t.genres.contains(TasteGenre.drama) &&
              !has(t, {...fast, TasteGenre.adventure}) &&
              t.rating >= 7.2,
          (QuizTitle t) => has(t, fast),
        ),
        TasteAxis.recentClassic => (
          (QuizTitle t) => t.year != null && t.year! >= thisYear - 5,
          (QuizTitle t) => t.year != null && t.year! <= thisYear - 30,
        ),
        TasteAxis.popularNiche => (
          (QuizTitle t) => t.votes >= 15000,
          (QuizTitle t) => t.votes >= 300 && t.votes <= 2500 && t.rating >= 7.2,
        ),
        TasteAxis.spectacleIntimate => (
          (QuizTitle t) => has(t, spectacle) && t.votes >= 5000,
          (QuizTitle t) => has(t, intimate) && !has(t, spectacle),
        ),
      };

  final candidates = pool
      .where(
        (t) =>
            t.isMovie &&
            !used.contains(t.key) &&
            !t.genres.any(avoided.contains),
      )
      .toList()
    ..sort((a, b) => b.votes.compareTo(a.votes));

  QuizTitle? left;
  for (final t in candidates) {
    if (first(t) && !second(t)) {
      left = t;
      break;
    }
  }
  if (left == null) return null;
  final anchor = left;

  bool alike(QuizTitle t) {
    final sharesGenre = t.genres.any(anchor.genres.contains);
    final closeInTime =
        axis == TasteAxis.recentClassic ||
        (t.year != null &&
            anchor.year != null &&
            (t.year! - anchor.year!).abs() <= 15);
    return sharesGenre || closeInTime;
  }

  QuizTitle? right;
  QuizTitle? fallback;
  for (final t in candidates) {
    if (t.key == anchor.key || !second(t) || first(t)) continue;
    if (alike(t)) {
      right = t;
      break;
    }
    fallback ??= t;
  }
  right ??= fallback;
  if (right == null) return null;
  return QuizDuel(axis, anchor, right);
}
