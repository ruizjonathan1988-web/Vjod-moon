import 'dart:convert';
import 'dart:math' as math;

import '../seerr/for_you_ranker.dart';
import '../seerr/seerr_api_models.dart';
import '../seerr/taste_profile.dart';
import 'evening_journal.dart';
import 'habit_model.dart';
import 'tonight_models.dart';

/// Whether a title can be played now, or first needs a request.
enum TonightAvailability { inLibrary, requested, requestable }

/// A title Tonight may suggest, from the library or from TMDB through Seerr.
/// Both are scored the same way: a request lands within minutes.
class TonightCandidate {
  /// `movie:603` when the TMDB id is known, otherwise `lib:<item id>`.
  final String key;

  /// `movie` or `tv`.
  final String mediaType;
  final int? tmdbId;
  final String title;
  final Set<TasteGenre> genres;

  /// A movie's length, or one episode's.
  final int? runtimeMinutes;
  final int? year;

  /// Out of 10.
  final double? rating;
  final int? voteCount;
  final String? language;

  /// The age the title's rating allows, when known.
  final int? ratingAge;
  final bool adult;
  final TonightAvailability availability;

  /// The next episode of a series the viewer is in the middle of.
  final bool inProgress;

  /// Already watched, offered again only for a comfort evening.
  final bool rewatch;

  /// Added to the library in the last couple of weeks.
  final bool freshlyAdded;

  /// The movie or series in the library, to open or play.
  final String? libraryItemId;

  /// What to play: the next episode, or the movie.
  final String? playItemId;
  final String? posterUrl;
  final String? backdropUrl;
  final String? overview;

  /// "S2 · E4" for a series in progress.
  final String? nextEpisodeLabel;

  /// Seasons a series has, when known.
  final int? seasonCount;

  const TonightCandidate({
    required this.key,
    required this.mediaType,
    required this.title,
    this.tmdbId,
    this.genres = const {},
    this.runtimeMinutes,
    this.year,
    this.rating,
    this.voteCount,
    this.language,
    this.ratingAge,
    this.adult = false,
    this.availability = TonightAvailability.requestable,
    this.inProgress = false,
    this.rewatch = false,
    this.freshlyAdded = false,
    this.libraryItemId,
    this.playItemId,
    this.posterUrl,
    this.backdropUrl,
    this.overview,
    this.nextEpisodeLabel,
    this.seasonCount,
  });

  bool get isMovie => mediaType == 'movie';

  String? get tmdbKey => tmdbId == null ? null : '$mediaType:$tmdbId';

  TonightCandidate copyWith({
    int? runtimeMinutes,
    TonightAvailability? availability,
    String? libraryItemId,
    String? playItemId,
    String? overview,
    String? backdropUrl,
  }) => TonightCandidate(
    key: key,
    mediaType: mediaType,
    title: title,
    tmdbId: tmdbId,
    genres: genres,
    runtimeMinutes: runtimeMinutes ?? this.runtimeMinutes,
    year: year,
    rating: rating,
    voteCount: voteCount,
    language: language,
    ratingAge: ratingAge,
    adult: adult,
    availability: availability ?? this.availability,
    inProgress: inProgress,
    rewatch: rewatch,
    freshlyAdded: freshlyAdded,
    libraryItemId: libraryItemId ?? this.libraryItemId,
    playItemId: playItemId ?? this.playItemId,
    posterUrl: posterUrl,
    backdropUrl: backdropUrl ?? this.backdropUrl,
    overview: overview ?? this.overview,
    nextEpisodeLabel: nextEpisodeLabel,
    seasonCount: seasonCount,
  );

  /// The library copy of [other] wins, with whatever [other] knows better.
  TonightCandidate mergedWith(TonightCandidate other) => TonightCandidate(
    key: key,
    mediaType: mediaType,
    title: title.isNotEmpty ? title : other.title,
    tmdbId: tmdbId ?? other.tmdbId,
    genres: genres.isNotEmpty ? genres : other.genres,
    runtimeMinutes: runtimeMinutes ?? other.runtimeMinutes,
    year: year ?? other.year,
    rating: other.voteCount != null ? other.rating : (rating ?? other.rating),
    voteCount: voteCount ?? other.voteCount,
    language: language ?? other.language,
    ratingAge: ratingAge ?? other.ratingAge,
    adult: adult || other.adult,
    availability: availability.index <= other.availability.index
        ? availability
        : other.availability,
    inProgress: inProgress || other.inProgress,
    rewatch: rewatch && other.rewatch,
    freshlyAdded: freshlyAdded || other.freshlyAdded,
    libraryItemId: libraryItemId ?? other.libraryItemId,
    playItemId: playItemId ?? other.playItemId,
    posterUrl: posterUrl ?? other.posterUrl,
    backdropUrl: backdropUrl ?? other.backdropUrl,
    overview: (overview?.isNotEmpty ?? false) ? overview : other.overview,
    nextEpisodeLabel: nextEpisodeLabel ?? other.nextEpisodeLabel,
    seasonCount: seasonCount ?? other.seasonCount,
  );
}

/// Why a pick was made, for the line under it.
enum TonightReasonKind {
  resume,
  because,
  habit,
  mood,
  company,
  quality,
  fresh,
  taste,
  joker,
}

class TonightReason {
  final TonightReasonKind kind;

  /// The title behind a "because" reason.
  final String? seedTitle;

  /// The slot behind a habit reason.
  final TonightSlot? slot;

  /// A liked genre behind a taste reason.
  final TasteGenre? genre;

  const TonightReason(this.kind, {this.seedTitle, this.slot, this.genre});
}

class TonightPick {
  final TonightCandidate candidate;
  final double score;

  /// The standardized features it was scored on, kept to learn from what
  /// the viewer does with it.
  final Map<String, double> features;
  final TonightReason reason;
  final bool isJoker;

  const TonightPick({
    required this.candidate,
    required this.score,
    required this.features,
    required this.reason,
    this.isJoker = false,
  });
}

/// What the score is made of. Each is standardized across the candidates
/// of an evening before weighing, so the weights compare like with like.
abstract final class TonightFeature {
  static const taste = 'taste';
  static const seed = 'seed';
  static const habit = 'habit';
  static const format = 'format';
  static const mood = 'mood';
  static const duration = 'duration';
  static const company = 'company';
  static const quality = 'quality';
  static const fresh = 'fresh';
  static const resume = 'resume';
  static const novelty = 'novelty';
  static const rejected = 'rejected';

  static const all = [
    taste,
    seed,
    habit,
    format,
    mood,
    duration,
    company,
    quality,
    fresh,
    resume,
    novelty,
    rejected,
  ];
}

/// How much each feature counts. Starts from sensible values, then follows
/// what the viewer actually launches, finishes or turns down.
class TonightWeights {
  final Map<String, double> values;

  /// Launches and verdicts learned from.
  final int lessons;

  const TonightWeights([this.values = const {}, this.lessons = 0]);

  static const defaults = {
    TonightFeature.taste: 1.0,
    TonightFeature.seed: 0.9,
    TonightFeature.habit: 0.8,
    TonightFeature.format: 0.3,
    TonightFeature.mood: 1.1,
    TonightFeature.duration: 0.6,
    TonightFeature.company: 0.6,
    TonightFeature.quality: 0.7,
    TonightFeature.fresh: 0.2,
    TonightFeature.resume: 0.5,
    TonightFeature.novelty: 0.15,
    TonightFeature.rejected: 1.0,
  };

  /// Features whose weight is a rule, not a taste: never learned.
  static const fixed = {TonightFeature.rejected};

  static const minWeight = 0.05;
  static const maxWeight = 2.5;

  double operator [](String feature) =>
      values[feature] ?? defaults[feature] ?? 0;

  /// Moves the weights towards what [chosen] had and, when given, away from
  /// what [over] had: [chosen] was preferred to [over].
  TonightWeights learn(
    Map<String, double> chosen, {
    Map<String, double>? over,
    required double reward,
    double rate = 0.05,
  }) {
    final next = <String, double>{};
    for (final feature in TonightFeature.all) {
      final current = this[feature];
      if (fixed.contains(feature)) {
        next[feature] = current;
        continue;
      }
      final delta = (chosen[feature] ?? 0) - (over?[feature] ?? 0);
      next[feature] = (current + rate * reward * delta).clamp(
        minWeight,
        maxWeight,
      );
    }
    return TonightWeights(next, lessons + 1);
  }

  String encode() => jsonEncode({'w': values, 'n': lessons});

  static TonightWeights decode(String? source) {
    if (source == null || source.isEmpty) return const TonightWeights();
    try {
      final json = jsonDecode(source);
      if (json is! Map) return const TonightWeights();
      final raw = json['w'];
      return TonightWeights({
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is num) '${e.key}': (e.value as num).toDouble(),
      }, (json['n'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return const TonightWeights();
    }
  }
}

/// Everything one evening's ranking needs.
class TonightInput {
  final List<TonightCandidate> candidates;
  final TonightAnswers answers;
  final DateTime now;
  final TonightDevice? device;
  final HabitModel habits;
  final List<JournalEntry> journal;
  final TasteProfile profile;
  final TasteFeedback feedback;
  final List<TasteSeed> seeds;
  final Map<String, List<SeerrDiscoverItem>> recommendations;

  /// Times each key was turned down lately with "Another idea".
  final Map<String, int> rejections;

  /// Keys already shown this evening and set aside.
  final Set<String> exclude;

  /// TMDB keys already watched.
  final Set<String> watched;
  final TonightWeights weights;
  final bool blockAdult;

  const TonightInput({
    required this.candidates,
    required this.answers,
    required this.now,
    required this.habits,
    this.device,
    this.journal = const [],
    this.profile = TasteProfile.empty,
    this.feedback = TasteFeedback.empty,
    this.seeds = const [],
    this.recommendations = const {},
    this.rejections = const {},
    this.exclude = const {},
    this.watched = const {},
    this.weights = const TonightWeights(),
    this.blockAdult = true,
  });
}

class TonightResult {
  final List<TonightPick> picks;

  /// Candidates left once the evening's rules were applied.
  final int poolSize;

  /// The mood was too strict for what was there, so it became a preference
  /// instead of a rule.
  final bool relaxedMood;

  const TonightResult({
    required this.picks,
    required this.poolSize,
    this.relaxedMood = false,
  });

  static const empty = TonightResult(picks: [], poolSize: 0);
}

/// Picks what to watch tonight: one main suggestion and five others, from
/// the viewer's taste, their habits for this time and company, the mood of
/// the evening and the time it leaves.
///
/// All of it is arithmetic on what the app already knows. Nothing leaves
/// the device but the Seerr calls that bring the candidates.
abstract final class TonightEngine {
  static const pickCount = 6;

  /// Genres each mood looks for, with how strongly.
  static const moodGenres = <TonightMood, Map<TasteGenre, double>>{
    TonightMood.laugh: {
      TasteGenre.comedy: 1,
      TasteGenre.animation: 0.6,
      TasteGenre.family: 0.5,
      TasteGenre.romance: 0.3,
    },
    TonightMood.chills: {
      TasteGenre.horror: 1,
      TasteGenre.thriller: 1,
      TasteGenre.mystery: 0.7,
      TasteGenre.crime: 0.4,
    },
    TonightMood.escape: {
      TasteGenre.fantasy: 1,
      TasteGenre.scifi: 1,
      TasteGenre.adventure: 0.9,
      TasteGenre.animation: 0.5,
      TasteGenre.action: 0.5,
    },
    TonightMood.think: {
      TasteGenre.documentary: 1,
      TasteGenre.drama: 0.8,
      TasteGenre.history: 0.8,
      TasteGenre.war: 0.5,
      TasteGenre.mystery: 0.4,
      TasteGenre.crime: 0.3,
    },
    TonightMood.comfort: {
      TasteGenre.comedy: 0.7,
      TasteGenre.family: 0.6,
      TasteGenre.romance: 0.6,
      TasteGenre.animation: 0.6,
      TasteGenre.adventure: 0.3,
      TasteGenre.music: 0.3,
    },
    TonightMood.surprise: {},
  };

  /// Genres that break a mood outright.
  static const moodClashes = <TonightMood, Set<TasteGenre>>{
    TonightMood.laugh: {TasteGenre.horror, TasteGenre.war},
    TonightMood.chills: {TasteGenre.family, TasteGenre.kids},
    TonightMood.escape: {TasteGenre.documentary, TasteGenre.talk},
    TonightMood.think: {TasteGenre.kids, TasteGenre.reality},
    TonightMood.comfort: {TasteGenre.horror, TasteGenre.war},
    TonightMood.surprise: {},
  };

  /// Moods a title has to answer to, not just lean towards.
  static const strictMoods = {
    TonightMood.laugh,
    TonightMood.chills,
    TonightMood.escape,
    TonightMood.think,
  };

  static const _familyGenres = {
    TasteGenre.family,
    TasteGenre.animation,
    TasteGenre.kids,
  };
  static const _darkGenres = {
    TasteGenre.horror,
    TasteGenre.thriller,
    TasteGenre.crime,
    TasteGenre.war,
  };

  static TonightResult rank(TonightInput input) {
    var scored = _score(input, strictMood: true);
    var relaxed = false;
    if (strictMoods.contains(input.answers.mood) &&
        scored.length < pickCount * 2) {
      final loose = _score(input, strictMood: false);
      if (loose.length > scored.length) {
        scored = loose;
        relaxed = true;
      }
    }
    if (scored.isEmpty) return TonightResult.empty;
    final picks = _select(scored, input);
    return TonightResult(
      picks: picks,
      poolSize: scored.length,
      relaxedMood: relaxed,
    );
  }

  /// Share of past sittings the engine would have put in its six picks, out
  /// of the current candidates, judged with only what it knew before each.
  /// Null until there are enough sittings to say.
  static double? selfCheck({
    required List<JournalEntry> journal,
    required List<TonightCandidate> pool,
    TasteProfile profile = TasteProfile.empty,
    TasteFeedback feedback = TasteFeedback.empty,
    TonightWeights weights = const TonightWeights(),
    int last = 20,
    int poolSample = 120,
  }) {
    final checked = journal
        .where((e) => e.genres.isNotEmpty && e.outcome > 0)
        .toList();
    if (checked.length < 8) return null;
    final sample = pool.take(poolSample).toList();
    var hits = 0;
    var tries = 0;
    for (final entry in checked.reversed.take(last)) {
      final before = journal.where((e) => e.at.isBefore(entry.at)).toList();
      if (before.length < 5) continue;
      final watchedKey = entry.tmdbKey ?? 'lib:${entry.itemId}';
      final target = TonightCandidate(
        key: watchedKey,
        mediaType: entry.mediaType,
        tmdbId: entry.tmdbId,
        title: entry.title,
        genres: entry.genres,
        runtimeMinutes: entry.runtimeMinutes,
        year: entry.year,
        rating: entry.rating,
        availability: TonightAvailability.inLibrary,
      );
      final input = TonightInput(
        candidates: [
          for (final c in sample)
            if (c.key != watchedKey) c,
          target,
        ],
        answers: TonightAnswers(
          company: entry.company ?? TonightCompany.alone,
          time: TonightTime.any,
          mood: TonightMood.surprise,
          at: entry.at,
        ),
        now: entry.at,
        device: entry.device,
        habits: HabitModel.build(before, now: entry.at),
        journal: before,
        profile: profile,
        feedback: feedback,
        weights: weights,
        blockAdult: false,
      );
      // The mood of that evening isn't known, so it is left out.
      final scored = _score(input, strictMood: false, neutralMood: true);
      final rank = scored.indexWhere((s) => s.candidate.key == watchedKey);
      if (rank < 0) continue;
      tries++;
      if (rank < pickCount) hits++;
    }
    if (tries < 5) return null;
    return hits / tries;
  }

  static List<_Scored> _score(
    TonightInput input, {
    required bool strictMood,
    bool neutralMood = false,
  }) {
    final answers = input.answers;
    final mood = answers.mood;
    final slot = TonightSlot.of(input.now);
    final habit = input.habits.forContext(
      slot: slot,
      company: answers.company,
      device: input.device,
    );
    final confidence = input.habits.global.confidence(prior: 10);
    final budget = answers.time.budgetMinutes;
    final declared = switch (input.profile.movieLength) {
      TasteMovieLength.short => 95.0,
      TasteMovieLength.medium => 120.0,
      TasteMovieLength.long => 150.0,
      TasteMovieLength.any => 110.0,
    };
    var idealMovie = (habit.typicalMovieMinutes ?? declared)
        .clamp(85.0, 150.0)
        .toDouble();
    if (budget != null) idealMovie = math.min(idealMovie, budget - 5.0);
    final support = _seedSupport(input, slot);
    final hidden = input.feedback.hiddenKeys;
    final wanted = moodGenres[mood]!;
    final clashes = moodClashes[mood]!;

    final rows = <_Scored>[];
    for (final c in input.candidates) {
      // Rules first: what the evening can't hold is out.
      if (input.exclude.contains(c.key)) continue;
      if (hidden.contains(c.key) ||
          (c.tmdbKey != null && hidden.contains(c.tmdbKey))) {
        continue;
      }
      if (input.blockAdult && c.adult) continue;
      if (c.rewatch && mood != TonightMood.comfort) continue;
      if (!c.rewatch &&
          !c.inProgress &&
          c.tmdbKey != null &&
          input.watched.contains(c.tmdbKey)) {
        continue;
      }
      if (!neutralMood && c.genres.any(clashes.contains)) continue;
      if (answers.company == TonightCompany.family &&
          !_familySafe(c, answers.kidsAge)) {
        continue;
      }
      final runtime = c.runtimeMinutes;
      if (budget != null && runtime != null) {
        if (c.isMovie && runtime > budget + 5) continue;
        if (!c.isMovie && runtime > budget) continue;
      }
      final taste = tasteFactorFor(
        genres: c.genres,
        mediaType: c.mediaType,
        language: c.language,
        year: c.year,
        voteCount: c.voteCount,
        profile: input.profile,
        feedback: input.feedback,
        now: input.now,
      );
      if (taste <= 0) continue;

      var moodScore = 0.0;
      for (final genre in c.genres) {
        moodScore += wanted[genre] ?? 0;
      }
      moodScore = math.min(moodScore, 1.5);
      if (!neutralMood &&
          strictMood &&
          strictMoods.contains(mood) &&
          moodScore <= 0 &&
          !c.inProgress) {
        continue;
      }
      if (mood == TonightMood.comfort) {
        if (c.rewatch) moodScore += 0.8;
        if (c.inProgress) moodScore += 0.5;
      }

      final seed = support[c.key] ?? support[c.tmdbKey];
      final seasons = c.seasonCount;
      final seriesFit = c.isMovie || seasons == null
          ? 0.0
          : switch (input.profile.seriesFormat) {
              TasteSeriesFormat.mini =>
                seasons == 1 ? 0.5 : (seasons >= 4 ? -0.5 : 0.0),
              TasteSeriesFormat.few =>
                seasons >= 2 && seasons <= 3 ? 0.5 : (seasons >= 6 ? -0.4 : 0.0),
              TasteSeriesFormat.long =>
                seasons >= 4 ? 0.5 : (seasons == 1 ? -0.3 : 0.0),
              TasteSeriesFormat.any => 0.0,
            };
      final genreFit = habit.genreFit(c.genres);
      final movieShare = habit.movieShare;

      final double duration;
      if (c.isMovie) {
        if (runtime == null) {
          duration = -0.4;
        } else {
          var d = -(runtime - idealMovie).abs() / 45;
          if (answers.time == TonightTime.evening && runtime >= 100) d += 0.2;
          duration = d;
        }
      } else {
        duration = switch (answers.time) {
          TonightTime.short => 0.3,
          TonightTime.evening => c.inProgress ? 0.3 : 0.0,
          TonightTime.any => 0.0,
        };
      }

      final double company;
      switch (answers.company) {
        case TonightCompany.family:
          company =
              (c.genres.any(_familyGenres.contains) ? 1.0 : 0.0) +
              (c.genres.contains(TasteGenre.comedy) ||
                      c.genres.contains(TasteGenre.adventure)
                  ? 0.3
                  : 0.0);
        case TonightCompany.couple:
          company =
              math.log(1 + (c.voteCount ?? 300)) / 8 +
              (c.genres.contains(TasteGenre.romance) ? 0.3 : 0.0);
        case TonightCompany.friends:
          company =
              c.genres.any(
                {
                  TasteGenre.action,
                  TasteGenre.comedy,
                  TasteGenre.horror,
                  TasteGenre.thriller,
                }.contains,
              )
              ? 0.6
              : 0.0;
        case TonightCompany.alone:
          company = 0;
      }

      final double quality;
      final rating = c.rating;
      final votes = c.voteCount;
      if (rating == null || rating <= 0) {
        quality = 0;
      } else if (votes != null) {
        const m = 400.0;
        const prior = 6.6;
        quality = (votes * rating + m * prior) / (votes + m) - prior;
      } else {
        quality = rating * 0.7 + 6.6 * 0.3 - 6.6;
      }

      final fresh =
          (c.freshlyAdded ? 1.0 : 0.0) +
          (c.year != null && c.year! >= input.now.year - 1 ? 0.5 : 0.0);

      rows.add(
        _Scored(c, taste, seed?.title, {
          TonightFeature.taste: math.log(taste),
          TonightFeature.seed: math.log(1 + (seed?.support ?? 0)),
          TonightFeature.habit: genreFit * confidence,
          TonightFeature.format:
              ((c.isMovie ? movieShare : 1 - movieShare) - 0.5) * confidence +
              seriesFit,
          TonightFeature.mood: neutralMood ? 0 : moodScore,
          TonightFeature.duration: duration,
          TonightFeature.company: company,
          TonightFeature.quality: quality,
          TonightFeature.fresh: fresh,
          TonightFeature.resume: c.inProgress ? 1.0 : 0.0,
          TonightFeature.novelty: -genreFit,
          TonightFeature.rejected: -(input.rejections[c.key] ?? 0).toDouble(),
        }),
      );
    }
    if (rows.isEmpty) return rows;

    _standardize(rows);
    final weights = _effectiveWeights(input, neutralMood: neutralMood);
    for (final row in rows) {
      var score = 0.0;
      for (final feature in TonightFeature.all) {
        score += (weights[feature] ?? 0) * (row.z[feature] ?? 0);
      }
      row.score = score;
    }
    rows.sort((a, b) => b.score.compareTo(a.score));
    return rows;
  }

  /// Turns every feature into how far a candidate stands from the evening's
  /// average, in standard deviations, so no feature wins by its scale.
  static void _standardize(List<_Scored> rows) {
    for (final feature in TonightFeature.all) {
      var sum = 0.0;
      for (final row in rows) {
        sum += row.raw[feature]!;
      }
      final mean = sum / rows.length;
      var variance = 0.0;
      for (final row in rows) {
        final d = row.raw[feature]! - mean;
        variance += d * d;
      }
      final sd = math.sqrt(variance / rows.length);
      for (final row in rows) {
        row.z[feature] = sd < 1e-6
            ? 0
            : ((row.raw[feature]! - mean) / sd).clamp(-2.5, 2.5);
      }
    }
  }

  static Map<String, double> _effectiveWeights(
    TonightInput input, {
    required bool neutralMood,
  }) {
    final w = {
      for (final feature in TonightFeature.all) feature: input.weights[feature],
    };
    if (neutralMood) {
      w[TonightFeature.mood] = 0;
      return w;
    }
    switch (input.answers.mood) {
      case TonightMood.surprise:
        w[TonightFeature.habit] = w[TonightFeature.habit]! * 0.3;
        w[TonightFeature.seed] = w[TonightFeature.seed]! * 0.6;
        w[TonightFeature.quality] = w[TonightFeature.quality]! * 1.3;
        w[TonightFeature.novelty] = 0.9;
      case TonightMood.comfort:
        w[TonightFeature.resume] = w[TonightFeature.resume]! * 2;
        w[TonightFeature.habit] = w[TonightFeature.habit]! * 1.3;
        w[TonightFeature.novelty] = 0;
      default:
        break;
    }
    if (input.answers.company == TonightCompany.family) {
      w[TonightFeature.company] = w[TonightFeature.company]! * 1.5;
    }
    if (input.answers.time == TonightTime.short) {
      w[TonightFeature.duration] = w[TonightFeature.duration]! * 1.4;
    }
    return w;
  }

  /// How strongly the viewer's favourite titles point at each candidate.
  /// Titles watched in a similar evening, or with the same company, point
  /// harder.
  static Map<String, ({double support, String title})> _seedSupport(
    TonightInput input,
    TonightSlot slot,
  ) {
    final contextual = <String, double>{};
    for (final entry in input.journal) {
      final key = entry.tmdbKey;
      if (key == null || entry.outcome <= 0) continue;
      var boost = 0.0;
      if (entry.slot.band == slot.band) boost += 0.25;
      if (entry.slot == slot) boost += 0.25;
      if (entry.company != null && entry.company == input.answers.company) {
        boost += 0.5;
      }
      contextual[key] = math.max(contextual[key] ?? 0, boost);
    }

    final result = <String, ({double support, String title})>{};
    final best = <String, double>{};
    for (final seed in input.seeds) {
      final recs = input.recommendations[seed.key];
      if (recs == null || recs.isEmpty) continue;
      final weight = seed.weight * (1 + (contextual[seed.key] ?? 0));
      for (final (rank, item) in recs.indexed) {
        final type = item.mediaType ?? seed.mediaType;
        final key = '$type:${item.id}';
        final push = weight * (1 - rank / (recs.length + 5));
        final current = result[key];
        final title = current != null && (best[key] ?? 0) >= push
            ? current.title
            : seed.title;
        if ((best[key] ?? 0) < push) best[key] = push;
        result[key] = (
          support: (current?.support ?? 0) + push,
          title: title,
        );
      }
    }
    return result;
  }

  static bool _familySafe(TonightCandidate c, KidsAge kids) {
    if (c.adult) return false;
    final age = c.ratingAge;
    if (age != null) return age <= kids.maxRatingAge;
    // No rating to go on: only what is plainly made for families.
    return c.genres.any(_familyGenres.contains) &&
        !c.genres.any(_darkGenres.contains);
  }

  static List<TonightPick> _select(List<_Scored> ranked, TonightInput input) {
    final picks = <_Scored>[];
    picks.add(ranked.first);

    // The next four: the best left, kept apart from what is already in.
    final window = ranked.take(60).toList();
    while (picks.length < pickCount - 1) {
      _Scored? best;
      var bestValue = double.negativeInfinity;
      for (final row in window) {
        if (picks.contains(row)) continue;
        final value = row.score - _redundancy(row, picks);
        if (value > bestValue) {
          bestValue = value;
          best = row;
        }
      }
      if (best == null) break;
      picks.add(best);
    }

    // The last: a well-rated title off the usual path, so the suggestions
    // keep finding new ground.
    _Scored? joker;
    var jokerValue = double.negativeInfinity;
    for (final row in ranked) {
      if (picks.contains(row)) continue;
      if (row.taste < 0.85) continue;
      if ((row.raw[TonightFeature.quality] ?? 0) < 0.3) continue;
      final value =
          (row.z[TonightFeature.quality] ?? 0) +
          1.2 * (row.z[TonightFeature.novelty] ?? 0) +
          0.4 * (row.z[TonightFeature.mood] ?? 0) +
          0.3 * (row.z[TonightFeature.taste] ?? 0) -
          (row.z[TonightFeature.rejected] ?? 0).abs();
      if (value > jokerValue) {
        jokerValue = value;
        joker = row;
      }
    }
    final jokerRow = joker;
    if (jokerRow != null) {
      picks.add(jokerRow);
    } else {
      for (final row in window) {
        if (picks.length >= pickCount) break;
        if (!picks.contains(row)) picks.add(row);
      }
    }

    final weights = _effectiveWeights(input, neutralMood: false);
    final slot = TonightSlot.of(input.now);
    return [
      for (final row in picks)
        TonightPick(
          candidate: row.candidate,
          score: row.score,
          features: Map.unmodifiable(row.z),
          reason: identical(row, jokerRow)
              ? const TonightReason(TonightReasonKind.joker)
              : _reason(row, weights, slot, input.profile),
          isJoker: identical(row, jokerRow),
        ),
    ];
  }

  /// How much [row] repeats what [picks] already offer.
  static double _redundancy(_Scored row, List<_Scored> picks) {
    var penalty = 0.0;
    for (final pick in picks) {
      final a = row.candidate.genres;
      final b = pick.candidate.genres;
      if (a.isNotEmpty && b.isNotEmpty) {
        final shared = a.intersection(b).length;
        final union = a.union(b).length;
        penalty += 0.6 * shared / union;
      }
      if (row.seedTitle != null && row.seedTitle == pick.seedTitle) {
        penalty += 0.6;
      }
      if (row.candidate.inProgress && pick.candidate.inProgress) {
        penalty += 0.4;
      }
    }
    return penalty;
  }

  static TonightReason _reason(
    _Scored row,
    Map<String, double> weights,
    TonightSlot slot,
    TasteProfile profile,
  ) {
    if (row.candidate.inProgress) {
      return const TonightReason(TonightReasonKind.resume);
    }
    double part(String feature) =>
        (weights[feature] ?? 0) * (row.z[feature] ?? 0);
    final options = <(TonightReasonKind, double)>[
      if (row.seedTitle != null)
        (TonightReasonKind.because, part(TonightFeature.seed) + 0.15),
      (TonightReasonKind.habit, part(TonightFeature.habit)),
      (TonightReasonKind.mood, part(TonightFeature.mood)),
      (TonightReasonKind.company, part(TonightFeature.company)),
      (TonightReasonKind.quality, part(TonightFeature.quality)),
      (TonightReasonKind.fresh, part(TonightFeature.fresh)),
      (TonightReasonKind.taste, part(TonightFeature.taste)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final kind = options.first.$2 > 0
        ? options.first.$1
        : TonightReasonKind.mood;
    TasteGenre? liked;
    for (final genre in row.candidate.genres) {
      if (profile.liked.contains(genre)) {
        liked = genre;
        break;
      }
    }
    return TonightReason(
      kind == TonightReasonKind.taste && liked == null
          ? TonightReasonKind.mood
          : kind,
      seedTitle: row.seedTitle,
      slot: slot,
      genre: liked,
    );
  }
}

class _Scored {
  final TonightCandidate candidate;

  /// The taste factor, kept apart for the joker's bar.
  final double taste;
  final String? seedTitle;
  final Map<String, double> raw;
  final Map<String, double> z = {};
  double score = 0;

  _Scored(this.candidate, this.taste, this.seedTitle, this.raw);
}
