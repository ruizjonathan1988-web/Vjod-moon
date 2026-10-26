import '../../repositories/seerr_repository.dart';
import '../seerr/seerr_api_models.dart';
import 'vjod_collections.dart';

/// Reads a VJOD collection from Seerr: one page of its discover search, or a
/// row's worth with what the library holds put first.
abstract final class VjodCollectionService {
  /// One page of [collection]'s search, or null when its keyword is unknown
  /// to TMDB.
  static Future<SeerrDiscoverPage?> fetchPage(
    SeerrRepository repo,
    VjodCollection collection, {
    int page = 1,
  }) {
    // Home draws a dozen of these at once and again at every refresh: the
    // same page is asked of Seerr once per half hour.
    final key = '${collection.id}#$page';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _lifetime) {
      return hit.page;
    }
    final future = _fetchPage(repo, collection, page: page);
    _cache[key] = (at: DateTime.now(), page: future);
    future.then<void>((value) {
      if (value == null) _cache.remove(key);
    }, onError: (Object _) => _cache.remove(key));
    return future;
  }

  static const _lifetime = Duration(minutes: 30);
  static final Map<String, ({DateTime at, Future<SeerrDiscoverPage?> page})>
  _cache = {};

  /// Forgets what was kept, so the next read asks Seerr again.
  static void clearCache() => _cache.clear();

  static Future<SeerrDiscoverPage?> _fetchPage(
    SeerrRepository repo,
    VjodCollection collection, {
    int page = 1,
  }) async {
    final q = collection.query;
    int? keywordId;
    final keyword = q.keyword;
    if (keyword != null) {
      keywordId = await repo.keywordId(keyword);
      if (keywordId == null) return null;
    }
    if (q.mediaType == 'tv') {
      return repo.discoverTv(
        page: page,
        sortBy: q.sortBy,
        genre: q.genre,
        network: q.network,
        keywords: keywordId,
        language: q.language,
        status: q.status,
        voteAverageGte: q.voteAverageGte,
        voteCountGte: q.voteCountGte,
        withRuntimeGte: q.runtimeGte,
        withRuntimeLte: q.runtimeLte,
        firstAirDateGte: q.dateGte,
        firstAirDateLte: q.dateLte,
      );
    }
    return repo.discoverMovies(
      page: page,
      sortBy: q.sortBy,
      genre: q.genre,
      studio: q.studio,
      keywords: keywordId,
      language: q.language,
      voteAverageGte: q.voteAverageGte,
      voteCountGte: q.voteCountGte,
      withRuntimeGte: q.runtimeGte,
      withRuntimeLte: q.runtimeLte,
      primaryReleaseDateGte: q.dateGte,
      primaryReleaseDateLte: q.dateLte,
    );
  }

  /// A home row of [collection]: its first [pages] pages, each title once,
  /// what the library holds first, then what is on its way, then the rest,
  /// each group in Seerr's own order. [hidden] holds `movie:<id>` keys the
  /// viewer said no to.
  static Future<List<SeerrDiscoverItem>> loadRow(
    SeerrRepository repo,
    VjodCollection collection, {
    int pages = 2,
    Set<String> hidden = const {},
  }) async {
    final fetched = await Future.wait([
      for (var p = 1; p <= pages; p++)
        fetchPage(repo, collection, page: p).catchError((Object _) => null),
    ]);
    final seen = <int>{};
    final items = <SeerrDiscoverItem>[];
    for (final page in fetched) {
      if (page == null) continue;
      for (final item in page.results) {
        if (!seen.add(item.id)) continue;
        if (item.isBlacklisted) continue;
        if (hidden.contains('${collection.query.mediaType}:${item.id}')) {
          continue;
        }
        items.add(item);
      }
    }
    final ordered = availableFirst(items);
    if (collection.readyOnly) {
      return [
        for (final item in ordered)
          if (item.isAvailable) item,
      ];
    }
    return ordered;
  }

  /// Available, then requested or downloading, then the rest. Stable.
  static List<SeerrDiscoverItem> availableFirst(List<SeerrDiscoverItem> items) {
    int rank(SeerrDiscoverItem item) {
      final status = item.mediaInfo?.status;
      if (SeerrMediaStatus.isAvailable(status)) return 0;
      if (status == SeerrMediaStatus.pending ||
          status == SeerrMediaStatus.processing) {
        return 1;
      }
      return 2;
    }

    final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
    indexed.sort((a, b) {
      final byRank = rank(a.$2).compareTo(rank(b.$2));
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }
}
