import 'dart:convert';
import 'dart:math' as math;

import 'seerr_api_models.dart';

/// The genres the taste questionnaire offers, each mapped onto TMDB's movie
/// and series genre ids, which differ: series fold action and adventure into
/// one genre, science fiction and fantasy into another, and have no horror
/// or thriller of their own.
enum TasteGenre {
  action({28}, {10759}),
  adventure({12}, {10759}),
  animation({16}, {16}),
  comedy({35}, {35}),
  crime({80}, {80}),
  documentary({99}, {99}),
  drama({18}, {18}),
  family({10751}, {10751}),
  fantasy({14}, {10765}),
  history({36}, {}),
  horror({27}, {}),
  kids({}, {10762}),
  music({10402}, {}),
  mystery({9648}, {9648}),
  reality({}, {10764}),
  romance({10749}, {}),
  scifi({878}, {10765}),
  talk({}, {10767, 10763, 10766}),
  thriller({53}, {}),
  war({10752}, {10768}),
  western({37}, {37});

  final Set<int> movieIds;
  final Set<int> tvIds;

  const TasteGenre(this.movieIds, this.tvIds);

  /// The questionnaire genres a TMDB title belongs to.
  static Set<TasteGenre> of(Iterable<int> genreIds, String mediaType) {
    final ids = genreIds.toSet();
    return {
      for (final genre in values)
        if ((mediaType == 'tv' ? genre.tvIds : genre.movieIds).any(
          ids.contains,
        ))
          genre,
    };
  }

  static TasteGenre? byName(String name) => values.asNameMap()[name];

  /// The questionnaire genres a library item's genre names stand for.
  ///
  /// Jellyfin keeps the names its metadata came with, in English or French
  /// for TMDB, and series combine two ("Action & Adventure"), so each name
  /// is split and every part looked up.
  static Set<TasteGenre> fromNames(Iterable<String> names) {
    final found = <TasteGenre>{};
    for (final name in names) {
      for (final part in name.split(RegExp(r'\s*(?:&|/|,| et | and )\s*'))) {
        final genre = _byLabel[_fold(part)];
        if (genre != null) found.add(genre);
      }
      final whole = _byLabel[_fold(name)];
      if (whole != null) found.add(whole);
    }
    return found;
  }

  static String _fold(String text) {
    const from = 'àâäéèêëîïôöùûüç';
    const to = 'aaaeeeeiioouuuc';
    final lower = text.trim().toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      final index = from.indexOf(char);
      buffer.write(index >= 0 ? to[index] : char);
    }
    return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static const Map<String, TasteGenre> _byLabel = {
    'action': TasteGenre.action,
    'adventure': TasteGenre.adventure,
    'aventure': TasteGenre.adventure,
    'animation': TasteGenre.animation,
    'anime': TasteGenre.animation,
    'comedy': TasteGenre.comedy,
    'comedie': TasteGenre.comedy,
    'crime': TasteGenre.crime,
    'policier': TasteGenre.crime,
    'documentary': TasteGenre.documentary,
    'documentaire': TasteGenre.documentary,
    'drama': TasteGenre.drama,
    'drame': TasteGenre.drama,
    'family': TasteGenre.family,
    'familial': TasteGenre.family,
    'famille': TasteGenre.family,
    'fantasy': TasteGenre.fantasy,
    'fantastique': TasteGenre.fantasy,
    'history': TasteGenre.history,
    'histoire': TasteGenre.history,
    'horror': TasteGenre.horror,
    'horreur': TasteGenre.horror,
    'kids': TasteGenre.kids,
    'enfants': TasteGenre.kids,
    'children': TasteGenre.kids,
    'music': TasteGenre.music,
    'musique': TasteGenre.music,
    'musical': TasteGenre.music,
    'mystery': TasteGenre.mystery,
    'mystere': TasteGenre.mystery,
    'reality': TasteGenre.reality,
    'realite': TasteGenre.reality,
    'reality tv': TasteGenre.reality,
    'tele realite': TasteGenre.reality,
    'romance': TasteGenre.romance,
    'science fiction': TasteGenre.scifi,
    'sci fi': TasteGenre.scifi,
    'talk': TasteGenre.talk,
    'talk show': TasteGenre.talk,
    'soap': TasteGenre.talk,
    'feuilleton': TasteGenre.talk,
    'news': TasteGenre.talk,
    'actualites': TasteGenre.talk,
    'thriller': TasteGenre.thriller,
    'suspense': TasteGenre.thriller,
    'war': TasteGenre.war,
    'guerre': TasteGenre.war,
    'war politics': TasteGenre.war,
    'western': TasteGenre.western,
  };
}

/// Whether the viewer leans to movies, series, or neither.
enum TasteMediaPref { both, movies, series }

/// Whether the viewer leans to recent titles, to older ones, or neither.
enum TasteEra { any, recent, classic }

/// A mood the questionnaire offers, read as a few genres. The moods share no
/// genre, so one is chosen exactly when all of its genres are liked.
enum TasteMood {
  darkPlots({TasteGenre.crime, TasteGenre.thriller, TasteGenre.mystery}),
  adrenaline({
    TasteGenre.action,
    TasteGenre.adventure,
    TasteGenre.war,
    TasteGenre.western,
  }),
  imaginary({TasteGenre.scifi, TasteGenre.fantasy}),
  trueStories({TasteGenre.documentary, TasteGenre.history}),
  intenseDrama({TasteGenre.drama}),
  feelGood({TasteGenre.comedy, TasteGenre.romance, TasteGenre.music}),
  chills({TasteGenre.horror}),
  animated({TasteGenre.animation}),
  family({TasteGenre.family, TasteGenre.kids});

  final Set<TasteGenre> genres;

  const TasteMood(this.genres);
}

/// How long a film may run before it feels long.
enum TasteMovieLength { short, medium, long, any }

/// The shape of series the viewer settles into.
enum TasteSeriesFormat { mini, few, long, any }

/// How much violence is welcome.
enum TasteViolence { none, justified, fine }

/// How the viewer takes subtitles.
enum TasteSubtitles { never, depends, gladly }

/// The axes of taste the duels measure. Negative leans to the first pole,
/// positive to the second.
enum TasteAxis {
  /// Dark (-) or light (+).
  darkLight,

  /// Real (-) or imaginary (+).
  realImaginary,

  /// Slow and contemplative (-) or fast and tense (+).
  slowFast,

  /// Recent (-) or classic (+).
  recentClassic,

  /// Mainstream (-) or niche (+).
  popularNiche,

  /// Spectacle (-) or intimate (+).
  spectacleIntimate,
}

/// A title the questionnaire learned something about.
class TastePick {
  final int tmdbId;

  /// Seerr's media type, `movie` or `tv`.
  final String mediaType;
  final String title;
  final String? posterPath;
  final Set<TasteGenre> genres;

  const TastePick({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.posterPath,
    this.genres = const {},
  });

  String get key => '$mediaType:$tmdbId';

  Map<String, dynamic> toJson() => {
    'id': tmdbId,
    'type': mediaType,
    'title': title,
    'poster': ?posterPath,
    if (genres.isNotEmpty) 'genres': [for (final g in genres) g.name],
  };

  static TastePick? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final type = json['type'];
    if (id is! int || (type != 'movie' && type != 'tv')) return null;
    return TastePick(
      tmdbId: id,
      mediaType: type as String,
      title: json['title'] as String? ?? '',
      posterPath: json['poster'] as String?,
      genres: {
        if (json['genres'] case final List list)
          for (final name in list)
            if (name is String)
              if (TasteGenre.byName(name) case final genre?) genre,
      },
    );
  }
}

/// What the viewer told the questionnaire.
class TasteProfile {
  final TasteMediaPref mediaPref;
  final Set<TasteGenre> liked;
  final Set<TasteGenre> avoided;

  /// ISO 639-1 codes. Empty means any language.
  final Set<String> languages;

  /// Titles seen and liked.
  final List<TastePick> favorites;
  final TasteEra era;

  /// The all-time favourites: the strongest signal there is.
  final List<TastePick> pivots;

  /// Titles seen and found so-so.
  final List<TastePick> meh;

  /// Titles seen and disliked.
  final List<TastePick> disliked;

  /// Who the viewer usually watches with: `alone`, `couple`, `family`,
  /// `friends`.
  final Set<String> contexts;

  /// The youngest child's age band when watching as a family: `under7`,
  /// `from7to12` or `teen`.
  final String? kidsAge;
  final TasteMovieLength movieLength;
  final TasteSeriesFormat seriesFormat;

  /// Where each duel landed, from -2 to 2. Missing means not asked or no
  /// preference.
  final Map<TasteAxis, double> axes;
  final TasteViolence violence;
  final TasteSubtitles subtitles;

  /// Fond of Japanese animation.
  final bool anime;

  /// Glad to be shown cinemas outside the usual ones.
  final bool surpriseMe;

  /// When the questionnaire was last completed, or null if never.
  final DateTime? updatedAt;

  const TasteProfile({
    this.mediaPref = TasteMediaPref.both,
    this.era = TasteEra.any,
    this.liked = const {},
    this.avoided = const {},
    this.languages = const {},
    this.favorites = const [],
    this.pivots = const [],
    this.meh = const [],
    this.disliked = const [],
    this.contexts = const {},
    this.kidsAge,
    this.movieLength = TasteMovieLength.any,
    this.seriesFormat = TasteSeriesFormat.any,
    this.axes = const {},
    this.violence = TasteViolence.fine,
    this.subtitles = TasteSubtitles.depends,
    this.anime = false,
    this.surpriseMe = false,
    this.updatedAt,
  });

  static const empty = TasteProfile();

  bool get answered => updatedAt != null;

  /// Every title the questionnaire heard about: all of them were seen, so
  /// none is worth suggesting.
  Set<String> get seenKeys => {
    for (final p in favorites) p.key,
    for (final p in pivots) p.key,
    for (final p in meh) p.key,
    for (final p in disliked) p.key,
  };

  /// How much each genre is liked from the titles rated, about -1 to 1. A
  /// genre seen only once or twice stays close to neutral.
  Map<TasteGenre, double> get genreAffinity {
    final sum = <TasteGenre, double>{};
    final count = <TasteGenre, int>{};
    void add(List<TastePick> picks, double value) {
      for (final pick in picks) {
        for (final genre in pick.genres) {
          sum[genre] = (sum[genre] ?? 0) + value;
          count[genre] = (count[genre] ?? 0) + 1;
        }
      }
    }

    add(pivots, 2);
    add(favorites, 1);
    add(meh, -0.3);
    add(disliked, -1);
    const prior = 3;
    return {
      for (final genre in sum.keys)
        genre: (sum[genre]! / (count[genre]! + prior)).clamp(-1.0, 1.0),
    };
  }

  TasteProfile copyWith({
    TasteMediaPref? mediaPref,
    TasteEra? era,
    Set<TasteGenre>? liked,
    Set<TasteGenre>? avoided,
    Set<String>? languages,
    List<TastePick>? favorites,
    List<TastePick>? pivots,
    List<TastePick>? meh,
    List<TastePick>? disliked,
    Set<String>? contexts,
    String? kidsAge,
    TasteMovieLength? movieLength,
    TasteSeriesFormat? seriesFormat,
    Map<TasteAxis, double>? axes,
    TasteViolence? violence,
    TasteSubtitles? subtitles,
    bool? anime,
    bool? surpriseMe,
    DateTime? updatedAt,
  }) => TasteProfile(
    mediaPref: mediaPref ?? this.mediaPref,
    era: era ?? this.era,
    liked: liked ?? this.liked,
    avoided: avoided ?? this.avoided,
    languages: languages ?? this.languages,
    favorites: favorites ?? this.favorites,
    pivots: pivots ?? this.pivots,
    meh: meh ?? this.meh,
    disliked: disliked ?? this.disliked,
    contexts: contexts ?? this.contexts,
    kidsAge: kidsAge ?? this.kidsAge,
    movieLength: movieLength ?? this.movieLength,
    seriesFormat: seriesFormat ?? this.seriesFormat,
    axes: axes ?? this.axes,
    violence: violence ?? this.violence,
    subtitles: subtitles ?? this.subtitles,
    anime: anime ?? this.anime,
    surpriseMe: surpriseMe ?? this.surpriseMe,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'media': mediaPref.name,
    'era': era.name,
    'liked': [for (final g in liked) g.name],
    'avoided': [for (final g in avoided) g.name],
    'languages': languages.toList(),
    'favorites': [for (final f in favorites) f.toJson()],
    if (pivots.isNotEmpty) 'pivots': [for (final f in pivots) f.toJson()],
    if (meh.isNotEmpty) 'meh': [for (final f in meh) f.toJson()],
    if (disliked.isNotEmpty) 'disliked': [for (final f in disliked) f.toJson()],
    if (contexts.isNotEmpty) 'contexts': contexts.toList(),
    'kids': ?kidsAge,
    'length': movieLength.name,
    'series': seriesFormat.name,
    if (axes.isNotEmpty)
      'axes': {for (final e in axes.entries) e.key.name: e.value},
    'violence': violence.name,
    'subtitles': subtitles.name,
    if (anime) 'anime': true,
    if (surpriseMe) 'surprise': true,
    'updatedAt': ?updatedAt?.toUtc().toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  /// Reads what [encode] wrote, or [empty] for anything unreadable.
  static TasteProfile decode(String? source) {
    if (source == null || source.isEmpty) return empty;
    try {
      final json = jsonDecode(source);
      if (json is! Map) return empty;
      Set<TasteGenre> genres(Object? list) => {
        if (list is List)
          for (final name in list)
            if (name is String)
              if (TasteGenre.byName(name) case final genre?) genre,
      };
      List<TastePick> picks(Object? list) => [
        if (list is List)
          for (final entry in list)
            if (TastePick.fromJson(entry) case final pick?) pick,
      ];
      T byName<T extends Enum>(List<T> values, Object? name, T fallback) =>
          values.asNameMap()[name] ?? fallback;
      return TasteProfile(
        mediaPref: byName(
          TasteMediaPref.values,
          json['media'],
          TasteMediaPref.both,
        ),
        era: byName(TasteEra.values, json['era'], TasteEra.any),
        liked: genres(json['liked']),
        avoided: genres(json['avoided']),
        languages: {
          if (json['languages'] case final List list)
            for (final code in list)
              if (code is String && code.isNotEmpty) code,
        },
        favorites: picks(json['favorites']),
        pivots: picks(json['pivots']),
        meh: picks(json['meh']),
        disliked: picks(json['disliked']),
        contexts: {
          if (json['contexts'] case final List list)
            for (final c in list)
              if (c is String) c,
        },
        kidsAge: json['kids'] as String?,
        movieLength: byName(
          TasteMovieLength.values,
          json['length'],
          TasteMovieLength.any,
        ),
        seriesFormat: byName(
          TasteSeriesFormat.values,
          json['series'],
          TasteSeriesFormat.any,
        ),
        axes: {
          if (json['axes'] case final Map map)
            for (final e in map.entries)
              if (TasteAxis.values.asNameMap()['${e.key}'] case final axis?)
                if (e.value is num) axis: (e.value as num).toDouble(),
        },
        violence: byName(
          TasteViolence.values,
          json['violence'],
          TasteViolence.fine,
        ),
        subtitles: byName(
          TasteSubtitles.values,
          json['subtitles'],
          TasteSubtitles.depends,
        ),
        anime: json['anime'] == true,
        surpriseMe: json['surprise'] == true,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      );
    } catch (_) {
      return empty;
    }
  }
}

/// What the viewer turned down from the suggestions.
class TasteFeedback {
  /// Titles never to suggest again, by `movie:603` style keys.
  final List<String> hidden;

  /// How many turned-down titles carried each genre.
  final Map<TasteGenre, int> genrePenalties;

  const TasteFeedback({this.hidden = const [], this.genrePenalties = const {}});

  static const empty = TasteFeedback();

  /// Hidden titles kept, newest last. Older ones fall off past this.
  static const maxHidden = 500;

  Set<String> get hiddenKeys => hidden.toSet();

  /// Records that a title with [genres] was turned down.
  TasteFeedback notInterested(String key, Set<TasteGenre> genres) {
    final keys = [...hidden.where((k) => k != key), key];
    final penalties = {...genrePenalties};
    for (final genre in genres) {
      penalties[genre] = (penalties[genre] ?? 0) + 1;
    }
    return TasteFeedback(
      hidden: keys.length > maxHidden
          ? keys.sublist(keys.length - maxHidden)
          : keys,
      genrePenalties: penalties,
    );
  }

  String encode() => jsonEncode({
    'hidden': hidden,
    'penalties': {
      for (final entry in genrePenalties.entries) entry.key.name: entry.value,
    },
  });

  static TasteFeedback decode(String? source) {
    if (source == null || source.isEmpty) return empty;
    try {
      final json = jsonDecode(source);
      if (json is! Map) return empty;
      return TasteFeedback(
        hidden: [
          if (json['hidden'] case final List list)
            for (final key in list)
              if (key is String) key,
        ],
        genrePenalties: {
          if (json['penalties'] case final Map map)
            for (final entry in map.entries)
              if (TasteGenre.byName('${entry.key}') case final genre?)
                if (entry.value is int) genre: entry.value as int,
        },
      );
    } catch (_) {
      return empty;
    }
  }
}

/// How much [profile] and [feedback] want [item], as a factor on its score.
/// Zero means never show it: one of its genres is on the avoid list.
///
/// Everything else nudges rather than rules: a liked genre lifts a title, a
/// title outside the chosen languages or media type sinks without vanishing,
/// so a row never empties because the answers were strict.
double tasteFactor(
  SeerrDiscoverItem item,
  String mediaType,
  TasteProfile profile,
  TasteFeedback feedback, {
  DateTime? now,
}) => tasteFactorFor(
  genres: TasteGenre.of(item.genreIds, mediaType),
  mediaType: mediaType,
  language: item.originalLanguage,
  year: _releaseYear(item),
  voteCount: item.voteCount,
  profile: profile,
  feedback: feedback,
  now: now,
);

const _darkGenres = {
  TasteGenre.horror,
  TasteGenre.thriller,
  TasteGenre.crime,
  TasteGenre.war,
};
const _lightGenres = {
  TasteGenre.comedy,
  TasteGenre.family,
  TasteGenre.animation,
  TasteGenre.kids,
};
const _realGenres = {
  TasteGenre.documentary,
  TasteGenre.history,
  TasteGenre.drama,
  TasteGenre.crime,
  TasteGenre.war,
};
const _imaginaryGenres = {
  TasteGenre.fantasy,
  TasteGenre.scifi,
  TasteGenre.animation,
};
const _fastGenres = {
  TasteGenre.action,
  TasteGenre.thriller,
  TasteGenre.horror,
};
const _spectacleGenres = {
  TasteGenre.adventure,
  TasteGenre.action,
  TasteGenre.scifi,
  TasteGenre.fantasy,
};
const _intimateGenres = {TasteGenre.drama, TasteGenre.romance};

/// Where a title sits on [axis], from -1 (first pole) to 1 (second pole),
/// or 0 when its genres, year and votes don't say.
double tasteAxisPosition(
  TasteAxis axis, {
  required Set<TasteGenre> genres,
  int? year,
  int? voteCount,
  DateTime? now,
}) {
  bool any(Set<TasteGenre> set) => genres.any(set.contains);
  switch (axis) {
    case TasteAxis.darkLight:
      final dark = any(_darkGenres);
      final light = any(_lightGenres);
      if (dark == light) return 0;
      return dark ? -1 : 1;
    case TasteAxis.realImaginary:
      final real = any(_realGenres);
      final imaginary = any(_imaginaryGenres);
      if (real == imaginary) return 0;
      return real ? -1 : 1;
    case TasteAxis.slowFast:
      if (any(_fastGenres)) return 1;
      if (genres.contains(TasteGenre.drama) ||
          genres.contains(TasteGenre.documentary)) {
        return -1;
      }
      return 0;
    case TasteAxis.recentClassic:
      if (year == null) return 0;
      final age = (now ?? DateTime.now()).year - year;
      if (age <= 5) return -1;
      if (age >= 25) return 1;
      return 0;
    case TasteAxis.popularNiche:
      if (voteCount == null) return 0;
      if (voteCount >= 10000) return -1;
      if (voteCount < 1500) return 1;
      return 0;
    case TasteAxis.spectacleIntimate:
      final spectacle = any(_spectacleGenres);
      final intimate = any(_intimateGenres);
      if (spectacle == intimate) return 0;
      return spectacle ? -1 : 1;
  }
}

/// [tasteFactor] for anything that knows its genres, wherever it came from:
/// a Seerr suggestion or a title already in the library.
double tasteFactorFor({
  required Set<TasteGenre> genres,
  required String mediaType,
  required TasteProfile profile,
  required TasteFeedback feedback,
  String? language,
  int? year,
  int? voteCount,
  DateTime? now,
}) {
  if (genres.any(profile.avoided.contains)) return 0;
  if (profile.violence == TasteViolence.none &&
      genres.contains(TasteGenre.horror)) {
    return 0;
  }
  final foreign =
      language != null &&
      language.isNotEmpty &&
      language != 'fr' &&
      language != 'en';
  if (profile.subtitles == TasteSubtitles.never && foreign) return 0;

  var factor = 1.0;

  switch (profile.mediaPref) {
    case TasteMediaPref.movies when mediaType == 'tv':
    case TasteMediaPref.series when mediaType == 'movie':
      factor *= 0.45;
    default:
      break;
  }

  if (profile.liked.isNotEmpty) {
    final matches = genres.where(profile.liked.contains).length;
    factor *= matches == 0 ? 0.8 : 1 + 0.3 * math.min(matches, 2);
  }

  // What the rated titles say about each genre.
  final affinity = profile.genreAffinity;
  if (affinity.isNotEmpty && genres.isNotEmpty) {
    var total = 0.0;
    var known = 0;
    for (final genre in genres) {
      final value = affinity[genre];
      if (value == null) continue;
      total += value;
      known++;
    }
    if (known > 0) {
      factor *= math.exp(0.4 * total / known).clamp(0.6, 1.5);
    }
  }

  if (profile.languages.isNotEmpty && language != null && language.isNotEmpty) {
    if (profile.languages.contains(language)) {
      factor *= 1.15;
    } else if (!profile.surpriseMe) {
      factor *= 0.7;
    }
  }
  if (profile.subtitles == TasteSubtitles.gladly && foreign) factor *= 1.08;
  if (profile.anime &&
      language == 'ja' &&
      genres.contains(TasteGenre.animation)) {
    factor *= 1.25;
  }

  switch (profile.violence) {
    case TasteViolence.none:
      if (genres.any(
        {TasteGenre.war, TasteGenre.crime, TasteGenre.thriller}.contains,
      )) {
        factor *= 0.75;
      }
    case TasteViolence.justified:
      if (genres.contains(TasteGenre.horror)) factor *= 0.75;
    case TasteViolence.fine:
      break;
  }

  if (profile.era != TasteEra.any && year != null) {
    final thisYear = (now ?? DateTime.now()).year;
    final recent = year >= thisYear - 8;
    final old = year <= thisYear - 20;
    if (profile.era == TasteEra.recent) {
      if (recent) factor *= 1.12;
      if (old) factor *= 0.8;
    } else {
      if (old) factor *= 1.25;
      if (recent) factor *= 0.85;
    }
  }

  // Each duel nudges up to 16% either way.
  for (final entry in profile.axes.entries) {
    if (entry.value == 0) continue;
    final position = tasteAxisPosition(
      entry.key,
      genres: genres,
      year: year,
      voteCount: voteCount,
      now: now,
    );
    if (position == 0) continue;
    factor *= 1 + 0.08 * entry.value.clamp(-2.0, 2.0) * position;
  }

  var penalty = 1.0;
  for (final genre in genres) {
    final count = feedback.genrePenalties[genre] ?? 0;
    if (count > 0) penalty *= math.pow(0.82, count).toDouble();
  }
  factor *= math.max(penalty, 0.3);

  return factor;
}

int? _releaseYear(SeerrDiscoverItem item) {
  final date = item.releaseDate ?? item.firstAirDate;
  if (date == null || date.length < 4) return null;
  return int.tryParse(date.substring(0, 4));
}
