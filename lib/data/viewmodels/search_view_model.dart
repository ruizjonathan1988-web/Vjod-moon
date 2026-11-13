import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../../l10n/current_app_localizations.dart';
import '../../util/accent_folding.dart';
import '../models/aggregated_item.dart';
import '../repositories/multi_server_repository.dart';
import '../repositories/search_repository.dart';
import '../repositories/seerr_repository.dart';
import '../services/seerr/seerr_api_models.dart';
import '../services/vjod/provider_catalog_access.dart';
import '../services/vjod/search_dedupe.dart';
import '../services/vjod/xtream_catalog.dart';
import '../services/vjod/ma_tv.dart' show MaTvClient;

class SearchResultGroup {
  final String title;
  final List<String> itemTypes;
  final List<AggregatedItem> items;

  const SearchResultGroup({
    required this.title,
    required this.itemTypes,
    this.items = const [],
  });

  SearchResultGroup copyWith({List<AggregatedItem>? items}) =>
      SearchResultGroup(title: title, itemTypes: itemTypes, items: items ?? this.items);
}

/// A single retro game that matched the query. Games live behind the Moonbase
/// plugin rather than the normal /Items search, so they carry their owning
/// [libraryId] (which [GameSummary] itself does not expose) for navigation.
class GameSearchResult {
  final String libraryId;
  final GameSummary game;

  const GameSearchResult({required this.libraryId, required this.game});
}

enum SearchState { idle, loading, ready, error }

class SearchViewModel extends ChangeNotifier {
  final SearchRepository _searchRepository;
  final MediaServerClient _client;
  final String? _scopedParentId;
  // Only set when search should cover every signed-in server.
  final MultiServerRepository? _multiServerRepository;
  SeerrRepository? _seerrRepository;

  SearchViewModel(
    this._searchRepository,
    this._client, {
    SeerrRepository? seerrRepository,
    String? scopedParentId,
    MultiServerRepository? multiServerRepository,
  }) : _seerrRepository = seerrRepository,
       _multiServerRepository = multiServerRepository,
       _scopedParentId =
           (scopedParentId != null && scopedParentId.isNotEmpty)
               ? scopedParentId
               : null;

  void setSeerrRepository(SeerrRepository repo) {
    _seerrRepository = repo;
  }

  ImageApi imageApiFor(AggregatedItem item) =>
      _multiServerRepository?.getImageApiForServer(item.serverId) ??
      _client.imageApi;

  Map<String, String> _serverNames = const {};

  /// The server [item] came from, or null when only one server was searched.
  String? serverNameFor(AggregatedItem item) => _serverNames[item.serverId];

  SearchState _state = SearchState.idle;
  SearchState get state => _state;

  String _query = '';
  String get query => _query;

  List<SearchResultGroup> _results = const [];
  List<SearchResultGroup> get results => _results;

  List<SeerrDiscoverItem> _seerrResults = const [];
  List<SeerrDiscoverItem> get seerrResults => _seerrResults;

  List<GameSearchResult> _gameResults = const [];
  List<GameSearchResult> get gameResults => _gameResults;

  /// Films and series read straight from the profile's Xtream provider, with
  /// nothing stored on the media server.
  List<XtreamTitle> _providerResults = const [];
  List<XtreamTitle> get providerResults => _providerResults;

  /// The provider those results came from, to build their stream URLs.
  XtreamCatalog? get providerCatalog => _providerCatalog();

  XtreamCatalog? _providerCatalog() =>
      _scopedParentId != null ? null : currentProviderCatalog();

  /// Starts downloading the provider's lists as soon as search opens.
  void warmUpProvider() => _providerCatalog()?.warmUp();

  /// VJOD 4.47: the channel lineup is fetched when the search opens, not at
  /// the first letter.
  void warmUpChannels() {
    if (_scopedParentId != null) return;
    unawaited(_channelMatches('warm-up'));
  }

  // All games across every game library, fetched once per session and filtered
  // client-side since the plugin exposes no search endpoint.
  Future<List<GameSearchResult>>? _allGamesFuture;

  Object? _error;
  Object? get error => _error;

  Timer? _debounceTimer;

  // VJOD: short, the results already there narrow down at each letter.
  static const _debounceMs = 250;
  static const _resultLimit = 24;
  // VJOD 4.47: 120 (was 240), the groups show 24 each.
  static const _globalFetchLimit = 120;
  // Some servers answer a people search far slower than everything else, so
  // it's dropped if it takes too long.
  static const _peopleTimeout = Duration(seconds: 10);
  // VJOD: once the library has answered, the other sources (people, Seerr,
  // games, IPTV, channels) get this long together; they come in after.
  static const _sideGrace = Duration(milliseconds: 400);

  // VJOD: the last searches, shown again at once (a letter erased, the
  // screen opened again).
  final _recent = <String, _Snapshot>{};
  static const _recentMax = 30;
  String _shownFor = '';

  // Counts searches, so people that answer late only fill in their own search.
  int _searchRun = 0;

  static List<SearchResultGroup> _bookSearchGroups() {
    final l10n = currentAppLocalizations();
    return [
      SearchResultGroup(title: l10n.books, itemTypes: const ['Book']),
      SearchResultGroup(title: l10n.audiobooks, itemTypes: const ['AudioBook']),
    ];
  }

  static List<SearchResultGroup> _searchGroups() {
    final l10n = currentAppLocalizations();
    return [
      SearchResultGroup(title: l10n.books, itemTypes: const ['Book']),
      SearchResultGroup(title: l10n.movies, itemTypes: const ['Movie']),
      SearchResultGroup(title: l10n.series, itemTypes: const ['Series']),
      SearchResultGroup(title: l10n.seasons, itemTypes: const ['Season']),
      SearchResultGroup(title: l10n.episodes, itemTypes: const ['Episode']),
      SearchResultGroup(title: l10n.videos, itemTypes: const ['Video']),
      SearchResultGroup(title: l10n.musicVideos, itemTypes: const ['MusicVideo']),
      SearchResultGroup(title: l10n.trailers, itemTypes: const ['Trailer']),
      SearchResultGroup(title: l10n.programs, itemTypes: const ['Program']),
      SearchResultGroup(
        title: l10n.channels,
        itemTypes: const ['LiveTvChannel', 'TvChannel'],
      ),
      SearchResultGroup(title: l10n.playlists, itemTypes: const ['Playlist']),
      SearchResultGroup(
        title: l10n.artists,
        itemTypes: const ['MusicArtist', 'AlbumArtist'],
      ),
      SearchResultGroup(title: l10n.albums, itemTypes: const ['MusicAlbum']),
      SearchResultGroup(title: l10n.songs, itemTypes: const ['Audio']),
      SearchResultGroup(title: l10n.photoAlbums, itemTypes: const ['PhotoAlbum']),
      SearchResultGroup(title: l10n.photos, itemTypes: const ['Photo']),
      SearchResultGroup(title: l10n.collections, itemTypes: const ['BoxSet']),
      SearchResultGroup(title: l10n.people, itemTypes: const ['Person']),
      SearchResultGroup(
        title: l10n.folders,
        itemTypes: const ['Folder', 'CollectionFolder', 'UserView'],
      ),
    ];
  }

  void searchDebounced(String query) {
    final trimmed = query.trim();
    if (trimmed == _query) return;
    _query = trimmed;

    _debounceTimer?.cancel();

    if (trimmed.isEmpty) {
      _results = const [];
      _seerrResults = const [];
      _gameResults = const [];
      _providerResults = const [];
      _shownFor = '';
      _state = SearchState.idle;
      notifyListeners();
      return;
    }

    final known = _recent[trimmed];
    if (known != null) {
      _show(known, trimmed);
      _state = SearchState.ready;
    } else {
      _narrowTo(trimmed);
      _state = SearchState.loading;
    }
    notifyListeners();

    _debounceTimer = Timer(
      Duration(milliseconds: known != null ? _debounceMs * 2 : _debounceMs),
      () => _executeSearch(trimmed),
    );
  }

  void _show(_Snapshot s, String query) {
    _results = s.results;
    _seerrResults = s.seerr;
    _gameResults = s.games;
    _providerResults = s.provider;
    _shownFor = query;
  }

  void _remember(String query) {
    _recent.remove(query);
    _recent[query] = _Snapshot(_results, _seerrResults, _gameResults, _providerResults);
    while (_recent.length > _recentMax) {
      _recent.remove(_recent.keys.first);
    }
    _shownFor = query;
  }

  /// A letter added: what is on screen keeps only what still matches, at
  /// once, while the servers are asked.
  void _narrowTo(String query) {
    if (_shownFor.isEmpty || !query.startsWith(_shownFor)) return;
    final words = foldForSearch(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    bool ok(String? text) {
      final t = foldForSearch(text ?? '');
      return words.every(t.contains);
    }
    // A group left with nothing goes: the screen reads each group's first
    // item, and « ali » then « alie » crashed it (« Bad state: No element »).
    _results = [
      for (final g in _results)
        g.copyWith(items: [for (final i in g.items) if (ok(i.name) || ok(i.rawData['OriginalTitle'] as String?)) i]),
    ].where((g) => g.items.isNotEmpty).toList();
    _seerrResults = [for (final x in _seerrResults) if (ok(x.title ?? x.name) || ok(x.originalTitle ?? x.originalName)) x];
    _gameResults = [for (final x in _gameResults) if (ok(x.game.title) || ok(x.game.fileName)) x];
    _providerResults = [for (final x in _providerResults) if (ok(x.name)) x];
    _shownFor = query;
  }

  void searchImmediate(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _query = trimmed;
    _debounceTimer?.cancel();
    _state = SearchState.loading;
    notifyListeners();
    _executeSearch(trimmed);
  }

  Future<void> _executeSearch(String query) async {
    if (query != _query) return;
    final run = ++_searchRun;

    Object? serverError;
    try {
        final activeGroups = _scopedParentId != null
          ? _bookSearchGroups()
          : _searchGroups();
      final seerrFuture = _fetchSeerrResults(query);
      final gamesFuture = _scopedParentId != null
          ? Future.value(const <GameSearchResult>[])
          : _fetchGameResults(query);
      final providerFuture = _fetchProviderResults(query);
      final channelsFuture = _scopedParentId != null
          ? Future.value(const <AggregatedItem>[])
          : _channelMatches(query);

      final (firstGroups, peopleFuture) = _scopedParentId != null
          ? (
              await Future.wait(
                activeGroups.map((group) async {
                  final items = await _searchRepository.search(
                    query,
                    includeItemTypes: group.itemTypes,
                    parentId: _scopedParentId,
                    limit: _resultLimit,
                  );
                  return group.copyWith(items: items);
                }),
              ),
              Future.value(const <AggregatedItem>[]),
            )
          : await _buildGroupedGlobalResults(query, activeGroups).catchError((
              Object e,
            ) {
              // The server's search failed (often one letter on a big
              // library, which times out). The IPTV, request and game
              // results still show; the error only when nothing else does.
              serverError = e;
              return (
                [for (final g in activeGroups) g.copyWith(items: const <AggregatedItem>[])],
                Future.value(const <AggregatedItem>[]),
              );
            });
      var groups = firstGroups;

      // VJOD 4.47: the other sources are waited for together, a moment at
      // most, instead of one after the other (up to 3 s more before). What
      // comes later fills in below.
      Future<T?> soon<T>(Future<T> f) =>
          f.then<T?>((v) => v).timeout(_sideGrace, onTimeout: () => null);
      final early = await Future.wait<Object?>([
        soon(seerrFuture),
        soon(gamesFuture),
        soon(providerFuture),
        soon(channelsFuture),
        soon(peopleFuture),
      ]);
      final seerrLate = early[0] as List<SeerrDiscoverItem>?;
      final gamesLate = early[1] as List<GameSearchResult>?;
      final provider = early[2] as List<XtreamTitle>?;
      final channelsEarly = early[3] as List<AggregatedItem>?;
      var people = early[4] as List<AggregatedItem>?;
      final seerr = seerrLate ?? const <SeerrDiscoverItem>[];
      final games = gamesLate ?? const <GameSearchResult>[];
      if (channelsEarly != null) groups = _withChannels(groups, channelsEarly);

      // With nothing else to show, the results wait for people instead of
      // coming up empty.
      final hasOtherResults =
          groups.any((g) => g.items.isNotEmpty) ||
          seerr.isNotEmpty ||
          games.isNotEmpty ||
          (provider?.isNotEmpty ?? false);
      if (people == null && !hasOtherResults) people = await peopleFuture;

      if (query != _query) return;

      final serverFailed = serverError;
      if (serverFailed != null && !hasOtherResults && (people ?? const []).isEmpty) {
        throw serverFailed;
      }

      var latestPeople = people ?? const <AggregatedItem>[];
      _results = _withPeople(groups, latestPeople);
      _gameResults = games;
      _setCatalogResults(groups, provider ?? const [], seerr);
      _state = SearchState.ready;
      _remember(query);
      var lateProvider = provider ?? const <XtreamTitle>[];
      var lateSeerr = seerr;
      if (channelsEarly == null) {
        unawaited(
          channelsFuture.then((found) {
            if (found.isEmpty || run != _searchRun || query != _query) return;
            groups = _withChannels(groups, found);
            _results = _withPeople(groups, latestPeople);
            _setCatalogResults(groups, lateProvider, lateSeerr);
            _remember(query);
            notifyListeners();
          }),
        );
      }
      if (seerrLate == null) {
        unawaited(
          seerrFuture.then((found) {
            if (found.isEmpty || run != _searchRun || query != _query) return;
            lateSeerr = found;
            _setCatalogResults(groups, lateProvider, lateSeerr);
            _remember(query);
            notifyListeners();
          }),
        );
      }
      if (gamesLate == null) {
        unawaited(
          gamesFuture.then((found) {
            if (found.isEmpty || run != _searchRun || query != _query) return;
            _gameResults = found;
            _remember(query);
            notifyListeners();
          }),
        );
      }
      if (provider == null) {
        unawaited(
          providerFuture.then((found) {
            if (found.isEmpty || run != _searchRun || query != _query) return;
            lateProvider = found;
            _setCatalogResults(groups, lateProvider, lateSeerr);
            _remember(query);
            notifyListeners();
          }),
        );
      }
      if (people == null) {
        unawaited(
          peopleFuture.then((found) {
            if (found.isEmpty || run != _searchRun || query != _query) return;
            latestPeople = found;
            _results = _withPeople(groups, found);
            _remember(query);
            notifyListeners();
          }),
        );
      }
    } catch (e) {
      if (query != _query) return;
      _error = e;
      _state = SearchState.error;
    }
    notifyListeners();
  }

  /// VJOD: each title once, under its best way to watch it (server, then
  /// IPTV, then to request); see search_dedupe.dart.
  void _setCatalogResults(
    List<SearchResultGroup> groups,
    List<XtreamTitle> provider,
    List<SeerrDiscoverItem> seerr,
  ) {
    final kept = dedupeCatalogResults(
      libraryTmdbIds: {
        for (final group in groups)
          for (final item in group.items)
            if ((item.type == 'Movie' || item.type == 'Series') && item.tmdbId != null)
              item.tmdbId!,
      },
      provider: provider,
      seerr: seerr,
    );
    _providerResults = kept.provider;
    _seerrResults = kept.seerr;
  }

  /// Every group in order with the People group left empty, and the people
  /// search that fills it.
  Future<(List<SearchResultGroup>, Future<List<AggregatedItem>>)>
  _buildGroupedGlobalResults(
    String query,
    List<SearchResultGroup> activeGroups,
  ) async {
    // Looked up once before the searches start, so each of them reuses it
    // instead of looking the servers up again.
    final sessions = await _multiServerRepository?.getLoggedInServers();
    _serverNames = sessions != null && sessions.length > 1
        ? {for (final session in sessions) session.server.id: session.server.name}
        : const {};
    final peopleFuture = _searchEachServer(
      (repository) => repository
          .searchPeople(query, limit: _resultLimit)
          .timeout(_peopleTimeout),
      label: 'people search',
    ).then(_interleave).catchError((_) => <AggregatedItem>[]);
    // VJOD 4.47: only the kinds the groups show, so the server searches less
    // (no songs, photos or tracks it would then throw away).
    final wanted = <String>{
      for (final g in activeGroups)
        for (final t in g.itemTypes)
          if (t != 'Person' && t != 'LiveTvChannel') t,
    }.toList();
    final perServerItems = await _searchEachServer(
      (repository) => repository.search(
        query,
        includeItemTypes: wanted,
        parentId: _scopedParentId,
        limit: _globalFetchLimit,
      ),
      label: 'search',
    );

    final grouped = <SearchResultGroup>[];
    for (final group in activeGroups) {
      if (group.itemTypes.contains('Person')) {
        grouped.add(group);
        continue;
      }
      if (group.itemTypes.contains('LiveTvChannel')) {
        // Filled in when the channel lineup answers (see _withChannels).
        grouped.add(group.copyWith(items: const <AggregatedItem>[]));
        continue;
      }
      final matched = _interleave([
        for (final items in perServerItems)
          items.where((item) => group.itemTypes.contains(item.type)).toList(),
      ]).take(_resultLimit).toList();
      grouped.add(group.copyWith(items: matched));
    }

    return (grouped, peopleFuture);
  }

  /// [groups] with the channels that match in the channel group.
  static List<SearchResultGroup> _withChannels(
    List<SearchResultGroup> groups,
    List<AggregatedItem> channels,
  ) => [
    for (final g in groups)
      if (g.itemTypes.contains('LiveTvChannel')) g.copyWith(items: channels) else g,
  ];

  /// The groups that have something to show, with [people] in the People
  /// group.
  static List<SearchResultGroup> _withPeople(
    List<SearchResultGroup> groups,
    List<AggregatedItem> people,
  ) => [
    for (final group in groups)
      if (group.itemTypes.contains('Person'))
        group.copyWith(items: people.take(_resultLimit).toList())
      else
        group,
  ].where((g) => g.items.isNotEmpty).toList();

  Future<List<List<AggregatedItem>>> _searchEachServer(
    Future<List<AggregatedItem>> Function(SearchRepository repository) search, {
    required String label,
  }) async {
    final multiServer = _multiServerRepository;
    if (multiServer == null) return [await search(_searchRepository)];
    return multiServer.searchEachServer(search, label: label);
  }

  /// Takes one result from each server in turn, so every server keeps its own
  /// ranking and none crowds the others out of a capped group.
  static List<AggregatedItem> _interleave(List<List<AggregatedItem>> perServer) {
    final longest = perServer.fold(0, (most, items) => max(most, items.length));
    return [
      for (var i = 0; i < longest; i++)
        for (final items in perServer)
          if (i < items.length) items[i],
    ];
  }

  // The lineup is fetched once per search session and reused across queries,
  // since /LiveTv/Channels has no search parameter of its own.
  Future<List<AggregatedItem>>? _channelsFuture;

  /// Whether Ma TV answers the channel search, so the server's own lineup
  /// isn't loaded. Replaceable for tests.
  Future<bool> Function() serverChannelsRedundant = () async => MaTvClient().isConfigured;

  Future<List<AggregatedItem>> _channelMatches(String query) async {
    // Channels come back wholesale rather than through a search the server
    // answers, so the folding it would have done has to happen here.
    final q = foldForSearch(query.trim());
    if (q.isEmpty || q.startsWith('studio:')) return const [];
    // VJOD 5.14: with Ma TV, its row « Chaînes en direct » already finds the
    // channels; the server's lineup is the same 12 000 channels, loaded a
    // second time for nothing (700 MB on the SFR box when search froze).
    if (await serverChannelsRedundant()) return const [];
    _channelsFuture ??= _searchEachServer(
      (repository) => repository.fetchLiveTvChannels(),
      label: 'channel lineup',
    ).then((perServer) => perServer.expand((channels) => channels).toList());
    try {
      final all = await _channelsFuture!;
      return all
          .where((c) => foldForSearch(c.name).contains(q))
          .take(_resultLimit)
          .toList();
    } catch (_) {
      // A server without Live TV shouldn't break search. Retry next query in
      // case the failure was transient.
      _channelsFuture = null;
      return const [];
    }
  }

  Future<List<SeerrDiscoverItem>> _fetchSeerrResults(String query) async {
    if (_scopedParentId != null) return const [];
    if (query.trim().toLowerCase().startsWith('studio:')) return const [];
    final repo = _seerrRepository;
    if (repo == null) return const [];
    try {
      await repo.ensureInitialized();
      if (!repo.isAvailable) return const [];
      final page = await repo.search(query, limit: _resultLimit);
      return page.results.where((item) => !item.isBlacklisted).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<XtreamTitle>> _fetchProviderResults(String query) async {
    if (query.trim().toLowerCase().startsWith('studio:')) return const [];
    final catalog = _providerCatalog();
    if (catalog == null) return const [];
    try {
      return await catalog.search(
        query,
        preferredTags: currentProviderLanguages(),
      );
    } catch (_) {
      return const [];
    }
  }

  Future<List<GameSearchResult>> _fetchGameResults(String query) async {
    // Games have no search endpoint, so the whole set is matched here and the
    // folding is this side's to do.
    final q = foldForSearch(query.trim());
    if (q.isEmpty || q.startsWith('studio:')) return const [];
    final gamesApi = _client.gamesApi;
    if (gamesApi == null) return const [];
    try {
      _allGamesFuture ??= _fetchAllGames(gamesApi);
      final all = await _allGamesFuture!;
      return all
          .where(
            (r) =>
                foldForSearch(r.game.title).contains(q) ||
                foldForSearch(r.game.fileName).contains(q),
          )
          .take(_resultLimit)
          .toList();
    } catch (_) {
      _allGamesFuture = null;
      return const [];
    }
  }

  Future<List<GameSearchResult>> _fetchAllGames(GamesApi gamesApi) async {
    final libraries = await gamesApi.getLibraries();
    final perLibrary = await Future.wait(
      libraries.map((library) async {
        final games = await gamesApi.getGames(library.id);
        return games.map(
          (game) => GameSearchResult(libraryId: library.id, game: game),
        );
      }),
    );
    return perLibrary.expand((results) => results).toList();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    // Keeps people that answer after the screen closed from landing on it.
    _searchRun++;
    super.dispose();
  }
}

/// What a search showed, to show it again at once.
class _Snapshot {
  final List<SearchResultGroup> results;
  final List<SeerrDiscoverItem> seerr;
  final List<GameSearchResult> games;
  final List<XtreamTitle> provider;
  const _Snapshot(this.results, this.seerr, this.games, this.provider);
}
