/// VJOD's own collections: themed shelves that mix what the library holds
/// with everything else one request away, all drawn from Seerr's discover
/// search with a rule per collection.
library;

/// The Seerr browse filter type that opens a VJOD collection.
const vjodFilterType = 'vjod';

/// The groups the Explorer page shows, in its order.
enum VjodFamily { ready, ambiances, themes, series, platforms, studios, world }

/// One Seerr discover search. Every field maps to a parameter Seerr's
/// `discover/movies` or `discover/tv` route takes.
class VjodQuery {
  /// `movie` or `tv`.
  final String mediaType;

  /// TMDB genre ids, `,` for all of them, `|` for any.
  final String? genre;

  /// A TMDB keyword, by name: looked up once, since ids are what Seerr takes.
  final String? keyword;
  final int? studio;
  final int? network;

  /// The original language, ISO 639-1.
  final String? language;
  final double? voteAverageGte;
  final int? voteCountGte;
  final int? runtimeGte;
  final int? runtimeLte;

  /// `YYYY-MM-DD`, on the release date for films, first air date for series.
  final String? dateGte;
  final String? dateLte;

  /// TMDB series statuses, pipe joined (0 returning, 3 ended).
  final String? status;
  final String sortBy;

  const VjodQuery({
    this.mediaType = 'movie',
    this.genre,
    this.keyword,
    this.studio,
    this.network,
    this.language,
    this.voteAverageGte,
    this.voteCountGte,
    this.runtimeGte,
    this.runtimeLte,
    this.dateGte,
    this.dateLte,
    this.status,
    this.sortBy = 'popularity.desc',
  });
}

class VjodCollection {
  final String id;
  final VjodFamily family;
  final String titleFr;
  final String titleEn;
  final String subtitleFr;
  final String subtitleEn;
  final VjodQuery query;

  /// Months (1 to 12) the collection belongs to. Empty means all year.
  final Set<int> months;

  /// Only what the library holds: ready to play tonight.
  bool get readyOnly => family == VjodFamily.ready;

  const VjodCollection({
    required this.id,
    required this.family,
    required this.titleFr,
    required this.titleEn,
    this.subtitleFr = '',
    this.subtitleEn = '',
    required this.query,
    this.months = const {},
  });

  String title(bool french) => french ? titleFr : titleEn;
  String subtitle(bool french) => french ? subtitleFr : subtitleEn;

  bool inSeason(DateTime now) => months.isEmpty || months.contains(now.month);
}

String vjodFamilyTitle(VjodFamily family, bool french) => switch (family) {
  VjodFamily.ready => french ? 'Prêt à lancer' : 'Ready to play',
  VjodFamily.ambiances => french ? 'Ambiances' : 'Moods',
  VjodFamily.themes => french ? 'Thèmes' : 'Themes',
  VjodFamily.series => french ? 'Séries' : 'Series',
  VjodFamily.platforms => french ? 'Plateformes' : 'Streaming services',
  VjodFamily.studios => 'Studios',
  VjodFamily.world => french ? 'Tour du monde' : 'Around the world',
};

/// Every collection, in the order Explorer lists them.
const vjodCollections = <VjodCollection>[
  // Ready to play: what the server already holds.
  VjodCollection(
    id: 'gems',
    family: VjodFamily.ready,
    titleFr: 'Pépites jamais vues',
    titleEn: 'Unwatched gems',
    subtitleFr: 'Les mieux notés du serveur, pas encore vus',
    subtitleEn: 'The best rated on the server, not seen yet',
    query: VjodQuery(voteAverageGte: 7.5, voteCountGte: 1000, sortBy: 'vote_average.desc'),
  ),
  VjodCollection(
    id: 'short_gems',
    family: VjodFamily.ready,
    titleFr: 'Petit film, grosse claque',
    titleEn: 'Short and brilliant',
    subtitleFr: 'Moins d\'1 h 40 et excellent',
    subtitleEn: 'Under 1h40 and excellent',
    query: VjodQuery(runtimeGte: 60, runtimeLte: 100, voteAverageGte: 7.3, voteCountGte: 1000, sortBy: 'vote_average.desc'),
  ),

  // Moods.
  VjodCollection(
    id: 'feel_good',
    family: VjodFamily.ambiances,
    titleFr: 'Feel good',
    titleEn: 'Feel good',
    subtitleFr: 'Des films qui font du bien',
    subtitleEn: 'Films that lift you up',
    query: VjodQuery(genre: '35|10751|10402', voteAverageGte: 6.8, voteCountGte: 800),
  ),
  VjodCollection(
    id: 'popcorn',
    family: VjodFamily.ambiances,
    titleFr: 'Mode pop-corn',
    titleEn: 'Popcorn mode',
    subtitleFr: 'Action et aventure efficaces, moins de 2 h',
    subtitleEn: 'Action and adventure under 2 hours',
    query: VjodQuery(genre: '28|12', voteAverageGte: 6.3, voteCountGte: 2000, runtimeLte: 120),
  ),
  VjodCollection(
    id: 'tearjerkers',
    family: VjodFamily.ambiances,
    titleFr: 'Mouchoirs obligatoires',
    titleEn: 'Bring tissues',
    subtitleFr: 'Les drames qui serrent la gorge',
    subtitleEn: 'Dramas that hit hard',
    query: VjodQuery(genre: '18,10749', voteAverageGte: 7.2, voteCountGte: 800),
  ),
  VjodCollection(
    id: 'mind_benders',
    family: VjodFamily.ambiances,
    titleFr: 'Ça retourne le cerveau',
    titleEn: 'Mind benders',
    subtitleFr: 'Science-fiction et mystères à twist',
    subtitleEn: 'Twisty science fiction and mysteries',
    query: VjodQuery(genre: '878|9648', voteAverageGte: 7.3, voteCountGte: 1500),
  ),
  VjodCollection(
    id: 'sleepless',
    family: VjodFamily.ambiances,
    titleFr: 'Nuit blanche',
    titleEn: 'Sleepless night',
    subtitleFr: 'L\'horreur qui fait vraiment peur',
    subtitleEn: 'Horror that really scares',
    query: VjodQuery(genre: '27', voteAverageGte: 6.6, voteCountGte: 800),
  ),
  VjodCollection(
    id: 'epic',
    family: VjodFamily.ambiances,
    titleFr: 'Grand spectacle',
    titleEn: 'Epic cinema',
    subtitleFr: 'À voir sur le plus grand écran',
    subtitleEn: 'Made for the biggest screen',
    query: VjodQuery(genre: '12|28|878|14|10752|36', runtimeGte: 130, voteAverageGte: 7.2, voteCountGte: 3000),
  ),
  VjodCollection(
    id: 'family',
    family: VjodFamily.ambiances,
    titleFr: 'Soirée en famille',
    titleEn: 'Family night',
    subtitleFr: 'Pour tous les âges',
    subtitleEn: 'For every age',
    query: VjodQuery(genre: '10751|16', voteAverageGte: 6.8, voteCountGte: 800),
  ),
  VjodCollection(
    id: 'classics',
    family: VjodFamily.ambiances,
    titleFr: 'Grands classiques',
    titleEn: 'Great classics',
    subtitleFr: 'Les incontournables d\'avant 1985',
    subtitleEn: 'Must-sees from before 1985',
    query: VjodQuery(dateLte: '1984-12-31', voteAverageGte: 7.8, voteCountGte: 1500, sortBy: 'vote_average.desc'),
  ),

  // Themes, by TMDB keyword.
  VjodCollection(
    id: 'heist',
    family: VjodFamily.themes,
    titleFr: 'Casses et braquages',
    titleEn: 'Heists',
    query: VjodQuery(keyword: 'heist', voteCountGte: 300),
  ),
  VjodCollection(
    id: 'time_travel',
    family: VjodFamily.themes,
    titleFr: 'Voyages dans le temps',
    titleEn: 'Time travel',
    query: VjodQuery(keyword: 'time travel', voteCountGte: 300),
  ),
  VjodCollection(
    id: 'space',
    family: VjodFamily.themes,
    titleFr: 'Perdus dans l\'espace',
    titleEn: 'Lost in space',
    query: VjodQuery(keyword: 'space travel', voteCountGte: 300),
  ),
  VjodCollection(
    id: 'apocalypse',
    family: VjodFamily.themes,
    titleFr: 'Fin du monde',
    titleEn: 'End of the world',
    query: VjodQuery(keyword: 'post-apocalyptic future', voteCountGte: 300),
  ),
  VjodCollection(
    id: 'zombies',
    family: VjodFamily.themes,
    titleFr: 'Zombies',
    titleEn: 'Zombies',
    query: VjodQuery(keyword: 'zombie', voteCountGte: 300),
  ),
  VjodCollection(
    id: 'serial_killer',
    family: VjodFamily.themes,
    titleFr: 'Dans la tête d\'un tueur',
    titleEn: 'Inside a killer\'s mind',
    query: VjodQuery(keyword: 'serial killer', voteCountGte: 300),
  ),
  VjodCollection(
    id: 'mafia',
    family: VjodFamily.themes,
    titleFr: 'Mafia et gangsters',
    titleEn: 'Mob stories',
    query: VjodQuery(keyword: 'mafia', voteCountGte: 300),
  ),
  VjodCollection(
    id: 'prison_escape',
    family: VjodFamily.themes,
    titleFr: 'Évasions',
    titleEn: 'Great escapes',
    query: VjodQuery(keyword: 'prison escape', voteCountGte: 200),
  ),
  VjodCollection(
    id: 'ai',
    family: VjodFamily.themes,
    titleFr: 'Machines et IA',
    titleEn: 'Machines and AI',
    query: VjodQuery(keyword: 'artificial intelligence (a.i.)', voteCountGte: 300),
  ),
  VjodCollection(
    id: 'true_story',
    family: VjodFamily.themes,
    titleFr: 'Histoires vraies',
    titleEn: 'True stories',
    query: VjodQuery(keyword: 'based on true story', voteAverageGte: 6.8, voteCountGte: 800),
  ),
  VjodCollection(
    id: 'superheroes',
    family: VjodFamily.themes,
    titleFr: 'Super-héros',
    titleEn: 'Superheroes',
    query: VjodQuery(keyword: 'superhero', voteCountGte: 1000),
  ),
  VjodCollection(
    id: 'christmas',
    family: VjodFamily.themes,
    titleFr: 'Films de Noël',
    titleEn: 'Christmas films',
    query: VjodQuery(keyword: 'christmas', voteCountGte: 300),
    months: {11, 12},
  ),
  VjodCollection(
    id: 'halloween',
    family: VjodFamily.themes,
    titleFr: 'Frissons d\'Halloween',
    titleEn: 'Halloween chills',
    query: VjodQuery(keyword: 'halloween', voteCountGte: 200),
    months: {10},
  ),

  // Series.
  VjodCollection(
    id: 'binge',
    family: VjodFamily.series,
    titleFr: 'À binger ce week-end',
    titleEn: 'Weekend binge',
    subtitleFr: 'Séries terminées et excellentes',
    subtitleEn: 'Finished, excellent series',
    query: VjodQuery(mediaType: 'tv', status: '3', voteAverageGte: 8, voteCountGte: 300),
  ),
  VjodCollection(
    id: 'miniseries',
    family: VjodFamily.series,
    titleFr: 'Mini-séries à binger',
    titleEn: 'Miniseries',
    subtitleFr: 'Une histoire complète en quelques épisodes',
    subtitleEn: 'A whole story in a few episodes',
    query: VjodQuery(mediaType: 'tv', keyword: 'miniseries', voteAverageGte: 7.5, voteCountGte: 200),
  ),
  VjodCollection(
    id: 'half_hour',
    family: VjodFamily.series,
    titleFr: 'Épisodes de 30 min',
    titleEn: 'Half-hour episodes',
    subtitleFr: 'Un épisode avant de dormir',
    subtitleEn: 'One before bed',
    query: VjodQuery(mediaType: 'tv', genre: '35', runtimeLte: 35, voteAverageGte: 7.5, voteCountGte: 300),
  ),
  VjodCollection(
    id: 'airing',
    family: VjodFamily.series,
    titleFr: 'Toujours en cours',
    titleEn: 'Still airing',
    subtitleFr: 'Les séries qui continuent',
    subtitleEn: 'Series still going',
    query: VjodQuery(mediaType: 'tv', status: '0', voteAverageGte: 7.5, voteCountGte: 300),
  ),
  VjodCollection(
    id: 'hbo',
    family: VjodFamily.platforms,
    titleFr: 'Séries HBO',
    titleEn: 'HBO series',
    query: VjodQuery(mediaType: 'tv', network: 49, voteCountGte: 200),
  ),
  VjodCollection(
    id: 'netflix',
    family: VjodFamily.platforms,
    titleFr: 'Séries Netflix',
    titleEn: 'Netflix series',
    query: VjodQuery(mediaType: 'tv', network: 213, voteCountGte: 200),
  ),

  // Streaming services.
  VjodCollection(
    id: 'disneyplus',
    family: VjodFamily.platforms,
    titleFr: 'Séries Disney+',
    titleEn: 'Disney+ series',
    query: VjodQuery(mediaType: 'tv', network: 2739, voteCountGte: 100),
  ),
  VjodCollection(
    id: 'prime',
    family: VjodFamily.platforms,
    titleFr: 'Séries Prime Video',
    titleEn: 'Prime Video series',
    query: VjodQuery(mediaType: 'tv', network: 1024, voteCountGte: 100),
  ),
  VjodCollection(
    id: 'appletv',
    family: VjodFamily.platforms,
    titleFr: 'Séries Apple TV+',
    titleEn: 'Apple TV+ series',
    query: VjodQuery(mediaType: 'tv', network: 2552, voteCountGte: 100),
  ),
  VjodCollection(
    id: 'paramountplus',
    family: VjodFamily.platforms,
    titleFr: 'Séries Paramount+',
    titleEn: 'Paramount+ series',
    query: VjodQuery(mediaType: 'tv', network: 4330, voteCountGte: 100),
  ),
  VjodCollection(
    id: 'hulu',
    family: VjodFamily.platforms,
    titleFr: 'Séries Hulu',
    titleEn: 'Hulu series',
    query: VjodQuery(mediaType: 'tv', network: 453, voteCountGte: 100),
  ),
  VjodCollection(
    id: 'peacock',
    family: VjodFamily.platforms,
    titleFr: 'Séries Peacock',
    titleEn: 'Peacock series',
    query: VjodQuery(mediaType: 'tv', network: 3353, voteCountGte: 100),
  ),
  VjodCollection(
    id: 'bbc',
    family: VjodFamily.platforms,
    titleFr: 'Séries BBC',
    titleEn: 'BBC series',
    query: VjodQuery(mediaType: 'tv', network: 4, voteCountGte: 100),
  ),

  // Studios.
  VjodCollection(
    id: 'pixar',
    family: VjodFamily.studios,
    titleFr: 'Pixar',
    titleEn: 'Pixar',
    query: VjodQuery(studio: 3),
  ),
  VjodCollection(
    id: 'ghibli',
    family: VjodFamily.studios,
    titleFr: 'Studio Ghibli',
    titleEn: 'Studio Ghibli',
    query: VjodQuery(studio: 10342),
  ),
  VjodCollection(
    id: 'a24',
    family: VjodFamily.studios,
    titleFr: 'A24',
    titleEn: 'A24',
    query: VjodQuery(studio: 41077, voteCountGte: 100),
  ),
  VjodCollection(
    id: 'disney',
    family: VjodFamily.studios,
    titleFr: 'Disney',
    titleEn: 'Disney',
    query: VjodQuery(studio: 2, voteCountGte: 200),
  ),
  VjodCollection(
    id: 'marvel',
    family: VjodFamily.studios,
    titleFr: 'Marvel Studios',
    titleEn: 'Marvel Studios',
    query: VjodQuery(studio: 420, voteCountGte: 200),
  ),
  VjodCollection(
    id: 'dc',
    family: VjodFamily.studios,
    titleFr: 'DC',
    titleEn: 'DC',
    query: VjodQuery(studio: 9993, voteCountGte: 200),
  ),
  VjodCollection(
    id: 'dreamworks',
    family: VjodFamily.studios,
    titleFr: 'DreamWorks',
    titleEn: 'DreamWorks',
    query: VjodQuery(studio: 521, voteCountGte: 200),
  ),
  VjodCollection(
    id: 'warner',
    family: VjodFamily.studios,
    titleFr: 'Warner Bros.',
    titleEn: 'Warner Bros.',
    query: VjodQuery(studio: 174, voteCountGte: 200),
  ),
  VjodCollection(
    id: 'universal',
    family: VjodFamily.studios,
    titleFr: 'Universal',
    titleEn: 'Universal',
    query: VjodQuery(studio: 33, voteCountGte: 200),
  ),
  VjodCollection(
    id: 'paramount',
    family: VjodFamily.studios,
    titleFr: 'Paramount',
    titleEn: 'Paramount',
    query: VjodQuery(studio: 4, voteCountGte: 200),
  ),
  VjodCollection(
    id: 'sony',
    family: VjodFamily.studios,
    titleFr: 'Sony Pictures',
    titleEn: 'Sony Pictures',
    query: VjodQuery(studio: 34, voteCountGte: 200),
  ),
  VjodCollection(
    id: 'fox',
    family: VjodFamily.studios,
    titleFr: '20th Century Studios',
    titleEn: '20th Century Studios',
    query: VjodQuery(studio: 127928, voteCountGte: 200),
  ),

  // Around the world, by original language.
  VjodCollection(
    id: 'french',
    family: VjodFamily.world,
    titleFr: 'Le meilleur du cinéma français',
    titleEn: 'The best of French cinema',
    query: VjodQuery(language: 'fr', voteAverageGte: 7, voteCountGte: 300),
  ),
  VjodCollection(
    id: 'russian',
    family: VjodFamily.world,
    titleFr: 'Cinéma russe et soviétique',
    titleEn: 'Russian and Soviet cinema',
    query: VjodQuery(language: 'ru', voteAverageGte: 6.5, voteCountGte: 100),
  ),
  VjodCollection(
    id: 'korean',
    family: VjodFamily.world,
    titleFr: 'Cinéma coréen',
    titleEn: 'Korean cinema',
    query: VjodQuery(language: 'ko', voteAverageGte: 7, voteCountGte: 200),
  ),
  VjodCollection(
    id: 'japanese',
    family: VjodFamily.world,
    titleFr: 'Cinéma japonais',
    titleEn: 'Japanese cinema',
    query: VjodQuery(language: 'ja', voteAverageGte: 7, voteCountGte: 300),
  ),
];

VjodCollection? vjodCollectionById(String? id) {
  for (final c in vjodCollections) {
    if (c.id == id) return c;
  }
  return null;
}

/// The themes the Theme of the day rotates through, in season.
List<VjodCollection> vjodThemesInSeason(DateTime now) => [
  for (final c in vjodCollections)
    if (c.family == VjodFamily.themes && c.inSeason(now)) c,
];

/// Today's theme: one a day, the same all day, cycling through the themes in
/// season. A theme tied to the season (Christmas, Halloween) wins its months.
VjodCollection vjodThemeOfDay(DateTime now) {
  final themes = vjodThemesInSeason(now);
  final seasonal = themes.where((c) => c.months.isNotEmpty).toList();
  if (seasonal.isNotEmpty && now.day.isEven) return seasonal.first;
  final dayIndex = DateTime(now.year, now.month, now.day)
      .difference(DateTime(2026))
      .inDays;
  final yearRound = themes.where((c) => c.months.isEmpty).toList();
  return yearRound[dayIndex.abs() % yearRound.length];
}

/// Today's mood row: one of the moods a day, the same all day, skipping the
/// ones that already have a row of their own on Home ([onHome]) and the
/// ones that only hold what the library has. Null when none is left.
VjodCollection? vjodAmbianceOfDay(DateTime now, {Set<String> onHome = const {}}) {
  final moods = [
    for (final c in vjodCollections)
      if (c.family == VjodFamily.ambiances &&
          !c.readyOnly &&
          c.inSeason(now) &&
          !onHome.contains(c.id))
        c,
  ];
  if (moods.isEmpty) return null;
  final dayIndex = DateTime(now.year, now.month, now.day)
      .difference(DateTime(2026))
      .inDays;
  // Offset from the theme's cycle, so the two rows don't change in step.
  return moods[(dayIndex.abs() + 3) % moods.length];
}

/// The name a VJOD home row goes by in the settings: its collection's, or
/// "Thème du jour" for the row that changes every day.
String vjodSectionLabel(String? collectionId, bool french) {
  final collection = vjodCollectionById(collectionId);
  if (collection != null) return 'VJOD · ${collection.title(french)}';
  return french ? 'VJOD · Thème du jour' : 'VJOD · Theme of the day';
}
