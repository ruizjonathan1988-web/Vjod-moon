import 'dart:math' as math;

import '../seerr/taste_profile.dart';
import '../tonight/evening_journal.dart';
import '../tonight/tonight_engine.dart';
import '../tonight/tonight_models.dart';
import 'vjod_votes.dart';

/// Why a title sits where it does in a personalized row, said under it.
enum VjodWhy { mood, recent, liked, discovery }

/// A title a VJOD row could show, with what personalizing it needs.
class VjodCandidate<T> {
  final T item;

  /// `movie:<tmdb id>` or `tv:<tmdb id>`.
  final String key;
  final Set<TasteGenre> genres;

  /// What the taste profile thinks of it: 0 is an explicit no, 1 neutral.
  final double taste;

  const VjodCandidate({
    required this.item,
    required this.key,
    required this.genres,
    this.taste = 1,
  });
}

/// A title placed in a row, and why, when there is something to say.
class VjodPlaced<T> {
  final T item;
  final VjodWhy? why;

  /// The title watched lately that brought it, for [VjodWhy.recent].
  final String? because;

  const VjodPlaced(this.item, {this.why, this.because});
}

/// Everything VJOD knows about the viewer right now, read once per refresh.
class VjodSignals {
  /// Personalization on. Off, rows keep the catalogue's own order.
  final bool enabled;

  /// What tonight calls for, chosen on Home today. Null when not chosen.
  final TonightMood? mood;

  /// Genres of the last weeks' sittings, each one's share, 0 to 1. Short
  /// memory: a binge from a month ago barely counts.
  final Map<TasteGenre, double> recent;

  /// For each recent genre, the latest title watched in it.
  final Map<TasteGenre, String> recentTitles;

  /// The genres the viewer always goes back to: discovery means outside
  /// these.
  final Set<TasteGenre> comfort;

  /// TMDB keys of everything already watched.
  final Set<String> watched;

  /// What the "J'ai aimé" and "Bof" votes say about each genre, -1 to 1.
  final Map<TasteGenre, double> genreBias;

  /// How much each suggestion source earned the viewer's trust.
  final Map<String, double> sourceWeights;

  const VjodSignals({
    this.enabled = false,
    this.mood,
    this.recent = const {},
    this.recentTitles = const {},
    this.comfort = const {},
    this.watched = const {},
    this.genreBias = const {},
    this.sourceWeights = const {},
  });

  /// The same, minus the watched titles: for rows that already hold only
  /// unplayed ones.
  VjodSignals withoutWatched() => VjodSignals(
    enabled: enabled,
    mood: mood,
    recent: recent,
    recentTitles: recentTitles,
    comfort: comfort,
    genreBias: genreBias,
    sourceWeights: sourceWeights,
  );

  static const off = VjodSignals();

  /// How long a sitting keeps half its weight in the short memory.
  static const recentHalfLife = Duration(days: 5);

  /// Past this, a sitting is out of the short memory altogether.
  static const recentWindow = Duration(days: 21);

  /// The long memory, for what the viewer always comes back to.
  static const habitHalfLife = Duration(days: 60);

  factory VjodSignals.build({
    required bool enabled,
    required EveningJournal journal,
    required TasteProfile profile,
    TonightMood? mood,
    VjodVotes votes = VjodVotes.empty,
    DateTime? now,
  }) {
    if (!enabled) return off;
    final at = now ?? DateTime.now();
    final recent = <TasteGenre, double>{};
    final recentTitles = <TasteGenre, String>{};
    final habit = <TasteGenre, double>{};
    for (final entry in journal.entries) {
      if (entry.abandoned || entry.genres.isEmpty) continue;
      final age = at.difference(entry.at);
      if (age.isNegative) continue;
      final days = age.inMinutes / Duration.minutesPerDay;
      final strength = math.max(entry.outcome, 0.1);
      final long =
          strength *
          math.pow(0.5, days / habitHalfLife.inDays).toDouble() /
          entry.genres.length;
      for (final genre in entry.genres) {
        habit[genre] = (habit[genre] ?? 0) + long;
      }
      if (age > recentWindow) continue;
      final short =
          strength *
          math.pow(0.5, days / recentHalfLife.inDays).toDouble() /
          entry.genres.length;
      for (final genre in entry.genres) {
        recent[genre] = (recent[genre] ?? 0) + short;
        // Entries come oldest first, so the last one written wins.
        if (entry.title.isNotEmpty) recentTitles[genre] = entry.title;
      }
    }
    final recentTotal = recent.values.fold<double>(0, (a, b) => a + b);
    final recentShares = recentTotal <= 0
        ? const <TasteGenre, double>{}
        : {for (final e in recent.entries) e.key: e.value / recentTotal};

    // What the viewer always comes back to: their three most watched genres,
    // what they said they like, and what their favourite titles share.
    final habitual = habit.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final bias = votes.genreBias(now: at);
    final comfort = <TasteGenre>{
      for (final e in habitual.take(3)) e.key,
      ...profile.liked,
      for (final e in profile.genreAffinity.entries)
        if (e.value >= 0.3) e.key,
      for (final e in bias.entries)
        if (e.value >= 0.3) e.key,
    };

    return VjodSignals(
      enabled: true,
      mood: mood,
      recent: recentShares,
      recentTitles: recentTitles,
      comfort: comfort,
      // A title voted on was seen, whatever the journal says.
      watched: {...journal.watchedTmdbKeys, for (final v in votes.votes) v.key},
      genreBias: bias,
      sourceWeights: votes.sourceWeights(),
    );
  }
}

/// Turns a collection into a row that looks like the viewer without walling
/// them in.
///
/// The rules, all of them here:
/// - about one title in three is a discovery: outside the genres the viewer
///   always goes back to;
/// - a preference only ever raises or lowers, it never removes; only an
///   explicit "never" from the questionnaire or "not interested" does;
/// - recent sittings weigh a lot but fade within days, and a mood lasts the
///   evening;
/// - each personalized title says why it is there.
abstract final class VjodPersonalizer {
  /// Share of a row kept for discoveries.
  static const discoveryShare = 1 / 3;

  /// When the viewer asks to be surprised, half the row.
  static const surpriseShare = 1 / 2;

  static List<VjodPlaced<T>> arrange<T>(
    List<VjodCandidate<T>> candidates,
    VjodSignals signals, {
    int seed = 0,
    bool allDiscovery = false,
  }) {
    if (!signals.enabled) {
      return [for (final c in candidates) VjodPlaced(c.item)];
    }
    final mood = signals.mood;
    final moodGenres = mood == null
        ? const <TasteGenre, double>{}
        : TonightEngine.moodGenres[mood] ?? const {};
    final moodClashes = mood == null
        ? const <TasteGenre>{}
        : TonightEngine.moodClashes[mood] ?? const {};

    final scored = <({VjodCandidate<T> c, double score, VjodWhy? why, String? because})>[];
    final seen = <String>{};
    for (final (index, c) in candidates.indexed) {
      if (c.taste <= 0) continue;
      if (signals.watched.contains(c.key)) continue;
      if (!seen.add(c.key)) continue;

      // The collection's own order still counts: it is what makes it good.
      final prior = 1 / (1 + 0.04 * index);
      var recentFit = 0.0;
      TasteGenre? recentGenre;
      for (final genre in c.genres) {
        final share = signals.recent[genre] ?? 0.0;
        recentFit += share;
        if (share > (signals.recent[recentGenre] ?? 0)) recentGenre = genre;
      }
      recentFit = recentFit.clamp(0.0, 1.0);
      var moodFit = 0.0;
      for (final genre in c.genres) {
        moodFit = math.max(moodFit, moodGenres[genre] ?? 0.0);
      }
      final clashes = c.genres.any(moodClashes.contains);

      final voted = VjodVotes.factorFor(c.genres, signals.genreBias);
      var score = c.taste * voted * prior * (1 + 0.8 * recentFit);
      if (moodGenres.isNotEmpty) {
        score *= 0.55 + moodFit;
        // Lowered, never removed: the evening may turn.
        if (clashes) score *= 0.25;
      }

      VjodWhy? why;
      String? because;
      if (moodFit >= 0.6 && !clashes) {
        why = VjodWhy.mood;
      } else if (recentFit >= 0.3 && recentGenre != null) {
        why = VjodWhy.recent;
        because = signals.recentTitles[recentGenre];
        if (because == null) why = null;
      } else if (c.taste * voted >= 1.25) {
        why = VjodWhy.liked;
      }
      scored.add((c: c, score: score, why: why, because: because));
    }

    bool isDiscovery(VjodCandidate<T> c) =>
        c.genres.isNotEmpty &&
        !c.genres.any(signals.comfort.contains) &&
        !c.genres.any(moodClashes.contains);

    final random = math.Random(seed);
    // Discoveries keep the collection's order, lightly stirred each day.
    final discoveries = [
      for (final s in scored)
        if (isDiscovery(s.c)) s,
    ];
    final head = discoveries.take(12).toList()..shuffle(random);
    final discoveryQueue = [...head, ...discoveries.skip(12)];

    if (allDiscovery) {
      return [
        for (final s in discoveryQueue)
          VjodPlaced(s.c.item, why: VjodWhy.discovery),
      ];
    }

    final personal = [
      for (final s in scored)
        if (!isDiscovery(s.c)) s,
    ]..sort((a, b) => b.score.compareTo(a.score));

    final share = mood == TonightMood.surprise ? surpriseShare : discoveryShare;
    final every = math.max(2, (1 / share).round());
    final out = <VjodPlaced<T>>[];
    var p = 0;
    var d = 0;
    while (p < personal.length || d < discoveryQueue.length) {
      final slot = out.length;
      final wantsDiscovery = slot % every == every - 1;
      if ((wantsDiscovery || p >= personal.length) &&
          d < discoveryQueue.length) {
        out.add(
          VjodPlaced(discoveryQueue[d++].c.item, why: VjodWhy.discovery),
        );
      } else {
        final s = personal[p++];
        out.add(VjodPlaced(s.c.item, why: s.why, because: s.because));
      }
    }
    return out;
  }

  /// What the critics and audiences MDBList gathers agree on, as a factor
  /// from 0.8 to 1.2. One source alone says too little: 1.
  static double ratingsFactor(Map<String, double>? ratings) {
    if (ratings == null || ratings.isEmpty) return 1;
    final scores = <double>[];
    for (final e in ratings.entries) {
      final scale = switch (e.key) {
        'letterboxd' => 5.0,
        'rogerebert' => 4.0,
        'imdb' || 'metacriticuser' || 'myanimelist' => 10.0,
        _ => 100.0,
      };
      final score = e.value / scale;
      if (score > 0 && score <= 1) scores.add(score);
    }
    if (scores.length < 2) return 1;
    final mean = scores.reduce((a, b) => a + b) / scores.length;
    // 0.6 is an ordinary film, 0.85 a great one.
    return (0.8 + (mean - 0.6) * 1.6).clamp(0.8, 1.2);
  }

  /// The genre most of [genres] share, when one holds half of them or more.
  static TasteGenre? dominantGenre(Iterable<Set<TasteGenre>> genres) {
    final count = <TasteGenre, int>{};
    var total = 0;
    for (final set in genres) {
      total++;
      for (final g in set) {
        count[g] = (count[g] ?? 0) + 1;
      }
    }
    if (total == 0) return null;
    final best = count.entries.fold<MapEntry<TasteGenre, int>?>(
      null,
      (a, b) => a == null || b.value > a.value ? b : a,
    );
    if (best == null || best.value * 2 < total) return null;
    return best.key;
  }

  /// The sentence under a title, French or English.
  static String? whyText(VjodWhy? why, {String? because, TonightMood? mood, required bool french}) {
    switch (why) {
      case null:
        return null;
      case VjodWhy.mood:
        final label = mood == null ? null : moodLabel(mood, french: french);
        if (label == null) return null;
        return french ? 'Pour ce soir : $label' : 'For tonight: $label';
      case VjodWhy.recent:
        if (because == null) return null;
        return french
            ? 'Parce que vous regardez $because'
            : 'Because you are watching $because';
      case VjodWhy.liked:
        return french ? 'Dans vos goûts' : 'Your kind of thing';
      case VjodWhy.discovery:
        return french
            ? 'Pour sortir de vos habitudes'
            : 'Off your beaten track';
    }
  }

  static String moodLabel(TonightMood mood, {required bool french}) =>
      switch (mood) {
        TonightMood.laugh => french ? 'Rire' : 'Laugh',
        TonightMood.chills => french ? 'Frissons' : 'Chills',
        TonightMood.escape => french ? 'Évasion' : 'Escape',
        TonightMood.think => french ? 'Réfléchir' : 'Think',
        TonightMood.comfort => french ? 'Réconfort' : 'Comfort',
        TonightMood.surprise => french ? 'Surprends-moi' : 'Surprise me',
      };
}

/// Today's mood, stored as `<mood>@<yyyy-mm-dd>`: gone the next morning.
abstract final class VjodMoodStore {
  /// A day starts at 5 in the morning, so a late evening keeps its mood.
  static String _day(DateTime at) {
    final shifted = at.subtract(const Duration(hours: 5));
    return '${shifted.year}-${shifted.month}-${shifted.day}';
  }

  static TonightMood? read(String? stored, {DateTime? now}) {
    if (stored == null || stored.isEmpty) return null;
    final parts = stored.split('@');
    if (parts.length != 2) return null;
    if (parts[1] != _day(now ?? DateTime.now())) return null;
    return TonightMood.values.asNameMap()[parts[0]];
  }

  static String write(TonightMood mood, {DateTime? now}) =>
      '${mood.name}@${_day(now ?? DateTime.now())}';
}
