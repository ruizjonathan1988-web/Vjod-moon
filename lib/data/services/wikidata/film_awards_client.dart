import 'package:dio/dio.dart';

/// The awards that make a French film "primé", as Wikidata names them: the
/// César for best film and for best first film, the Louis-Delluc prize, and
/// the top prize of Cannes, Venice and Berlin.
const _cesarBestFilm = 'wd:Q645595';
const _cesarFirstFilm = 'wd:Q655056';
const _louisDelluc = 'wd:Q734335';
const _palmeDOr = 'wd:Q179808';
const _goldenLion = 'wd:Q209459';
const _goldenBear = 'wd:Q154590';

/// Films with one of those awards, as TMDB ids, the most recently awarded
/// first. The French awards count whatever the film; the festivals only
/// when France is among the film's countries.
const _frenchWinnersQuery =
    '''
SELECT ?tmdb (MAX(?year) AS ?latest) WHERE {
  VALUES ?award { $_cesarBestFilm $_cesarFirstFilm $_louisDelluc $_palmeDOr $_goldenLion $_goldenBear }
  ?film p:P166 ?won .
  ?won ps:P166 ?award .
  OPTIONAL { ?won pq:P585 ?date . BIND(YEAR(?date) AS ?year) }
  ?film wdt:P4947 ?tmdb .
  FILTER(?award IN ($_cesarBestFilm, $_cesarFirstFilm, $_louisDelluc) || EXISTS { ?film wdt:P495 wd:Q142 })
}
GROUP BY ?tmdb
ORDER BY DESC(?latest)
LIMIT 40
''';

/// French film awards, from Wikidata's open database. No key needed.
class FilmAwardsClient {
  FilmAwardsClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://query.wikidata.org',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'Accept': 'application/sparql-results+json',
                // Wikidata asks every client to say who it is.
                'User-Agent': 'Moonfin-perso/1.0 (personal Jellyfin client)',
              },
            ),
          );

  final Dio _dio;

  /// The list changes once a year at most, so it is asked once per run.
  List<int>? _frenchWinners;

  /// The TMDB ids of award-winning French films, the latest winners first.
  Future<List<int>> frenchWinners() async {
    final known = _frenchWinners;
    if (known != null) return known;
    final response = await _dio.get<Object?>(
      '/sparql',
      queryParameters: {'query': _frenchWinnersQuery, 'format': 'json'},
    );
    final winners = parseAwardWinners(response.data);
    if (winners.isNotEmpty) _frenchWinners = winners;
    return winners;
  }
}

/// The TMDB ids in Wikidata's answer, in its order, each once.
List<int> parseAwardWinners(Object? json) {
  final results = json is Map ? json['results'] : null;
  final bindings = results is Map ? results['bindings'] : null;
  if (bindings is! List) return const [];
  final ids = <int>[];
  for (final row in bindings) {
    final tmdb = row is Map ? row['tmdb'] : null;
    final value = tmdb is Map ? tmdb['value'] : null;
    final id = value is String ? int.tryParse(value) : null;
    if (id != null && id > 0 && !ids.contains(id)) ids.add(id);
  }
  return ids;
}
