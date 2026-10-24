import 'package:flutter/foundation.dart';

import '../../repositories/seerr_repository.dart';
import 'seerr_api_models.dart';
import 'taste_quiz.dart';

/// Gathers the titles the questionnaire shows: the most voted of all time,
/// what is popular now, classics, recent hits, and well-known titles from
/// France, Korea and Japan, movies and series. Each list is asked for on its
/// own, so one the server can't give doesn't take the others down.
Future<List<QuizTitle>> loadQuizPool(SeerrRepository repo, {DateTime? now}) async {
  final year = (now ?? DateTime.now()).year;

  Future<List<QuizTitle>> list(
    Future<SeerrDiscoverPage> Function() call,
    String type,
  ) async {
    try {
      final page = await call().timeout(const Duration(seconds: 10));
      return [
        for (final item in page.results)
          if (!item.adult)
            if (QuizTitle.fromSeerr(item, type: type) case final title?) title,
      ];
    } catch (e) {
      debugPrint('[Taste] A quiz list failed: $e');
      return const [];
    }
  }

  final lists = await Future.wait([
    for (var page = 1; page <= 3; page++)
      list(
        () => repo.discoverMovies(page: page, sortBy: 'vote_count.desc'),
        'movie',
      ),
    for (var page = 1; page <= 2; page++)
      list(
        () => repo.discoverMovies(
          page: page,
          sortBy: 'popularity.desc',
          voteCountGte: 1500,
        ),
        'movie',
      ),
    list(
      () => repo.discoverMovies(
        sortBy: 'vote_count.desc',
        primaryReleaseDateLte: '1999-12-31',
      ),
      'movie',
    ),
    list(
      () => repo.discoverMovies(
        sortBy: 'vote_count.desc',
        primaryReleaseDateGte: '${year - 6}-01-01',
      ),
      'movie',
    ),
    for (var page = 1; page <= 2; page++)
      list(
        () => repo.discoverMovies(
          page: page,
          sortBy: 'vote_count.desc',
          language: 'fr',
        ),
        'movie',
      ),
    list(
      () => repo.discoverMovies(sortBy: 'vote_count.desc', language: 'ko'),
      'movie',
    ),
    list(
      () => repo.discoverMovies(
        sortBy: 'vote_count.desc',
        language: 'ja',
        genre: '16',
      ),
      'movie',
    ),
    list(
      () => repo.discoverMovies(
        sortBy: 'vote_average.desc',
        voteCountGte: 400,
        voteAverageGte: 7.4,
      ),
      'movie',
    ),
    for (var page = 1; page <= 2; page++)
      list(
        () => repo.discoverTv(page: page, sortBy: 'vote_count.desc'),
        'tv',
      ),
    list(
      () => repo.discoverTv(sortBy: 'popularity.desc', voteCountGte: 300),
      'tv',
    ),
    list(
      () => repo.discoverTv(sortBy: 'vote_count.desc', language: 'fr'),
      'tv',
    ),
  ]);

  final seen = <String>{};
  return [
    for (final titles in lists)
      for (final title in titles)
        if (seen.add(title.key)) title,
  ];
}

/// What TMDB recommends next to [title], as quiz titles.
Future<List<QuizTitle>> loadQuizRecommendations(
  SeerrRepository repo,
  QuizTitle title,
) async {
  try {
    final page = await (title.isMovie
            ? repo.getMovieRecommendations(title.tmdbId)
            : repo.getTvRecommendations(title.tmdbId))
        .timeout(const Duration(seconds: 8));
    return [
      for (final item in page.results)
        if (!item.adult)
          if (QuizTitle.fromSeerr(item, type: title.mediaType) case final t?) t,
    ];
  } catch (e) {
    debugPrint('[Taste] No recommendations for ${title.title}: $e');
    return const [];
  }
}

/// Titles matching [query], for picking an all-time favourite.
Future<List<QuizTitle>> searchQuizTitles(
  SeerrRepository repo,
  String query,
) async {
  if (query.trim().isEmpty) return const [];
  try {
    final page = await repo
        .search(query.trim())
        .timeout(const Duration(seconds: 8));
    return [
      for (final item in page.results)
        if (!item.adult)
          if (QuizTitle.fromSeerr(item) case final t?) t,
    ];
  } catch (e) {
    debugPrint('[Taste] Search failed: $e');
    return const [];
  }
}
