import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'dart:convert';
import 'dart:io';

import 'package:moonfin_design/moonfin_design.dart' show ThemeRegistry;
import 'package:path_provider/path_provider.dart';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';
import 'package:collection/collection.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/models/aggregated_library.dart';
import '../../../data/models/home_row.dart';
import '../../../data/repositories/multi_server_repository.dart';
import '../../../data/repositories/user_views_repository.dart';
import '../../../data/utils/latest_media_row_normalizer.dart';
import '../../../data/services/connectivity_service.dart';
import '../../../data/services/home_row_cache_store.dart';
import '../../../data/services/row_data_source.dart';
import '../../../data/services/topshelf_service.dart';
import '../../../data/services/tv_channels_service.dart';
import '../../../data/services/watch_next_service.dart';
import '../../../data/services/user_data_sync.dart';
import '../../../data/viewmodels/media_bar_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/current_app_localizations.dart';
import '../../../preference/home_section_config.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/plugin_sync_service.dart';
import '../../../data/services/seerr/seerr_api_models.dart';
import '../../../data/services/seerr/seerr_discover_sliders.dart';
import '../../../data/services/seerr/for_you_service.dart';
import '../../../data/services/seerr/my_requests.dart';
import '../../../data/services/seerr/for_you_ranker.dart';
import '../../../data/services/seerr/taste_profile.dart';
import '../../../data/services/seerr/taste_extras.dart';
import '../../../data/services/seerr/saga_service.dart';
import '../../../data/services/seerr/seed_recommendations.dart';
import '../../../data/services/seerr/seerr_age_gate.dart';
import '../../../data/services/seerr/upcoming_picks.dart';
import '../../../data/services/betaseries/betaseries_client.dart';
import '../../../data/services/chart_cards.dart';
import '../../../data/services/trakt/trakt_client.dart';
import '../../../data/services/wikidata/film_awards_client.dart';
import '../../../data/services/french_box_office.dart';
import '../../../data/services/home_highlights.dart';
import '../../../data/services/home_row_tidy.dart';
import '../../../data/utils/bounded_concurrency.dart';
import '../../../util/platform_detection.dart';
import '../../../util/server_url.dart';
import '../../../preference/seerr_preferences.dart';
import '../../../data/viewmodels/seerr_discover_view_model.dart';
import '../../widgets/seerr/seerr_shortcuts.dart';
import '../../../data/services/custom_external_lists_service.dart';
import '../../../data/utils/blocked_ratings.dart';
import '../../../util/parental_filter.dart';
import '../../../util/seasonal_country.dart';
import '../../../util/seerr_genre_art.dart';
import '../../util/home_row_title_localizer.dart';

class HomeViewModel extends ChangeNotifier {
  /// Cards in a merged row, matching what a single library row shows.
  static const _mergedRowItemLimit = 15;

  final RowDataSource _dataSource;
  final UserPreferences _prefs;
  final MediaServerClient _client;
  final MediaBarViewModel _mediaBarViewModel;
  final MultiServerRepository _multiServerRepo;
  final String _ownerUserId;
  final HomeRowCacheStore _cacheStore;
  final Set<String> _inFlightPagingRowIds = {};
  final Map<String, int> _rowOffsets = {};
  final Set<String> _rowsPagedThisLoad = {};

  /// How many items a row asks for per page, matching what RowDataSource
  /// requests so the offsets tracked here stay in step with it.
  static const _rowPageSize = 15;

  final TopShelfService _topShelf = TopShelfService();
  final WatchNextService _watchNext = WatchNextService();
  final TvChannelsService _tvChannels = TvChannelsService();

  List<HomeRow> _rows = [];

  /// The rows as drawn: without the placeholders of sections expected to be
  /// empty, and tidied by [tidyHomeRows]. Kept until the rows or the
  /// session's requests change, so the screen's layout caches see the same
  /// rows from one frame to the next.
  List<HomeRow> get rows {
    final visible = _emptySectionIds.isEmpty
        ? _rows
        : _rows.where((row) => !_isEmptySectionPlaceholder(row)).toList();
    final requested = ForYouService.instance.requestedChanges.value;
    final gate = _ageGate;
    final gateVersion = gate?.version;
    final cached = _tidyRows;
    if (cached != null &&
        _tidyRequested == requested &&
        _tidyGateVersion == gateVersion &&
        identical(_tidyFilter, activeParentalFilter) &&
        listEquals(_tidySource, visible)) {
      return cached;
    }
    _tidySource = List.of(visible);
    _tidyRequested = requested;
    _tidyGateVersion = gateVersion;
    _tidyFilter = activeParentalFilter;
    // On a profile with ratings blocked, Seerr's titles wait for theirs.
    final allowed = gate == null || !activeParentalFilter.isActive
        ? visible
        : withAgeGate(visible, gate.allows);
    return _tidyRows = tidyHomeRows(
      allowed,
      keptRowIds: const {
        myRequestsRowId,
        sagaRowId,
        top10MoviesRowId,
        top10SeriesRowId,
        frenchMoviesRowId,
        frenchSeriesRowId,
        frenchClassicsRowId,
      },
      requestedKeys: ForYouService.instance.requestedKeys,
      requestableFlag: forYouFlag,
    );
  }

  List<HomeRow>? _tidySource;
  List<HomeRow>? _tidyRows;
  int? _tidyRequested;
  int? _tidyGateVersion;
  ParentalFilter? _tidyFilter;

  /// Placeholder ids of sections expected to come back empty, because their
  /// last load did or a cold start found nothing cached for them. Their
  /// placeholders still hold their place in the order, but aren't shown, so
  /// an empty section doesn't flash its title on every load.
  final Set<String> _emptySectionIds = {};

  bool _isEmptySectionPlaceholder(HomeRow row) =>
      row.isLoading && row.items.isEmpty && _emptySectionIds.contains(row.id);

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  bool _bgMergeInFlight = false;
  bool _bgResumeRefreshInFlight = false;
  bool _reloadRequestedWhileLoading = false;
  bool _pendingReloadPreserveExisting = true;
  bool _pendingReloadForceRefresh = false;
  bool _pendingReloadNewSectionsOnly = true;

  /// How many sections from the top load with Home. The single row sections
  /// below them, such as collections, genres and playlists, wait in
  /// [_deferredSections] until Home scrolls near their row, so a Home with
  /// hundreds of collections doesn't fetch them all up front.
  static const _eagerSectionCount = 8;

  /// Sections waiting to load, keyed by the id their row has on Home.
  final Map<String, HomeSectionConfig> _deferredSections = {};

  /// Loads a section the way the last [load] did.
  Future<void> Function(HomeSectionConfig cfg)? _loadDeferredSection;

  /// The last seasonal answer, kept for the session so every Home reload doesn't
  /// ask Moonbase again. The daily refresh clears it, which is when the server's
  /// shuffle changes too.
  Map<String, dynamic>? _seasonalMemo;

  String get _serverId => _client.baseUrl;
  MediaBarViewModel get mediaBarViewModel => _mediaBarViewModel;

  // TV can't download, so it never enters offline browsing mode and keeps
  // rendering its cached rows instead.
  bool get _isOffline =>
      !PlatformDetection.isTV &&
      GetIt.instance.isRegistered<ConnectivityService>() &&
      !GetIt.instance<ConnectivityService>().canReachServer;

  bool get _multiServerEnabled =>
      !_isOffline && _prefs.get(UserPreferences.enableMultiServerLibraries);

  /// Whether a stored address is the server this client is on, ignoring the
  /// harmless ways the two spellings differ, such as a trailing slash or the
  /// `/web/index.html` the dashboard runs under.
  bool _isThisServer(String? storedServerId) {
    if (storedServerId == null || storedServerId.isEmpty) return false;
    return normalizeServerBaseUrl(storedServerId) ==
        normalizeServerBaseUrl(_serverId);
  }

  /// Whether a section should show on this server's home screen.
  ///
  /// The admin config page stamps dynamic rows with whatever address Moonbase
  /// was opened at, which is often not how users reach the server, so a LAN
  /// address against a public domain never matches however it is spelled. With
  /// one server there is nowhere else the row could belong, so keep it anyway.
  /// A collection picked from another signed-in server shows only while
  /// multi-server libraries are on.
  bool _belongsToThisServer(HomeSectionConfig cfg) {
    if (cfg.isBuiltin || cfg.pluginSource == HomeSectionPluginSource.custom) {
      return true;
    }
    if (_otherServerRows.containsKey(cfg.stableId)) return _multiServerEnabled;
    if (!_multiServerEnabled) return true;
    return _isThisServer(cfg.serverId);
  }

  /// The signed-in server each collection row picked from another server
  /// loads and pages from, by row id.
  Map<String, ServerUserSession> _otherServerRows = const {};

  Future<Map<String, ServerUserSession>> _findOtherServerRows(
    List<HomeSectionConfig> configs,
  ) async {
    final foreign = configs.where(
      (c) =>
          c.pluginSource == HomeSectionPluginSource.collections &&
          !_isThisServer(c.serverId),
    );
    if (foreign.isEmpty) return const {};
    try {
      final sessions = {
        for (final s in await _multiServerRepo.getLoggedInServers())
          normalizeServerBaseUrl(s.client.baseUrl): s,
      };
      return {
        for (final c in foreign)
          c.stableId: ?sessions[normalizeServerBaseUrl(c.serverId ?? '')],
      };
    } catch (_) {
      return const {};
    }
  }

  String _homeCacheKey() {
    final userId = _ownerUserId;
    final sections = _prefs.get(UserPreferences.homeSectionsJson);
    final multiServer = _prefs.get(UserPreferences.enableMultiServerLibraries);
    final merge = _prefs.effectiveMergeContinueWatchingNextUp;
    final blocked = _prefs.get(UserPreferences.blockedParentalRatings);
    // Offline rows are cached separately so cached online rows never hydrate
    // an offline home (and vice versa).
    final offline = _isOffline;
    final shape = RowDataSource.fieldShapeToken;
    return '$_serverId|$userId|$sections|$multiServer|$merge|$blocked|offline:$offline|fields:$shape';
  }

  /// Called again when the resume and next up rows refresh on their own, or
  /// the next cold start paints the ones from before the last episode
  /// finished.
  void _saveRowCache() => unawaited(_cacheStore.write(_homeCacheKey(), _rows));

  static bool _isFavoriteSectionType(HomeSectionType type) {
    return switch (type) {
      HomeSectionType.favoriteMovies ||
      HomeSectionType.favoriteSeries ||
      HomeSectionType.favoriteEpisodes ||
      HomeSectionType.favoritePeople ||
      HomeSectionType.favoriteArtists ||
      HomeSectionType.favoriteMusicVideos ||
      HomeSectionType.favoriteAlbums ||
      HomeSectionType.favoriteSongs => true,
      _ => false,
    };
  }

  static bool _isCollectionsSectionType(HomeSectionType type) {
    return type == HomeSectionType.collections;
  }

  static bool _isGenresSectionType(HomeSectionType type) {
    return type == HomeSectionType.genres;
  }

  static bool _isPlaylistsSectionType(HomeSectionType type) {
    return type == HomeSectionType.playlists;
  }

  static bool _isAudioSectionType(HomeSectionType type) {
    return switch (type) {
      HomeSectionType.audioArtists ||
      HomeSectionType.audioAlbums ||
      HomeSectionType.audioPlaylists => true,
      _ => false,
    };
  }

  /// Sections the offline downloads catalog can answer. Everything else
  /// (live TV, seerr/tmdb/arr externals, server plugin rows) is skipped when
  /// the server is unreachable.
  static bool _isOfflineCapableSection(HomeSectionConfig c) {
    if (!c.isBuiltin) return false;
    return switch (c.type) {
      HomeSectionType.liveTv ||
      HomeSectionType.onNow ||
      HomeSectionType.activeRecordings ||
      HomeSectionType.playlists ||
      HomeSectionType.audioPlaylists ||
      HomeSectionType.radarrCalendar ||
      HomeSectionType.sonarrCalendar ||
      HomeSectionType.seerrForYou ||
      HomeSectionType.seerrMyRequests ||
      HomeSectionType.seerrSagas ||
      HomeSectionType.seerrGems ||
      HomeSectionType.seerrUpcoming ||
      HomeSectionType.familyNight ||
      HomeSectionType.seerrBecause ||
      HomeSectionType.top10Movies ||
      HomeSectionType.top10Series ||
      HomeSectionType.frenchMovies ||
      HomeSectionType.frenchSeries ||
      HomeSectionType.frenchClassics ||
      HomeSectionType.surprise ||
      HomeSectionType.seasonal =>
        false,
      final t when _isSeerrSectionType(t) || _isTmdbSectionType(t) => false,
      _ => true,
    };
  }

  static bool _isSeerrSectionType(HomeSectionType type) {
    return type == HomeSectionType.seerrShortcuts ||
        type == HomeSectionType.seerrRecentRequests ||
        type == HomeSectionType.seerrWatchlist ||
        type == HomeSectionType.seerrRecentlyAdded ||
        type == HomeSectionType.seerrPopularMovies ||
        type == HomeSectionType.seerrUpcomingMovies ||
        type == HomeSectionType.seerrPopularSeries ||
        type == HomeSectionType.seerrUpcomingSeries ||
        type == HomeSectionType.seerrTrending ||
        type == HomeSectionType.seerrMovieGenres ||
        type == HomeSectionType.seerrStudios ||
        type == HomeSectionType.seerrSeriesGenres ||
        type == HomeSectionType.seerrNetworks;
  }

  static bool _isTmdbSectionType(HomeSectionType type) =>
      UserPreferences.isTmdbSectionType(type);

  bool _isTmdbSectionEnabled(HomeSectionType type) {
    final pref = UserPreferences.tmdbSectionEnabled[type];
    return pref != null && _prefs.get(pref);
  }

  bool _isAnyTmdbSectionEnabled() =>
      UserPreferences.tmdbSectionEnabled.values.any(_prefs.get);

  static bool _isImdbSectionType(HomeSectionType type) {
    return type == HomeSectionType.imdbTop250Movies ||
        type == HomeSectionType.imdbTop250TvShows ||
        type == HomeSectionType.imdbMostPopularMovies ||
        type == HomeSectionType.imdbMostPopularTvShows ||
        type == HomeSectionType.imdbLowestRatedMovies ||
        type == HomeSectionType.imdbTopEnglishMovies;
  }

  bool _isImdbSectionEnabled(HomeSectionType type) {
    switch (type) {
      case HomeSectionType.imdbTop250Movies:
        return _prefs.get(UserPreferences.imdbTop250MoviesEnabled);
      case HomeSectionType.imdbTop250TvShows:
        return _prefs.get(UserPreferences.imdbTop250TvShowsEnabled);
      case HomeSectionType.imdbMostPopularMovies:
        return _prefs.get(UserPreferences.imdbMostPopularMoviesEnabled);
      case HomeSectionType.imdbMostPopularTvShows:
        return _prefs.get(UserPreferences.imdbMostPopularTvShowsEnabled);
      case HomeSectionType.imdbLowestRatedMovies:
        return _prefs.get(UserPreferences.imdbLowestRatedMoviesEnabled);
      case HomeSectionType.imdbTopEnglishMovies:
        return _prefs.get(UserPreferences.imdbTopEnglishMoviesEnabled);
      default:
        return false;
    }
  }

  bool _isAnyImdbSectionEnabled() {
    return _prefs.get(UserPreferences.imdbTop250MoviesEnabled) ||
        _prefs.get(UserPreferences.imdbTop250TvShowsEnabled) ||
        _prefs.get(UserPreferences.imdbMostPopularMoviesEnabled) ||
        _prefs.get(UserPreferences.imdbMostPopularTvShowsEnabled) ||
        _prefs.get(UserPreferences.imdbLowestRatedMoviesEnabled) ||
        _prefs.get(UserPreferences.imdbTopEnglishMoviesEnabled);
  }

  ImageApi imageApiForServer(String serverId) {
    if (!_multiServerEnabled) return _dataSource.imageApi;
    return _multiServerRepo.getImageApiForServer(serverId);
  }

  HomeViewModel({
    required RowDataSource dataSource,
    required UserPreferences prefs,
    required MediaServerClient client,
    required MediaBarViewModel mediaBarViewModel,
    required MultiServerRepository multiServerRepo,
    HomeRowCacheStore? cacheStore,
  }) : _dataSource = dataSource,
       _prefs = prefs,
       _client = client,
       _mediaBarViewModel = mediaBarViewModel,
       _multiServerRepo = multiServerRepo,
       _cacheStore = cacheStore ?? HomeRowCacheStore(),
       _ownerUserId = client.userId ?? '' {
    ForYouService.instance.requestedChanges.addListener(notifyListeners);
    _ageGate?.addListener(notifyListeners);
  }

  @override
  void dispose() {
    ForYouService.instance.requestedChanges.removeListener(notifyListeners);
    _ageGate?.removeListener(notifyListeners);
    super.dispose();
  }

  /// Keeps Seerr's titles behind the ratings blocked on this profile.
  final SeerrAgeGate? _ageGate = GetIt.instance.isRegistered<SeerrAgeGate>()
      ? GetIt.instance<SeerrAgeGate>()
      : null;

  /// Whether a section whose load threw keeps what is already on screen.
  ///
  /// A thrown load is a transient failure rather than an empty result, so a
  /// populated row stays, and rows the cache restored count too since a first
  /// load is exactly when the cache put them there. With nothing worth keeping
  /// the row clears, so a cold load still drops its placeholder.
  @visibleForTesting
  static bool keepsRowsOnFailure({
    required bool preserveExisting,
    required bool hydratedFromCache,
    required bool hasVisibleRow,
  }) => (preserveExisting || hydratedFromCache) && hasVisibleRow;

  /// Whether a freshly fetched row gives way to the one already on screen.
  ///
  /// A section fetch only brings back the first page, so a row that paged while
  /// it was out would lose those pages and be handed straight back to the
  /// viewport to page in again. A row nobody paged takes the shorter answer,
  /// since that is how an item leaving a row reaches the screen.
  @visibleForTesting
  static bool keepsPagedRow({
    required bool pagedDuringLoad,
    required int existingItemCount,
    required int freshItemCount,
  }) => pagedDuringLoad && existingItemCount > freshItemCount;

  /// Whether the home has to load again because the server came back.
  ///
  /// Rows built while it was unreachable came from the downloads catalog, so
  /// they hold only what was downloaded. Connectivity reports every probe it
  /// runs, so only the crossing counts.
  static bool reloadsOnReachability({
    required bool canReachServer,
    required bool couldReachServer,
  }) => canReachServer && !couldReachServer;

  /// [newSectionsOnly] loads just the sections that have no rows yet, such as
  /// the Seerr rows that show up once Seerr signs in, and leaves the others
  /// as they are.
  Future<void> load({
    bool preserveExisting = false,
    bool forceRefresh = false,
    bool newSectionsOnly = false,
  }) async {
    _checkAndTriggerDailyExternalRowsRefresh();
    if (_isLoading) {
      _reloadRequestedWhileLoading = true;
      _pendingReloadPreserveExisting =
          _pendingReloadPreserveExisting && preserveExisting;
      _pendingReloadForceRefresh =
          _pendingReloadForceRefresh || forceRefresh;
      _pendingReloadNewSectionsOnly =
          _pendingReloadNewSectionsOnly && newSectionsOnly;
      return;
    }
    newSectionsOnly = newSectionsOnly && _rows.isNotEmpty;
    if (newSectionsOnly) preserveExisting = true;
    _isLoading = true;
    if (!newSectionsOnly) {
      _mediaBarViewModel.load(force: forceRefresh);
      _rowOffsets.clear();
      _multiServerRepo.clearOffsets();
      _rowsPagedThisLoad.clear();
    }
    notifyListeners();
    try {
      var hydratedFromCache = false;
      if (_rows.isEmpty) {
        final cached = await _cacheStore.read(_homeCacheKey());
        if (cached != null && _rows.isEmpty) {
          _rows = cached;
          hydratedFromCache = true;
          notifyListeners();
        }
      }

      final activeConfigs = _prefs.activeHomeSectionConfigs;
      final fallbackUsed = activeConfigs.isEmpty;
      final configs = fallbackUsed
          ? const [
              HomeSectionConfig(
                type: HomeSectionType.resume,
                enabled: true,
                order: 0,
              ),
              HomeSectionConfig(
                type: HomeSectionType.nextUp,
                enabled: true,
                order: 1,
              ),
              HomeSectionConfig(
                type: HomeSectionType.latestMedia,
                enabled: true,
                order: 2,
              ),
            ]
          : activeConfigs;
      _otherServerRows = await _findOtherServerRows(configs);
      final showFavoritesRows = _prefs.get(
        UserPreferences.displayFavoritesRows,
      );
      final showCollectionsRows = _prefs.get(
        UserPreferences.displayCollectionsRows,
      );
      final showGenresRows = _prefs.get(UserPreferences.displayGenresRows);
      final showPlaylistsRows = _prefs.get(
        UserPreferences.displayPlaylistsRows,
      );
      final showAudioRows = _prefs.get(UserPreferences.displayAudioRows);
      final showSeerrRows = GetIt.instance<PluginSyncService>().seerrAvailable;
      final seerrPrefs = GetIt.instance<SeerrPreferences>();
      final showImdbRows = _isAnyImdbSectionEnabled();
      final showTmdbRows = _isAnyTmdbSectionEnabled();
      final showSinceYouWatched = _prefs.get(UserPreferences.displaySinceYouWatchedRows);
      final sinceYouWatchedNum = _prefs.get(UserPreferences.sinceYouWatchedNumRows).value;
      final showRewatch = _prefs.get(UserPreferences.displayRewatchRow);
      final showStudiosRows = _prefs.get(UserPreferences.displayStudiosRows);
      final showSeasonal = GetIt.instance<PluginSyncService>().pluginAvailable &&
          _prefs.get(UserPreferences.seasonalRowEnabled);

      final offline = _isOffline;
      final visibleConfigsRaw = configs
          .where(
            (c) =>
                // When offline, only sections the downloads catalog can
                // answer are shown.
                (!offline || _isOfflineCapableSection(c)) &&
                _belongsToThisServer(c) &&
                (showFavoritesRows || !_isFavoriteSectionType(c.type)) &&
                (showCollectionsRows ||
                    !((c.isBuiltin && _isCollectionsSectionType(c.type)) ||
                        (c.isPluginDynamic &&
                            c.pluginSource ==
                                HomeSectionPluginSource.collections))) &&
                (showGenresRows ||
                    !((c.isBuiltin && _isGenresSectionType(c.type)) ||
                        (c.isPluginDynamic &&
                            c.pluginSource ==
                                HomeSectionPluginSource.genres))) &&
                (showStudiosRows || c.type != HomeSectionType.studios) &&
                (showPlaylistsRows ||
                    !((c.isBuiltin && _isPlaylistsSectionType(c.type)) ||
                        (c.isPluginDynamic &&
                            c.pluginSource ==
                                HomeSectionPluginSource.playlists))) &&
                (showAudioRows || !_isAudioSectionType(c.type)) &&
                (!_isSeerrSectionType(c.type) || (showSeerrRows && seerrPrefs.isSeerrHomeRowEnabled(c.type))) &&
                (showSeerrRows || !isSeerrSliderSection(c)) &&
                ((c.type != HomeSectionType.seerrForYou &&
                        c.type != HomeSectionType.seerrMyRequests &&
                        c.type != HomeSectionType.seerrSagas &&
                        c.type != HomeSectionType.seerrGems &&
                        c.type != HomeSectionType.seerrUpcoming &&
                        c.type != HomeSectionType.seerrBecause &&
                        c.type != HomeSectionType.top10Movies &&
                        c.type != HomeSectionType.top10Series &&
                        c.type != HomeSectionType.frenchMovies &&
                        c.type != HomeSectionType.frenchSeries &&
                        c.type != HomeSectionType.frenchClassics) ||
                    showSeerrRows) &&
                (!_isImdbSectionType(c.type) || (showImdbRows && _isImdbSectionEnabled(c.type))) &&
                (!_isTmdbSectionType(c.type) || (showTmdbRows && _isTmdbSectionEnabled(c.type))) &&
                (c.type != HomeSectionType.radarrCalendar || _prefs.get(UserPreferences.enableRadarrCalendar)) &&
                (c.type != HomeSectionType.sonarrCalendar || _prefs.get(UserPreferences.enableSonarrCalendar)) &&
                (c.type.sinceYouWatchedRow == 0 || (showSinceYouWatched && c.type.sinceYouWatchedRow <= sinceYouWatchedNum)) &&
                (c.type != HomeSectionType.rewatch || showRewatch) &&
                (c.type != HomeSectionType.seasonal || showSeasonal),
          )
          .toList(growable: false);

      // Filter out plugin-dynamic rows that duplicate already-enabled built-ins
      // and collapse equivalent plugin-dynamic rows so only the first
      // configured plugin row in a duplicate group remains visible.
      final enabledBuiltinKeys = visibleConfigsRaw
          .where((c) => c.isBuiltin)
          .expand(_duplicateKeysForConfig)
          .toSet();
      final seenPluginKeys = <String>{};
      final visibleConfigs = visibleConfigsRaw
          .where((c) {
            if (!c.isPluginDynamic) return true;
            final duplicateKeys = _duplicateKeysForConfig(c);
            if (duplicateKeys.any(enabledBuiltinKeys.contains)) {
              return false;
            }
            final duplicatesExistingPlugin = duplicateKeys.any(
              seenPluginKeys.contains,
            );
            if (!duplicatesExistingPlugin) {
              seenPluginKeys.addAll(duplicateKeys);
            }
            return !duplicatesExistingPlugin;
          })
          .toList(growable: false);

      final sections = visibleConfigs
          .where((c) => c.isBuiltin)
          .map((c) => c.type)
          .toList();

      if (!sections.contains(HomeSectionType.mediaBar)) {
        _mediaBarViewModel.load(force: forceRefresh);
      }

      final merge = _prefs.effectiveMergeContinueWatchingNextUp;
      final effectiveConfigs = visibleConfigs
          .where(
            (c) => !(c.isBuiltin && merge && c.type == HomeSectionType.nextUp),
          )
          .toList();

      final nonResumeEffectiveConfigs = merge
          ? effectiveConfigs
                .where(
                  (c) => !(c.isBuiltin && c.type == HomeSectionType.resume),
                )
                .toList()
          : effectiveConfigs;

      // Without its own series row, the Top 10 switches between films and
      // series in place.
      _top10Switches = !effectiveConfigs.any(
        (c) => c.isBuiltin && c.type == HomeSectionType.top10Series,
      );

      final showMergedResume =
          merge &&
          effectiveConfigs.any(
            (c) => c.isBuiltin && c.type == HomeSectionType.resume,
          );

      final List<HomeSectionConfig> sectionsToLoad;
      if (newSectionsOnly) {
        sectionsToLoad = nonResumeEffectiveConfigs
            .where((c) => !_rows.any((r) => _rowBelongsToConfig(r, c)))
            .toList();
      } else {
        _deferredSections.clear();
        sectionsToLoad = [];
        for (final (index, cfg) in nonResumeEffectiveConfigs.indexed) {
          if (index >= _eagerSectionCount && _isDeferrable(cfg)) {
            _deferredSections[cfg.stableId] = cfg;
          } else {
            sectionsToLoad.add(cfg);
          }
        }
      }

      if ((!preserveExisting && !hydratedFromCache) || _rows.isEmpty) {
        final placeholders = <HomeRow>[];
        for (final cfg in effectiveConfigs) {
          final placeholder = _placeholderForConfig(cfg);
          if (placeholder != null) {
            placeholders.add(placeholder);
          }
        }
        _rows = placeholders;
        notifyListeners();
      } else {
        final reconciledRows = _reconcilePreservedRows(
          effectiveConfigs,
          hydratedFromCache: hydratedFromCache,
        );
        if (!listEquals(_rows, reconciledRows)) {
          _rows = reconciledRows;
          notifyListeners();
        }
      }

      Future<void> loadConfigItem(HomeSectionConfig cfg) async {
        List<HomeRow> sectionRows;
        var failed = false;
        try {
          sectionRows = await _loadConfig(cfg, forceRefresh: forceRefresh);
        } catch (e) {
          failed = true;
          debugPrint('[Home] Failed to load section $cfg: $e');
          final hasVisibleRow = _rowsForConfig(
            _rows,
            cfg,
          ).any((r) => !r.isLoading);
          if (keepsRowsOnFailure(
            preserveExisting: preserveExisting,
            hydratedFromCache: hydratedFromCache,
            hasVisibleRow: hasVisibleRow,
          )) {
            return;
          }
          sectionRows = const <HomeRow>[];
        }
        final currentConfigs = _prefs.activeHomeSectionConfigs;
        final isStillActive = currentConfigs.any((c) => c.stableId == cfg.stableId);
        if (!isStillActive) return;
        // Cleanup runs even when the load failed, so the section's loading
        // placeholder is cleared instead of spinning forever.
        final loadedRows = sectionRows
            .map((r) => r.copyWith(items: _filterEmptyElements(r.items)))
            .where(
              (r) => r.items.isNotEmpty || r.rowType == HomeRowType.liveTv,
            )
            .map((freshRow) {
              final existing = _rows.firstWhereOrNull(
                (r) => r.id == freshRow.id,
              );
              if (existing == null) return freshRow;
              if (keepsPagedRow(
                pagedDuringLoad: _rowsPagedThisLoad.contains(freshRow.id),
                existingItemCount: existing.items.length,
                freshItemCount: freshRow.items.length,
              )) {
                return existing;
              }
              return freshRow;
            })
            .toList();
        final placeholder = _placeholderForConfig(cfg);
        if (placeholder != null && !failed) {
          if (loadedRows.isEmpty) {
            _emptySectionIds.add(placeholder.id);
          } else {
            _emptySectionIds.remove(placeholder.id);
          }
        }
        final loadedIds = loadedRows.map((r) => r.id).toSet();
        // Find the row that immediately follows this section's placeholder /
        // existing rows, so we can re-anchor after removals.

        String? anchorId;
        {
          // Walk forward past the section's current rows to find the next
          // sibling row that won't be removed.
          bool pastSection = false;
          for (final r in _rows) {
            final willRemove =
                (placeholder != null && r.id == placeholder.id) ||
                loadedIds.contains(r.id) ||
                _rowBelongsToConfig(r, cfg);
            if (willRemove) {
              pastSection = true;
            } else if (pastSection) {
              anchorId = r.id;
              break;
            }
          }
        }
        final newRows = List<HomeRow>.from(_rows);
        newRows.removeWhere(
          (r) =>
              (placeholder != null && r.id == placeholder.id) ||
              loadedIds.contains(r.id) ||
              // Also clear any stale rows that belonged to this section from a
              // prior load but were not included in the fresh result. This
              // prevents phantom rows when the section's row-set changes
              // (e.g. library added/removed, latestItemsExcludes updated).
              _rowBelongsToConfig(r, cfg),
        );

        if (loadedRows.isNotEmpty) {
          final insertIndex = anchorId != null
              ? newRows.indexWhere((r) => r.id == anchorId)
              : -1;
          if (insertIndex < 0) {
            newRows.addAll(loadedRows);
          } else {
            newRows.insertAll(insertIndex, loadedRows);
          }
        }
        _rows = newRows;
        notifyListeners();
      }

      // The merged row is the one a viewer checks first, so it doesn't wait
      // behind every other section while its cached copy sits on screen.
      if (showMergedResume) {
        unawaited(_loadResumeAndNextUpInBackground());
      }

      _loadDeferredSection = loadConfigItem;
      await mapBounded<HomeSectionConfig, void>(
        sectionsToLoad,
        3,
        (cfg) => loadConfigItem(cfg),
      );

      _saveRowCache();
      _topShelf.update(_rows);
      _watchNext.update(_rows);
      _tvChannels.update();
    } finally {
      _isLoading = false;
      notifyListeners();
      if (_reloadRequestedWhileLoading) {
        final nextPreserveExisting = _pendingReloadPreserveExisting;
        final nextForceRefresh = _pendingReloadForceRefresh;
        final nextNewSectionsOnly = _pendingReloadNewSectionsOnly;
        _reloadRequestedWhileLoading = false;
        _pendingReloadPreserveExisting = true;
        _pendingReloadForceRefresh = false;
        _pendingReloadNewSectionsOnly = true;
        await load(
          preserveExisting: nextPreserveExisting,
          forceRefresh: nextForceRefresh,
          newSectionsOnly: nextNewSectionsOnly,
        );
      }
    }
  }

  bool get hasDeferredSections => _deferredSections.isNotEmpty;

  /// Loads the deferred sections behind [nearRows], the rows on or near the
  /// screen.
  void loadSectionsNear(Iterable<HomeRow> nearRows) {
    final loadSection = _loadDeferredSection;
    if (loadSection == null) return;
    final due = [
      for (final row in nearRows) ?_deferredSections.remove(row.id),
    ];
    if (due.isEmpty) return;
    unawaited(
      mapBounded<HomeSectionConfig, void>(due, 3, loadSection)
          .then((_) => _saveRowCache()),
    );
  }

  /// Single row sections, which a layout can hold hundreds of, and whose row
  /// takes the section's id.
  static bool _isDeferrable(HomeSectionConfig cfg) =>
      cfg.isPluginDynamic && (cfg.pluginSection?.isNotEmpty ?? false);

  /// Repaints the watched ticks on the rows already built, without refetching
  /// them. The home screen drives this so the listener lives and dies with the
  /// widget rather than with this singleton.
  void applyUserDataChanges() {
    List<HomeRow>? rows;
    for (var i = 0; i < _rows.length; i++) {
      final patched = userDataSync.applyAll(_rows[i].items);
      if (identical(patched, _rows[i].items)) continue;
      rows ??= List<HomeRow>.of(_rows);
      rows[i] = _rows[i].copyWith(items: patched);
    }
    if (rows == null) return;
    _rows = rows;
    notifyListeners();
  }

  List<HomeRow> _reconcilePreservedRows(
    List<HomeSectionConfig> effectiveConfigs, {
    bool hydratedFromCache = false,
  }) {
    final currentRows = _rows;
    final reconciledRows = <HomeRow>[];

    for (final cfg in effectiveConfigs) {
      final existingRows = _rowsForConfig(currentRows, cfg);
      if (existingRows.isNotEmpty) {
        reconciledRows.addAll(existingRows);
        continue;
      }

      final placeholder = _placeholderForConfig(cfg);
      if (placeholder != null) {
        // The cache holds every section that had something to show, apart
        // from rows too short lived to keep. A deferred section may never
        // have loaded, and hiding it would keep Home from scrolling near it.
        if (hydratedFromCache &&
            !HomeRowCacheStore.isTimeBound(placeholder.rowType) &&
            !_deferredSections.containsKey(cfg.stableId)) {
          _emptySectionIds.add(placeholder.id);
        }
        reconciledRows.add(placeholder);
      }
    }

    return reconciledRows;
  }

  List<HomeRow> _rowsForConfig(List<HomeRow> rows, HomeSectionConfig cfg) {
    return rows
        .where((row) => _rowBelongsToConfig(row, cfg))
        .toList(growable: false);
  }

  List<AggregatedItem> _filterEmptyElements(List<AggregatedItem> items) {
    return items.where((item) {
      if (item.type == 'BoxSet' || item.type == 'Playlist') {
        if (item.childCount == 0 || item.recursiveItemCount == 0) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// The section in [configs] that built [row], or null when none of them did.
  ///
  /// Built-in rows are keyed by what they show rather than by their section's
  /// stable id, so this asks each section the same question the row
  /// reconciliation asks.
  static HomeSectionConfig? sectionConfigForRow(
    HomeRow row,
    List<HomeSectionConfig> configs,
  ) {
    // The merged calendar comes from the Radarr section when that one is on
    // and from the Sonarr section otherwise, the way the two loaders split it.
    if (row.id == 'merged_calendar') {
      return configs.firstWhereOrNull(
            (c) =>
                c.isBuiltin &&
                c.enabled &&
                c.type == HomeSectionType.radarrCalendar,
          ) ??
          configs.firstWhereOrNull(
            (c) => c.isBuiltin && c.type == HomeSectionType.sonarrCalendar,
          );
    }
    // The media bar matches recently released rows too, but it never builds
    // a row of its own.
    return configs.firstWhereOrNull(
      (c) => c.type != HomeSectionType.mediaBar && _rowBelongsToConfig(row, c),
    );
  }

  static bool _rowBelongsToConfig(HomeRow row, HomeSectionConfig cfg) {
    if (cfg.isPluginDynamic) {
      return row.id == cfg.stableId;
    }

    switch (cfg.type) {
      case HomeSectionType.resume:
        return row.rowType == HomeRowType.resume;
      case HomeSectionType.resumeAudio:
        return row.rowType == HomeRowType.resumeAudio;
      case HomeSectionType.nextUp:
        return row.rowType == HomeRowType.nextUp;
      case HomeSectionType.latestMedia:
        // Only claim rows that belong to the built-in latest-media section.
        // Plugin-dynamic rows (per-collection, per-playlist, etc.) have IDs
        // starting with 'pluginDynamic:' and must NOT be claimed here.
        return row.rowType == HomeRowType.latestMedia &&
            !row.id.startsWith('pluginDynamic:') &&
            !row.id.startsWith('sinceYouWatched') &&
            row.id != 'rewatch';
      case HomeSectionType.favoriteMovies:
      case HomeSectionType.favoriteSeries:
      case HomeSectionType.favoriteEpisodes:
      case HomeSectionType.favoritePeople:
      case HomeSectionType.favoriteArtists:
      case HomeSectionType.favoriteMusicVideos:
      case HomeSectionType.favoriteAlbums:
      case HomeSectionType.favoriteSongs:
        return row.rowType == HomeRowType.favorites &&
            row.id == _favoriteRowIdForSection(cfg.type);
      case HomeSectionType.collections:
        // Only claim the single aggregated collections row (id == 'collections').
        // Individual per-collection plugin rows have stableId-based IDs and
        // must NOT be claimed by the built-in section.
        return row.rowType == HomeRowType.collections &&
            !row.id.startsWith('pluginDynamic:');
      case HomeSectionType.genres:
        return row.rowType == HomeRowType.genres &&
            !row.id.startsWith('pluginDynamic:');
      case HomeSectionType.studios:
        return row.rowType == HomeRowType.studios &&
            !row.id.startsWith('pluginDynamic:');
      case HomeSectionType.libraryTilesSmall:
        return row.rowType == HomeRowType.libraryTiles;
      case HomeSectionType.libraryButtons:
        return row.rowType == HomeRowType.libraryTilesSmall;
      case HomeSectionType.playlists:
        return row.rowType == HomeRowType.playlists &&
            !row.id.startsWith('pluginDynamic:');
      case HomeSectionType.audioArtists:
        return row.rowType == HomeRowType.audioArtists;
      case HomeSectionType.audioAlbums:
        return row.rowType == HomeRowType.audioAlbums;
      case HomeSectionType.audioPlaylists:
        return row.rowType == HomeRowType.audioPlaylists;
      case HomeSectionType.liveTv:
        return row.rowType == HomeRowType.liveTv ||
            (row.rowType == HomeRowType.liveTvOnNow && row.id != 'onNow') ||
            row.rowType == HomeRowType.liveTvFavorites;
      case HomeSectionType.onNow:
        return row.rowType == HomeRowType.liveTvOnNow && row.id == 'onNow';
      case HomeSectionType.activeRecordings:
        return row.rowType == HomeRowType.activeRecordings;
      case HomeSectionType.seerrForYou:
        return row.id == forYouRowId;
      case HomeSectionType.seerrMyRequests:
        return row.id == myRequestsRowId;
      case HomeSectionType.seerrSagas:
        return row.id == sagaRowId;
      case HomeSectionType.seerrGems:
        return row.id == gemsRowId;
      case HomeSectionType.seerrUpcoming:
        return row.id == upcomingRowId;
      case HomeSectionType.familyNight:
        return row.id == familyRowId;
      case HomeSectionType.seerrBecause:
        return row.id.startsWith(becauseRowIdPrefix);
      case HomeSectionType.top10Movies:
        return row.id == top10MoviesRowId;
      case HomeSectionType.top10Series:
        return row.id == top10SeriesRowId;
      case HomeSectionType.frenchMovies:
        return row.id == frenchMoviesRowId;
      case HomeSectionType.frenchSeries:
        return row.id == frenchSeriesRowId;
      case HomeSectionType.frenchClassics:
        return row.id == frenchClassicsRowId;
      case HomeSectionType.surprise:
        return row.id == surpriseRowId;
      case HomeSectionType.seerrShortcuts:
        return row.id == 'seerr_shortcuts';
      case HomeSectionType.seerrRecentRequests:
        return row.id == 'seerr_recent_requests';
      case HomeSectionType.seerrWatchlist:
        return row.id == 'seerr_watchlist';
      case HomeSectionType.seerrRecentlyAdded:
        return row.id == 'seerr_recently_added';
      case HomeSectionType.seerrPopularMovies:
        return row.id == 'seerr_popular_movies';
      case HomeSectionType.seerrUpcomingMovies:
        return row.id == 'seerr_upcoming_movies';
      case HomeSectionType.seerrPopularSeries:
        return row.id == 'seerr_popular_series';
      case HomeSectionType.seerrUpcomingSeries:
        return row.id == 'seerr_upcoming_series';
      case HomeSectionType.seerrTrending:
        return row.id == 'seerr_trending';
      case HomeSectionType.seerrMovieGenres:
        return row.id == 'seerr_movie_genres';
      case HomeSectionType.seerrStudios:
        return row.id == 'seerr_studios';
      case HomeSectionType.seerrSeriesGenres:
        return row.id == 'seerr_series_genres';
      case HomeSectionType.seerrNetworks:
        return row.id == 'seerr_networks';
      case HomeSectionType.imdbTop250Movies:
        return row.id == 'imdb_top_250_movies';
      case HomeSectionType.imdbTop250TvShows:
        return row.id == 'imdb_top_250_tv_shows';
      case HomeSectionType.imdbMostPopularMovies:
        return row.id == 'imdb_most_popular_movies';
      case HomeSectionType.imdbMostPopularTvShows:
        return row.id == 'imdb_most_popular_tv_shows';
      case HomeSectionType.imdbLowestRatedMovies:
        return row.id == 'imdb_lowest_rated_movies';
      case HomeSectionType.imdbTopEnglishMovies:
        return row.id == 'imdb_top_english_movies';
      case HomeSectionType.tmdbPopularMovies:
        return row.id == 'tmdb_popular_movies';
      case HomeSectionType.tmdbTopRatedMovies:
        return row.id == 'tmdb_top_rated_movies';
      case HomeSectionType.tmdbNowPlayingMovies:
        return row.id == 'tmdb_now_playing_movies';
      case HomeSectionType.tmdbUpcomingMovies:
        return row.id == 'tmdb_upcoming_movies';
      case HomeSectionType.tmdbPopularTv:
        return row.id == 'tmdb_popular_tv';
      case HomeSectionType.tmdbTopRatedTv:
        return row.id == 'tmdb_top_rated_tv';
      case HomeSectionType.tmdbAiringTodayTv:
        return row.id == 'tmdb_airing_today_tv';
      case HomeSectionType.tmdbOnTheAirTv:
        return row.id == 'tmdb_on_the_air_tv';
      case HomeSectionType.tmdbTrendingMovieDaily:
        return row.id == 'tmdb_trending_movie_daily';
      case HomeSectionType.tmdbTrendingMovieWeekly:
        return row.id == 'tmdb_trending_movie_weekly';
      case HomeSectionType.tmdbTrendingTvDaily:
        return row.id == 'tmdb_trending_tv_daily';
      case HomeSectionType.tmdbTrendingTvWeekly:
        return row.id == 'tmdb_trending_tv_weekly';
      case HomeSectionType.tmdbTrendingAllWeekly:
        return row.id == 'tmdb_trending_all_weekly';
      case HomeSectionType.radarrCalendar:
        return row.id == 'radarr_calendar';
      case HomeSectionType.sonarrCalendar:
        return row.id == 'sonarr_calendar';
      case HomeSectionType.seasonal:
        return row.id == 'seasonal';
      case HomeSectionType.mediaBar:
      case HomeSectionType.recentlyReleased:
        return row.rowType == HomeRowType.recentlyReleased;
      case HomeSectionType.sinceYouWatched1:
      case HomeSectionType.sinceYouWatched2:
      case HomeSectionType.sinceYouWatched3:
      case HomeSectionType.sinceYouWatched4:
      case HomeSectionType.sinceYouWatched5:
        final idx = cfg.type.sinceYouWatchedRow;
        return row.rowType == HomeRowType.latestMedia && row.id == 'sinceYouWatched$idx';
      case HomeSectionType.rewatch:
        return row.rowType == HomeRowType.latestMedia && row.id == 'rewatch';
      case HomeSectionType.resumeBook:
      case HomeSectionType.none:
        return false;
    }
  }

  Future<void> refresh({
    bool preserveExisting = true,
    bool newMediaBar = false,
    bool newSectionsOnly = false,
  }) async {
    if (newMediaBar) unawaited(_mediaBarViewModel.load(force: true));
    await load(
      preserveExisting: preserveExisting,
      newSectionsOnly: newSectionsOnly,
    );
  }

  /// Lightweight refresh for returning to home from a pushed route. Viewing or
  /// playing an item only changes the resume and next-up rows, so this refetches
  /// just those and updates them in place, leaving every other row (and its
  /// pagination, scroll, and focus state) untouched. A full [refresh] still runs
  /// on the Home button, pull-to-refresh, cold start, and periodic refresh.
  Future<void> refreshResumeAndNextUp() async {
    // A full load already covers these rows, so don't compete with it.
    if (_isLoading) return;

    if (_prefs.effectiveMergeContinueWatchingNextUp) {
      await _loadResumeAndNextUpInBackground();
      return;
    }

    if (_bgResumeRefreshInFlight) return;
    _bgResumeRefreshInFlight = true;
    try {
      await Future.wait([
        _refreshRowInPlace(
          'resume',
          () => _multiServerEnabled
              ? _multiServerRepo.getAggregatedResume()
              : _dataSource.loadResume(_serverId),
          _prefs.filterContinueWatching,
        ),
        _refreshRowInPlace(
          'nextUp',
          () => _multiServerEnabled
              ? _multiServerRepo.getAggregatedNextUp()
              : _dataSource.loadNextUp(_serverId),
          _prefs.filterNextUp,
        ),
        _refreshRowInPlace(
          'resumeAudio',
          () => _multiServerEnabled
              ? _multiServerRepo.getAggregatedResumeAudio()
              : _dataSource.loadResumeAudio(_serverId),
          _prefs.filterContinueWatching,
        ),
      ]);
    } finally {
      _bgResumeRefreshInFlight = false;
    }
    _saveRowCache();
    _topShelf.update(_rows);
    _watchNext.update(_rows);
    _tvChannels.update();
  }

  /// Refetches the row with [rowId] and replaces it in place, or removes it when
  /// it becomes empty. Does nothing when the row isn't currently present (e.g.
  /// the section is disabled), so it never disturbs the rest of the list.
  Future<void> _refreshRowInPlace(
    String rowId,
    Future<HomeRow> Function() fetch,
    List<AggregatedItem> Function(List<AggregatedItem>) filter,
  ) async {
    if (!_rows.any((r) => r.id == rowId)) return;
    final HomeRow fresh;
    try {
      fresh = await fetch();
    } catch (_) {
      // Transient failure: keep the existing row rather than wiping it.
      return;
    }
    final index = _rows.indexWhere((r) => r.id == rowId);
    if (index < 0) return;
    final items = _filterEmptyElements(filter(fresh.items));
    _rows = List.of(_rows);
    if (items.isEmpty) {
      _emptySectionIds.add(rowId);
      _rows.removeAt(index);
    } else {
      _emptySectionIds.remove(rowId);
      _rows[index] = _rows[index].copyWith(items: items, isLoading: false);
    }
    notifyListeners();
  }

  Future<void> loadMoreForRow(int rowIndex) async {
    final displayedRows = rows;
    if (rowIndex < 0 || rowIndex >= displayedRows.length) return;
    // Placeholders of sections expected to be empty are hidden, so the index
    // on screen can differ from the one the paging loaders use.
    rowIndex = _rows.indexWhere((row) => row.id == displayedRows[rowIndex].id);
    if (rowIndex < 0) return;
    final row = _rows[rowIndex];
    if (!row.hasMore || _inFlightPagingRowIds.contains(row.id)) return;

    _inFlightPagingRowIds.add(row.id);
    _rowsPagedThisLoad.add(row.id);
    try {
      final seerrType = _seerrRowTypeForId(row.id);
      if (seerrType != null) {
        await _loadMoreSeerrRow(rowIndex, seerrType);
        return;
      }
      final slider = _seerrSliderRows[row.id];
      if (slider != null) {
        await _loadMoreSeerrSliderRow(rowIndex, slider);
        return;
      }

      // The aggregated multi-server rows take no offset, so they keep the
      // paging they already had.
      if (row.id == 'resume' &&
          !_multiServerEnabled &&
          _prefs.effectiveMergeContinueWatchingNextUp) {
        await _loadMoreMergedResume(rowIndex);
        return;
      }

      final int currentOffset = _rowOffsets[row.id] ?? row.items.length;
      final (List<AggregatedItem> items, int totalCount) result;
      if (_multiServerEnabled && !row.id.startsWith('pluginDynamic:')) {
        result = await _multiServerRepo.loadMore(row: row);
      } else {
        final other = _otherServerRows[row.id];
        result = await _dataSourceFor(other).loadMore(
          row: row,
          serverId: other?.server.id ?? _serverId,
          offset: currentOffset,
        );
      }
      _rowOffsets[row.id] = currentOffset + _rowPageSize;

      final filteredItems = _filterEmptyElements(result.$1);
      final newTotalCount = filteredItems.length <= row.items.length
          ? filteredItems.length
          : (result.$2 - (result.$1.length - filteredItems.length));
      _replaceRowById(
        row.copyWith(items: filteredItems, totalCount: newTotalCount),
      );
    } catch (_) {
    } finally {
      _inFlightPagingRowIds.remove(row.id);
    }
  }

  /// Puts a paged [row] back wherever its id sits now. A section that
  /// finished loading during the page request can have moved it.
  void _replaceRowById(HomeRow row) {
    final index = _rows.indexWhere((r) => r.id == row.id);
    if (index < 0) return;
    _rows = List.of(_rows)..[index] = row;
    notifyListeners();
  }

  Future<List<HomeRow>> _loadConfig(HomeSectionConfig cfg, {bool forceRefresh = false}) async {
    if (isSeerrSliderSection(cfg)) return _loadSeerrSliderRow(cfg);
    if (cfg.isPluginDynamic) {
      final section = cfg.pluginSection;
      if (section == null || section.isEmpty) return const [];
      final other = _otherServerRows[cfg.stableId];
      final row = await _dataSourceFor(other).loadDynamicSection(
        rowId: cfg.stableId,
        section: section,
        title: cfg.pluginDisplayText ?? section,
        serverId: other?.server.id ?? _serverId,
        additionalData: cfg.pluginAdditionalData,
        pluginSource: cfg.pluginSource,
        forceRefresh: forceRefresh,
      );
      return [row];
    }
    return _loadSection(cfg.type, forceRefresh: forceRefresh);
  }

  /// Kept per server so a collection the user can't open isn't asked for
  /// again on every load.
  final Map<String, RowDataSource> _otherServerSources = {};

  RowDataSource _dataSourceFor(ServerUserSession? other) => other == null
      ? _dataSource
      : _otherServerSources.putIfAbsent(
          other.server.id,
          () => RowDataSource(other.client),
        );

  HomeRow? _placeholderForConfig(HomeSectionConfig cfg) {
    if (cfg.isPluginDynamic) {
      final section = cfg.pluginSection;
      if (section == null || section.isEmpty) return null;
      return HomeRow(
        id: cfg.stableId,
        title: cfg.pluginDisplayText ?? section,
        rowType: HomeRowType.pluginDynamic,
        isLoading: true,
      );
    }
    return _placeholderForSection(cfg.type);
  }

  static Set<String> _duplicateKeysForConfig(HomeSectionConfig cfg) {
    if (cfg.isBuiltin) {
      return _duplicateKeysForBuiltin(cfg.type);
    }
    return const <String>{};
  }

  static Set<String> _duplicateKeysForBuiltin(HomeSectionType type) {
    switch (type) {
      case HomeSectionType.latestMedia:
        return const {'latestMedia'};
      case HomeSectionType.recentlyReleased:
        return const {'recentlyReleased'};
      case HomeSectionType.resume:
        return const {'resume'};
      case HomeSectionType.resumeAudio:
        return const {'resumeAudio'};
      case HomeSectionType.resumeBook:
        return const {'resumeBook'};
      case HomeSectionType.nextUp:
        return const {'nextUp'};
      case HomeSectionType.liveTv:
        return const {'liveTv'};
      case HomeSectionType.onNow:
        return const {'onNow'};
      case HomeSectionType.libraryTilesSmall:
        return const {'libraryTiles'};
      case HomeSectionType.libraryButtons:
        return const {'libraryButtons'};
      case HomeSectionType.playlists:
        return const {'playlists'};
      case HomeSectionType.favoriteMovies:
        return const {'favoriteMovies'};
      case HomeSectionType.favoriteSeries:
        return const {'favoriteSeries'};
      case HomeSectionType.favoriteEpisodes:
        return const {'favoriteEpisodes'};
      case HomeSectionType.favoritePeople:
        return const {'favoritePeople'};
      case HomeSectionType.favoriteArtists:
        return const {'favoriteArtists'};
      case HomeSectionType.favoriteMusicVideos:
        return const {'favoriteMusicVideos'};
      case HomeSectionType.favoriteAlbums:
        return const {'favoriteAlbums'};
      case HomeSectionType.favoriteSongs:
        return const {'favoriteSongs'};
      case HomeSectionType.collections:
        return const {'collections'};
      case HomeSectionType.genres:
        return const {'genres'};
      case HomeSectionType.studios:
        return const {'studios'};
      case HomeSectionType.activeRecordings:
        return const {'activeRecordings'};
      case HomeSectionType.seerrForYou:
        return const {'seerrForYou'};
      case HomeSectionType.seerrMyRequests:
        return const {'seerrMyRequests'};
      case HomeSectionType.seerrSagas:
        return const {'seerrSagas'};
      case HomeSectionType.seerrGems:
        return const {'seerrGems'};
      case HomeSectionType.seerrUpcoming:
        return const {'seerrUpcoming'};
      case HomeSectionType.familyNight:
        return const {'familyNight'};
      case HomeSectionType.seerrBecause:
        return const {'seerrBecause'};
      case HomeSectionType.top10Movies:
        return const {'top10Movies'};
      case HomeSectionType.top10Series:
        return const {'top10Series'};
      case HomeSectionType.frenchMovies:
        return const {'frenchMovies'};
      case HomeSectionType.frenchSeries:
        return const {'frenchSeries'};
      case HomeSectionType.frenchClassics:
        return const {'frenchClassics'};
      case HomeSectionType.surprise:
        return const {'surprise'};
      case HomeSectionType.seerrShortcuts:
        return const {'seerrShortcuts'};
      case HomeSectionType.seerrRecentRequests:
        return const {'seerrRecentRequests'};
      case HomeSectionType.seerrWatchlist:
        return const {'seerrWatchlist'};
      case HomeSectionType.seerrRecentlyAdded:
        return const {'seerrRecentlyAdded'};
      case HomeSectionType.seerrPopularMovies:
        return const {'seerrPopularMovies'};
      case HomeSectionType.seerrUpcomingMovies:
        return const {'seerrUpcomingMovies'};
      case HomeSectionType.seerrPopularSeries:
        return const {'seerrPopularSeries'};
      case HomeSectionType.seerrUpcomingSeries:
        return const {'seerrUpcomingSeries'};
      case HomeSectionType.seerrTrending:
        return const {'seerrTrending'};
      case HomeSectionType.seerrMovieGenres:
        return const {'seerrMovieGenres'};
      case HomeSectionType.seerrStudios:
        return const {'seerrStudios'};
      case HomeSectionType.seerrSeriesGenres:
        return const {'seerrSeriesGenres'};
      case HomeSectionType.seerrNetworks:
        return const {'seerrNetworks'};
      case HomeSectionType.audioArtists:
        return const {'audioArtists'};
      case HomeSectionType.audioAlbums:
        return const {'audioAlbums'};
      case HomeSectionType.audioPlaylists:
        return const {'audioPlaylists'};
      case HomeSectionType.imdbTop250Movies:
        return const {'imdbTop250Movies'};
      case HomeSectionType.imdbTop250TvShows:
        return const {'imdbTop250TvShows'};
      case HomeSectionType.imdbMostPopularMovies:
        return const {'imdbMostPopularMovies'};
      case HomeSectionType.imdbMostPopularTvShows:
        return const {'imdbMostPopularTvShows'};
      case HomeSectionType.imdbLowestRatedMovies:
        return const {'imdbLowestRatedMovies'};
      case HomeSectionType.imdbTopEnglishMovies:
        return const {'imdbTopEnglishMovies'};
      case HomeSectionType.tmdbPopularMovies:
        return const {'tmdbPopularMovies'};
      case HomeSectionType.tmdbTopRatedMovies:
        return const {'tmdbTopRatedMovies'};
      case HomeSectionType.tmdbNowPlayingMovies:
        return const {'tmdbNowPlayingMovies'};
      case HomeSectionType.tmdbUpcomingMovies:
        return const {'tmdbUpcomingMovies'};
      case HomeSectionType.tmdbPopularTv:
        return const {'tmdbPopularTv'};
      case HomeSectionType.tmdbTopRatedTv:
        return const {'tmdbTopRatedTv'};
      case HomeSectionType.tmdbAiringTodayTv:
        return const {'tmdbAiringTodayTv'};
      case HomeSectionType.tmdbOnTheAirTv:
        return const {'tmdbOnTheAirTv'};
      case HomeSectionType.tmdbTrendingMovieDaily:
        return const {'tmdbTrendingMovieDaily'};
      case HomeSectionType.tmdbTrendingMovieWeekly:
        return const {'tmdbTrendingMovieWeekly'};
      case HomeSectionType.tmdbTrendingTvDaily:
        return const {'tmdbTrendingTvDaily'};
      case HomeSectionType.tmdbTrendingTvWeekly:
        return const {'tmdbTrendingTvWeekly'};
      case HomeSectionType.tmdbTrendingAllWeekly:
        return const {'tmdbTrendingAllWeekly'};
      case HomeSectionType.radarrCalendar:
        return const {'radarrCalendar'};
      case HomeSectionType.sonarrCalendar:
        return const {'sonarrCalendar'};
      case HomeSectionType.seasonal:
        return const {'seasonal'};
      case HomeSectionType.sinceYouWatched1:
        return const {'sinceYouWatched1'};
      case HomeSectionType.sinceYouWatched2:
        return const {'sinceYouWatched2'};
      case HomeSectionType.sinceYouWatched3:
        return const {'sinceYouWatched3'};
      case HomeSectionType.sinceYouWatched4:
        return const {'sinceYouWatched4'};
      case HomeSectionType.sinceYouWatched5:
        return const {'sinceYouWatched5'};
      case HomeSectionType.rewatch:
        return const {'rewatch'};
      case HomeSectionType.mediaBar:
      case HomeSectionType.none:
        return const <String>{};
    }
  }

  Future<List<HomeRow>> _loadSection(HomeSectionType section, {bool forceRefresh = false}) async {
    final l10n = currentAppLocalizations();
    final favoritesSortBy = _prefs
        .get(UserPreferences.favoritesRowSortBy)
        .apiValue;
    final favoritesSortOrder = _prefs
        .get(UserPreferences.favoritesRowSortOrder)
        .apiValue;
    final collectionsSortBy = _prefs
        .get(UserPreferences.collectionsRowSortBy)
        .apiValue;
    final collectionsSortOrder = _prefs
        .get(UserPreferences.collectionsRowSortOrder)
        .apiValue;
    final genresSortBy = _prefs.get(UserPreferences.genresRowSortBy).apiValue;
    final genresSortOrder = _prefs
        .get(UserPreferences.genresRowSortOrder)
        .apiValue;
    final genresItemFilter = _prefs
        .get(UserPreferences.genresRowItemFilter)
        .includeItemTypes;
    switch (section) {
      case HomeSectionType.resume:
        final row = _multiServerEnabled
            ? await _multiServerRepo.getAggregatedResume()
            : await _dataSource.loadResume(_serverId);
        return [row.copyWith(items: _prefs.filterContinueWatching(row.items))];
      case HomeSectionType.resumeAudio:
        final row = _multiServerEnabled
            ? await _multiServerRepo.getAggregatedResumeAudio()
            : await _dataSource.loadResumeAudio(_serverId);
        return [row.copyWith(items: _prefs.filterContinueWatching(row.items))];
      case HomeSectionType.nextUp:
        final row = _multiServerEnabled
            ? await _multiServerRepo.getAggregatedNextUp()
            : await _dataSource.loadNextUp(_serverId);
        return [row.copyWith(items: _prefs.filterNextUp(row.items))];
      case HomeSectionType.latestMedia:
        return _multiServerEnabled
            ? await _multiServerRepo.getAggregatedLatestMediaRows()
            : _loadLatestMediaRows();
      case HomeSectionType.playlists:
        final playlistsSortBy = _prefs
            .get(UserPreferences.playlistsRowSortBy)
            .apiValue;
        final playlistsSortOrder = _prefs
            .get(UserPreferences.playlistsRowSortOrder)
            .apiValue;
        return [
          _multiServerEnabled
              ? await _multiServerRepo.getAggregatedPlaylists(
                  sortBy: playlistsSortBy,
                  sortOrder: playlistsSortOrder,
                )
              : await _dataSource.loadPlaylists(
                  _serverId,
                  sortBy: playlistsSortBy,
                  sortOrder: playlistsSortOrder,
                ),
        ];
      case HomeSectionType.audioArtists:
        final audioSortBy = _prefs
            .get(UserPreferences.audioRowsSortBy)
            .apiValue;
        final audioSortOrder = _prefs
            .get(UserPreferences.audioRowsSortOrder)
            .apiValue;
        return [
          _multiServerEnabled
              ? await _multiServerRepo.getAggregatedAudioArtists(
                  sortBy: audioSortBy,
                  sortOrder: audioSortOrder,
                )
              : await _dataSource.loadAudioArtists(
                  _serverId,
                  sortBy: audioSortBy,
                  sortOrder: audioSortOrder,
                ),
        ];
      case HomeSectionType.audioAlbums:
        final audioSortBy = _prefs
            .get(UserPreferences.audioRowsSortBy)
            .apiValue;
        final audioSortOrder = _prefs
            .get(UserPreferences.audioRowsSortOrder)
            .apiValue;
        return [
          _multiServerEnabled
              ? await _multiServerRepo.getAggregatedAudioAlbums(
                  sortBy: audioSortBy,
                  sortOrder: audioSortOrder,
                )
              : await _dataSource.loadAudioAlbums(
                  _serverId,
                  sortBy: audioSortBy,
                  sortOrder: audioSortOrder,
                ),
        ];
      case HomeSectionType.audioPlaylists:
        final audioSortBy = _prefs
            .get(UserPreferences.audioRowsSortBy)
            .apiValue;
        final audioSortOrder = _prefs
            .get(UserPreferences.audioRowsSortOrder)
            .apiValue;
        return [
          _multiServerEnabled
              ? await _multiServerRepo.getAggregatedAudioPlaylists(
                  sortBy: audioSortBy,
                  sortOrder: audioSortOrder,
                )
              : await _dataSource.loadAudioPlaylists(
                  _serverId,
                  sortBy: audioSortBy,
                  sortOrder: audioSortOrder,
                ),
        ];
      case HomeSectionType.favoriteMovies:
      case HomeSectionType.favoriteSeries:
      case HomeSectionType.favoriteEpisodes:
      case HomeSectionType.favoritePeople:
      case HomeSectionType.favoriteArtists:
      case HomeSectionType.favoriteMusicVideos:
      case HomeSectionType.favoriteAlbums:
      case HomeSectionType.favoriteSongs:
        final favoriteFilter = _favoriteFilterForSection(section);
        final rowId = _favoriteRowIdForSection(section);
        final title = _favoriteTitleForSection(section, l10n);
        return [
          _multiServerEnabled
              ? await _multiServerRepo.getAggregatedFavorites(
                  rowId: rowId,
                  title: title,
                  includeItemTypes: favoriteFilter.itemTypes,
                  sortBy: favoritesSortBy,
                  sortOrder: favoritesSortOrder,
                )
              : await _dataSource.loadFavorites(
                  _serverId,
                  rowId: rowId,
                  title: title,
                  includeItemTypes: favoriteFilter.itemTypes,
                  sortBy: favoritesSortBy,
                  sortOrder: favoritesSortOrder,
                ),
        ];
      case HomeSectionType.collections:
        return [
          _multiServerEnabled
              ? await _multiServerRepo.getAggregatedCollections(
                  sortBy: collectionsSortBy,
                  sortOrder: collectionsSortOrder,
                )
              : await _dataSource.loadCollections(
                  _serverId,
                  sortBy: collectionsSortBy,
                  sortOrder: collectionsSortOrder,
                ),
        ];
      case HomeSectionType.genres:
        return [
          _multiServerEnabled
              ? await _multiServerRepo.getAggregatedGenres(
                  sortBy: genresSortBy,
                  sortOrder: genresSortOrder,
                  includeItemTypes: genresItemFilter,
                )
              : await _dataSource.loadGenres(
                  _serverId,
                  sortBy: genresSortBy,
                  sortOrder: genresSortOrder,
                  includeItemTypes: genresItemFilter,
                ),
        ];
      case HomeSectionType.studios:
        final studiosSortBy = _prefs.get(UserPreferences.studiosRowSortBy).apiValue;
        final studiosSortOrder = _prefs.get(UserPreferences.studiosRowSortOrder).apiValue;
        final selectedIds = _prefs.get(UserPreferences.studiosRowSelectedIds);
        return [
          _multiServerEnabled
              ? await _multiServerRepo.getAggregatedStudios(
                  sortBy: studiosSortBy,
                  sortOrder: studiosSortOrder,
                  selectedIds: selectedIds,
                  title: l10n.studios,
                )
              : await _dataSource.loadStudios(
                  _serverId,
                  sortBy: studiosSortBy,
                  sortOrder: studiosSortOrder,
                  selectedIds: selectedIds,
                  title: l10n.studios,
                ),
        ];
      case HomeSectionType.libraryTilesSmall:
        return [
          _multiServerEnabled
              ? await _multiServerRepo.getAggregatedLibraryTiles(
                  rowType: HomeRowType.libraryTiles,
                )
              : await _dataSource.loadLibraryTiles(
                  _serverId,
                  HomeRowType.libraryTiles,
                ),
        ];
      case HomeSectionType.libraryButtons:
        return [
          _multiServerEnabled
              ? await _multiServerRepo.getAggregatedLibraryTiles(
                  rowType: HomeRowType.libraryTilesSmall,
                )
              : await _dataSource.loadLibraryTiles(
                  _serverId,
                  HomeRowType.libraryTilesSmall,
                ),
        ];
      case HomeSectionType.liveTv:
        try {
          if (!await _dataSource.hasLiveTvChannels()) return [];
        } catch (_) {
          return [];
        }
        final rows = <HomeRow>[
          HomeRow(
            id: 'liveTv',
            title: l10n.liveTv,
            rowType: HomeRowType.liveTv,
            items: const [],
          ),
        ];
        try {
          // The standalone On Now section shows this row in its own spot.
          if (!_prefs.activeHomeSections.contains(HomeSectionType.onNow)) {
            final onNow = await _dataSource.loadOnNow(_serverId);
            if (onNow.items.isNotEmpty) rows.add(onNow);
          }
          final favorites = await _dataSource.loadFavoritesChannels(_serverId);
          if (favorites.items.isNotEmpty) rows.add(favorites);
        } catch (_) {}
        return rows;
      case HomeSectionType.onNow:
        if (!await _dataSource.hasLiveTvChannels()) return [];
        return [(await _dataSource.loadOnNow(_serverId)).copyWith(id: 'onNow')];
      case HomeSectionType.activeRecordings:
        return [
          HomeRow(
            id: 'activeRecordings',
            title: l10n.activeRecordings,
            rowType: HomeRowType.activeRecordings,
          ),
        ];
      case HomeSectionType.mediaBar:
        _mediaBarViewModel.load();
        return [];
      case HomeSectionType.seerrForYou:
        return _loadSeerrForYouRow(l10n, forceRefresh: forceRefresh);
      case HomeSectionType.seerrMyRequests:
        return _loadMyRequestsRow(l10n);
      case HomeSectionType.seerrSagas:
        return _loadSagaRow(l10n, forceRefresh: forceRefresh);
      case HomeSectionType.seerrGems:
        return _loadGemsRow(l10n, forceRefresh: forceRefresh);
      case HomeSectionType.seerrUpcoming:
        return _loadUpcomingRow(l10n, forceRefresh: forceRefresh);
      case HomeSectionType.familyNight:
        return _loadFamilyRow(l10n);
      case HomeSectionType.seerrBecause:
        return _loadBecauseRows(l10n, forceRefresh: forceRefresh);
      case HomeSectionType.top10Movies:
        return _loadTop10Row(l10n, 'movie', forceRefresh: forceRefresh);
      case HomeSectionType.top10Series:
        return _loadTop10Row(l10n, 'tv', forceRefresh: forceRefresh);
      case HomeSectionType.frenchMovies:
      case HomeSectionType.frenchSeries:
      case HomeSectionType.frenchClassics:
        return _loadFrenchRow(l10n, section, forceRefresh: forceRefresh);
      case HomeSectionType.surprise:
        return _loadSurpriseRow(l10n);
      case HomeSectionType.seerrShortcuts:
        return [await _loadSeerrShortcutsRow(l10n)];
      case HomeSectionType.seerrRecentRequests:
        return _loadSeerrRow(
          SeerrRowType.recentRequests,
          l10n.recentRequests,
          'seerr_recent_requests',
        );
      case HomeSectionType.seerrWatchlist:
        return _loadSeerrRow(
          SeerrRowType.yourWatchlist,
          l10n.yourWatchlist,
          'seerr_watchlist',
        );
      case HomeSectionType.seerrRecentlyAdded:
        return _loadSeerrRow(
          SeerrRowType.recentlyAdded,
          l10n.recentlyAdded,
          'seerr_recently_added',
        );
      case HomeSectionType.seerrPopularMovies:
        return _loadSeerrRow(
          SeerrRowType.popularMovies,
          l10n.popularMovies,
          'seerr_popular_movies',
        );
      case HomeSectionType.seerrUpcomingMovies:
        return _loadSeerrRow(
          SeerrRowType.upcomingMovies,
          l10n.upcomingMovies,
          'seerr_upcoming_movies',
        );
      case HomeSectionType.seerrPopularSeries:
        return _loadSeerrRow(
          SeerrRowType.popularSeries,
          l10n.popularSeries,
          'seerr_popular_series',
        );
      case HomeSectionType.seerrUpcomingSeries:
        return _loadSeerrRow(
          SeerrRowType.upcomingSeries,
          l10n.upcomingSeries,
          'seerr_upcoming_series',
        );
      case HomeSectionType.seerrTrending:
        return _loadSeerrRow(
          SeerrRowType.trending,
          l10n.trending,
          'seerr_trending',
        );
      case HomeSectionType.seerrMovieGenres:
        return _loadSeerrRow(
          SeerrRowType.movieGenres,
          l10n.movieGenres,
          'seerr_movie_genres',
        );
      case HomeSectionType.seerrStudios:
        return _loadSeerrRow(
          SeerrRowType.studios,
          l10n.studios,
          'seerr_studios',
        );
      case HomeSectionType.seerrSeriesGenres:
        return _loadSeerrRow(
          SeerrRowType.seriesGenres,
          l10n.seriesGenres,
          'seerr_series_genres',
        );
      case HomeSectionType.seerrNetworks:
        return _loadSeerrRow(
          SeerrRowType.networks,
          l10n.networks,
          'seerr_networks',
        );
      case HomeSectionType.radarrCalendar:
        return _loadRadarrCalendarRow(forceRefresh: forceRefresh);
      case HomeSectionType.sonarrCalendar:
        return _loadSonarrCalendarRow(forceRefresh: forceRefresh);
      case HomeSectionType.imdbTop250Movies:
        return _loadImdbRow(
          HomeSectionType.imdbTop250Movies,
          l10n.imdbTop250Movies,
          'imdb_top_250_movies',
        );
      case HomeSectionType.imdbTop250TvShows:
        return _loadImdbRow(
          HomeSectionType.imdbTop250TvShows,
          l10n.imdbTop250TvShows,
          'imdb_top_250_tv_shows',
        );
      case HomeSectionType.imdbMostPopularMovies:
        return _loadImdbRow(
          HomeSectionType.imdbMostPopularMovies,
          l10n.imdbMostPopularMovies,
          'imdb_most_popular_movies',
        );
      case HomeSectionType.imdbMostPopularTvShows:
        return _loadImdbRow(
          HomeSectionType.imdbMostPopularTvShows,
          l10n.imdbMostPopularTvShows,
          'imdb_most_popular_tv_shows',
        );
      case HomeSectionType.imdbLowestRatedMovies:
        return _loadImdbRow(
          HomeSectionType.imdbLowestRatedMovies,
          l10n.imdbLowestRatedMovies,
          'imdb_lowest_rated_movies',
        );
      case HomeSectionType.imdbTopEnglishMovies:
        return _loadImdbRow(
          HomeSectionType.imdbTopEnglishMovies,
          l10n.imdbTopEnglishMovies,
          'imdb_top_english_movies',
        );
      case HomeSectionType.tmdbPopularMovies:
        return _loadTmdbChartRow(HomeSectionType.tmdbPopularMovies, 'Popular Movies', 'tmdb_popular_movies');
      case HomeSectionType.tmdbTopRatedMovies:
        return _loadTmdbChartRow(HomeSectionType.tmdbTopRatedMovies, 'Top Rated Movies', 'tmdb_top_rated_movies');
      case HomeSectionType.tmdbNowPlayingMovies:
        return _loadTmdbChartRow(HomeSectionType.tmdbNowPlayingMovies, 'Now Playing Movies', 'tmdb_now_playing_movies');
      case HomeSectionType.tmdbUpcomingMovies:
        return _loadTmdbChartRow(HomeSectionType.tmdbUpcomingMovies, 'Upcoming Movies', 'tmdb_upcoming_movies');
      case HomeSectionType.tmdbPopularTv:
        return _loadTmdbChartRow(HomeSectionType.tmdbPopularTv, 'Popular TV', 'tmdb_popular_tv');
      case HomeSectionType.tmdbTopRatedTv:
        return _loadTmdbChartRow(HomeSectionType.tmdbTopRatedTv, 'Top Rated TV', 'tmdb_top_rated_tv');
      case HomeSectionType.tmdbAiringTodayTv:
        return _loadTmdbChartRow(HomeSectionType.tmdbAiringTodayTv, 'Airing Today TV', 'tmdb_airing_today_tv');
      case HomeSectionType.tmdbOnTheAirTv:
        return _loadTmdbChartRow(HomeSectionType.tmdbOnTheAirTv, 'On The Air TV', 'tmdb_on_the_air_tv');
      case HomeSectionType.tmdbTrendingMovieDaily:
        return _loadTmdbChartRow(HomeSectionType.tmdbTrendingMovieDaily, 'Trending Movies (Daily)', 'tmdb_trending_movie_daily');
      case HomeSectionType.tmdbTrendingMovieWeekly:
        return _loadTmdbChartRow(HomeSectionType.tmdbTrendingMovieWeekly, 'Trending Movies (Weekly)', 'tmdb_trending_movie_weekly');
      case HomeSectionType.tmdbTrendingTvDaily:
        return _loadTmdbChartRow(HomeSectionType.tmdbTrendingTvDaily, 'Trending TV (Daily)', 'tmdb_trending_tv_daily');
      case HomeSectionType.tmdbTrendingTvWeekly:
        return _loadTmdbChartRow(HomeSectionType.tmdbTrendingTvWeekly, 'Trending TV (Weekly)', 'tmdb_trending_tv_weekly');
      case HomeSectionType.tmdbTrendingAllWeekly:
        return _loadTmdbChartRow(HomeSectionType.tmdbTrendingAllWeekly, 'Trending All (Weekly)', 'tmdb_trending_all_weekly');
      case HomeSectionType.recentlyReleased:
        return _loadRecentlyReleasedRow();
      case HomeSectionType.seasonal:
        return _loadSeasonalRow(l10n, forceRefresh: forceRefresh);
      case HomeSectionType.sinceYouWatched1:
      case HomeSectionType.sinceYouWatched2:
      case HomeSectionType.sinceYouWatched3:
      case HomeSectionType.sinceYouWatched4:
      case HomeSectionType.sinceYouWatched5:
        final rowIndex = section.sinceYouWatchedRow;
        final row = await _dataSource.loadSinceYouWatchedRow(_serverId, rowIndex);
        return [row];
      case HomeSectionType.rewatch:
        final row = await _dataSource.loadRewatchRow(_serverId);
        return [row];
      case HomeSectionType.resumeBook:
      case HomeSectionType.none:
        return [];
    }
  }

  Future<List<HomeRow>> _loadLatestMediaRows() {
    return _loadRecentRows(
      load: (lib, type) =>
          _dataSource.loadLatestMedia(lib.id, lib.name, _serverId, type),
      sortKey: (item) => _parseDate(item.rawData['DateCreated']),
      idPrefix: 'latest',
      rowType: HomeRowType.latestMedia,
      mergedTitle: (l10n, descriptor) => l10n.latestLibraryName(descriptor),
    );
  }

  Future<List<HomeRow>> _loadRecentlyReleasedRow() {
    return _loadRecentRows(
      load: (lib, type) =>
          _dataSource.loadRecentlyReleased(lib.id, lib.name, _serverId, type),
      sortKey: _premiereDateOf,
      idPrefix: 'recently_released',
      rowType: HomeRowType.recentlyReleased,
      mergedTitle: (l10n, descriptor) =>
          l10n.recentlyReleasedLibraryName(descriptor),
    );
  }

  /// One row per library, or one row per media kind when the user has asked for
  /// libraries of a kind to be merged.
  Future<List<HomeRow>> _loadRecentRows({
    required Future<HomeRow> Function(AggregatedLibrary lib, String type) load,
    required DateTime? Function(AggregatedItem item) sortKey,
    required String idPrefix,
    required HomeRowType rowType,
    required String Function(AppLocalizations l10n, String descriptor)
        mergedTitle,
  }) async {
    final viewsRepo = GetIt.instance<UserViewsRepository>();
    final viewsFuture = viewsRepo.getAllViewsIncludingHidden();
    final configFuture = viewsRepo
        .cachedUserConfiguration()
        .then<Set<String>>((config) => config.latestItemsExcludes.toSet())
        .catchError((_) => const <String>{});

    final views = await viewsFuture;
    final Set<String> latestExcludes = await configFuture;

    final filteredViews = views.where((lib) {
      final collectionType = lib.collectionType.toLowerCase();
      if (collectionType == 'playlists' ||
          collectionType == 'boxsets' ||
          collectionType == 'livetv') {
        return false;
      }
      return !latestExcludes.contains(lib.id);
    }).toList();

    Future<HomeRow?> rowFor(AggregatedLibrary lib) async {
      try {
        return await load(lib, lib.collectionType.toLowerCase());
      } catch (_) {
        return null;
      }
    }

    if (!_prefs.get(UserPreferences.mergeRecentRowsByType)) {
      final resolved = await Future.wait(filteredViews.map(rowFor));
      return resolved
          .whereType<HomeRow>()
          .where((row) => row.items.isNotEmpty)
          .toList();
    }

    final grouped = <String, List<AggregatedLibrary>>{};
    for (final lib in filteredViews) {
      grouped.putIfAbsent(lib.collectionType.toLowerCase(), () => []).add(lib);
    }

    final l10n = currentAppLocalizations();
    final mergedRows = <HomeRow>[];
    for (final entry in grouped.entries) {
      final collectionType = entry.key;
      final loadedRows = (await Future.wait(entry.value.map(rowFor)))
          .whereType<HomeRow>();

      // The same title can sit in more than one library, so it is kept once.
      final seenIds = <String>{};
      final allItems = [
        for (final row in loadedRows)
          for (final item in row.items)
            if (seenIds.add(item.id)) item,
      ];
      if (allItems.isEmpty) continue;

      allItems.sort((a, b) {
        final da = sortKey(a);
        final db = sortKey(b);
        if (da != null && db != null) return db.compareTo(da);
        if (da != null) return -1;
        if (db != null) return 1;
        return 0;
      });

      // Trimmed to the same length a single library row gets, so merging
      // changes what a row holds rather than how big it is.
      final items = normalizeLatestMediaItems(
        allItems,
        collectionType: collectionType,
        limit: _mergedRowItemLimit,
      );
      if (items.isEmpty) continue;

      mergedRows.add(
        HomeRow(
          id: '$mergedTypeRowIdPrefix${idPrefix}_$collectionType',
          title: mergedTitle(
            l10n,
            genericDescriptorForCollectionType(l10n, collectionType),
          ),
          items: items,
          rowType: rowType,
          // Everything the row will ever hold is already here.
          totalCount: items.length,
          isAudio: collectionType == 'music',
        ),
      );
    }

    return mergedRows;
  }

  static DateTime? _parseDate(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;

  /// Release date, falling back to the production year and then to when the
  /// item was added, so an item missing one still lands somewhere sensible.
  static DateTime? _premiereDateOf(AggregatedItem item) {
    final premiere = _parseDate(item.rawData['PremiereDate']);
    if (premiere != null) return premiere;
    final year = item.rawData['ProductionYear'];
    if (year is int) return DateTime(year);
    return _parseDate(item.rawData['DateCreated']);
  }

  HomeRow? _placeholderForSection(HomeSectionType section) {
    final l10n = currentAppLocalizations();
    switch (section) {
      case HomeSectionType.resume:
        return HomeRow(
          id: 'resume',
          title: l10n.continueWatching,
          rowType: HomeRowType.resume,
          isLoading: true,
        );
      case HomeSectionType.resumeAudio:
        return HomeRow(
          id: 'resumeAudio',
          title: l10n.continueListening,
          rowType: HomeRowType.resumeAudio,
          isLoading: true,
        );
      case HomeSectionType.nextUp:
        return HomeRow(
          id: 'nextUp',
          title: l10n.nextUp,
          rowType: HomeRowType.nextUp,
          isLoading: true,
        );
      case HomeSectionType.latestMedia:
        return HomeRow(
          id: 'latestMedia',
          title: l10n.latestMedia,
          rowType: HomeRowType.latestMedia,
          isLoading: true,
        );
      case HomeSectionType.playlists:
        return HomeRow(
          id: 'playlists',
          title: l10n.playlists,
          rowType: HomeRowType.playlists,
          isLoading: true,
        );
      case HomeSectionType.audioArtists:
        return HomeRow(
          id: 'audioArtists',
          title: l10n.artists,
          rowType: HomeRowType.audioArtists,
          isLoading: true,
          isAudio: true,
        );
      case HomeSectionType.audioAlbums:
        return HomeRow(
          id: 'audioAlbums',
          title: l10n.albums,
          rowType: HomeRowType.audioAlbums,
          isLoading: true,
          isAudio: true,
        );
      case HomeSectionType.audioPlaylists:
        return HomeRow(
          id: 'audioPlaylists',
          title: l10n.audioPlaylists,
          rowType: HomeRowType.audioPlaylists,
          isLoading: true,
          isAudio: true,
        );
      case HomeSectionType.favoriteMovies:
      case HomeSectionType.favoriteSeries:
      case HomeSectionType.favoriteEpisodes:
      case HomeSectionType.favoritePeople:
      case HomeSectionType.favoriteArtists:
      case HomeSectionType.favoriteMusicVideos:
      case HomeSectionType.favoriteAlbums:
      case HomeSectionType.favoriteSongs:
        return HomeRow(
          id: _favoriteRowIdForSection(section),
          title: _favoriteTitleForSection(section, l10n),
          rowType: HomeRowType.favorites,
          isLoading: true,
        );
      case HomeSectionType.collections:
        return HomeRow(
          id: 'collections',
          title: l10n.collections,
          rowType: HomeRowType.collections,
          isLoading: true,
        );
      case HomeSectionType.genres:
        return HomeRow(
          id: 'genres',
          title: l10n.genres,
          rowType: HomeRowType.genres,
          isLoading: true,
        );
      case HomeSectionType.studios:
        return HomeRow(
          id: 'studios',
          title: l10n.studios,
          rowType: HomeRowType.studios,
          isLoading: true,
        );
      case HomeSectionType.libraryTilesSmall:
        return HomeRow(
          id: 'libraryTiles',
          title: l10n.myMedia,
          rowType: HomeRowType.libraryTiles,
          isLoading: true,
        );
      case HomeSectionType.libraryButtons:
        return HomeRow(
          id: 'libraryTilesSmall',
          title: l10n.myMedia,
          rowType: HomeRowType.libraryTilesSmall,
          isLoading: true,
        );
      case HomeSectionType.seerrRecentRequests:
        return HomeRow(
          id: 'seerr_recent_requests',
          title: l10n.recentRequests,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.seerrWatchlist:
        return HomeRow(
          id: 'seerr_watchlist',
          title: l10n.yourWatchlist,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.seerrRecentlyAdded:
        return HomeRow(
          id: 'seerr_recently_added',
          title: l10n.recentlyAdded,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.seerrPopularMovies:
        return HomeRow(
          id: 'seerr_popular_movies',
          title: l10n.popularMovies,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.seerrUpcomingMovies:
        return HomeRow(
          id: 'seerr_upcoming_movies',
          title: l10n.upcomingMovies,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.seerrPopularSeries:
        return HomeRow(
          id: 'seerr_popular_series',
          title: l10n.popularSeries,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.seerrUpcomingSeries:
        return HomeRow(
          id: 'seerr_upcoming_series',
          title: l10n.upcomingSeries,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.seerrMyRequests:
        return HomeRow(
          id: myRequestsRowId,
          title: l10n.myRequestsRow,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      // How many rows this brings, and their titles, depend on the history.
      case HomeSectionType.seerrBecause:
        return null;
      // These only show when they have something, so no empty shell first.
      case HomeSectionType.seerrSagas:
      case HomeSectionType.seerrGems:
      case HomeSectionType.seerrUpcoming:
      case HomeSectionType.familyNight:
        return null;
      case HomeSectionType.seerrForYou:
        return HomeRow(
          id: forYouRowId,
          title: l10n.seerrForYouRow,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.top10Movies:
        return HomeRow(
          id: top10MoviesRowId,
          title: l10n.top10MoviesRow,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.top10Series:
        return HomeRow(
          id: top10SeriesRowId,
          title: l10n.top10SeriesRow,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.frenchMovies:
        return HomeRow(
          id: frenchMoviesRowId,
          title: l10n.frenchMoviesRow,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.frenchSeries:
        return HomeRow(
          id: frenchSeriesRowId,
          title: l10n.frenchSeriesRow,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.frenchClassics:
        return HomeRow(
          id: frenchClassicsRowId,
          title: l10n.frenchClassicsRow,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.surprise:
        return HomeRow(
          id: surpriseRowId,
          title: l10n.surpriseRow,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.seerrShortcuts:
        return _seerrShortcutsRow(l10n);
      case HomeSectionType.seerrTrending:
        return HomeRow(
          id: 'seerr_trending',
          title: l10n.trending,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.seerrMovieGenres:
        return HomeRow(
          id: 'seerr_movie_genres',
          title: l10n.movieGenres,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.seerrStudios:
        return HomeRow(
          id: 'seerr_studios',
          title: l10n.studios,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.seerrSeriesGenres:
        return HomeRow(
          id: 'seerr_series_genres',
          title: l10n.seriesGenres,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.seerrNetworks:
        return HomeRow(
          id: 'seerr_networks',
          title: l10n.networks,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.radarrCalendar:
        return HomeRow(
          id: 'radarr_calendar',
          title: 'Upcoming Movies (Radarr)',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.sonarrCalendar:
        return HomeRow(
          id: 'sonarr_calendar',
          title: 'Upcoming TV Shows (Sonarr)',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.imdbTop250Movies:
        return HomeRow(
          id: 'imdb_top_250_movies',
          title: l10n.imdbTop250Movies,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.imdbTop250TvShows:
        return HomeRow(
          id: 'imdb_top_250_tv_shows',
          title: l10n.imdbTop250TvShows,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.imdbMostPopularMovies:
        return HomeRow(
          id: 'imdb_most_popular_movies',
          title: l10n.imdbMostPopularMovies,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.imdbMostPopularTvShows:
        return HomeRow(
          id: 'imdb_most_popular_tv_shows',
          title: l10n.imdbMostPopularTvShows,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.imdbLowestRatedMovies:
        return HomeRow(
          id: 'imdb_lowest_rated_movies',
          title: l10n.imdbLowestRatedMovies,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.imdbTopEnglishMovies:
        return HomeRow(
          id: 'imdb_top_english_movies',
          title: l10n.imdbTopEnglishMovies,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.tmdbPopularMovies:
        return HomeRow(
          id: 'tmdb_popular_movies',
          title: 'Popular Movies',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.tmdbTopRatedMovies:
        return HomeRow(
          id: 'tmdb_top_rated_movies',
          title: 'Top Rated Movies',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.tmdbNowPlayingMovies:
        return HomeRow(
          id: 'tmdb_now_playing_movies',
          title: 'Now Playing Movies',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.tmdbUpcomingMovies:
        return HomeRow(
          id: 'tmdb_upcoming_movies',
          title: 'Upcoming Movies',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.tmdbPopularTv:
        return HomeRow(
          id: 'tmdb_popular_tv',
          title: 'Popular TV',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.tmdbTopRatedTv:
        return HomeRow(
          id: 'tmdb_top_rated_tv',
          title: 'Top Rated TV',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.tmdbAiringTodayTv:
        return HomeRow(
          id: 'tmdb_airing_today_tv',
          title: 'Airing Today TV',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.tmdbOnTheAirTv:
        return HomeRow(
          id: 'tmdb_on_the_air_tv',
          title: 'On The Air TV',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.tmdbTrendingMovieDaily:
        return HomeRow(
          id: 'tmdb_trending_movie_daily',
          title: 'Trending Movies (Daily)',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.tmdbTrendingMovieWeekly:
        return HomeRow(
          id: 'tmdb_trending_movie_weekly',
          title: 'Trending Movies (Weekly)',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.tmdbTrendingTvDaily:
        return HomeRow(
          id: 'tmdb_trending_tv_daily',
          title: 'Trending TV (Daily)',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.tmdbTrendingTvWeekly:
        return HomeRow(
          id: 'tmdb_trending_tv_weekly',
          title: 'Trending TV (Weekly)',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.tmdbTrendingAllWeekly:
        return HomeRow(
          id: 'tmdb_trending_all_weekly',
          title: 'Trending All (Weekly)',
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.seasonal:
        return HomeRow(
          id: 'seasonal',
          title: l10n.seasonalRow,
          rowType: HomeRowType.pluginDynamic,
          isLoading: true,
        );
      case HomeSectionType.onNow:
        return HomeRow(
          id: 'onNow',
          title: l10n.onNow,
          rowType: HomeRowType.liveTvOnNow,
          isLoading: true,
        );
      case HomeSectionType.liveTv:
      case HomeSectionType.activeRecordings:
      case HomeSectionType.mediaBar:
      case HomeSectionType.recentlyReleased:
        return HomeRow(
          id: 'recentlyReleased',
          title: l10n.recentlyReleased,
          rowType: HomeRowType.recentlyReleased,
          isLoading: true,
        );
      case HomeSectionType.sinceYouWatched1:
      case HomeSectionType.sinceYouWatched2:
      case HomeSectionType.sinceYouWatched3:
      case HomeSectionType.sinceYouWatched4:
      case HomeSectionType.sinceYouWatched5:
        final index = section.sinceYouWatchedRow;
        return HomeRow(
          id: 'sinceYouWatched$index',
          title: 'Since you watched',
          rowType: HomeRowType.latestMedia,
          isLoading: true,
        );
      case HomeSectionType.rewatch:
        return HomeRow(
          id: 'rewatch',
          title: 'Rewatch',
          rowType: HomeRowType.latestMedia,
          isLoading: true,
        );
      case HomeSectionType.resumeBook:
      case HomeSectionType.none:
        return null;
    }
  }

  static FavoriteTypeFilter _favoriteFilterForSection(HomeSectionType type) {
    return switch (type) {
      HomeSectionType.favoriteMovies => FavoriteTypeFilter.movie,
      HomeSectionType.favoriteSeries => FavoriteTypeFilter.series,
      HomeSectionType.favoriteEpisodes => FavoriteTypeFilter.episode,
      HomeSectionType.favoritePeople => FavoriteTypeFilter.person,
      HomeSectionType.favoriteArtists => FavoriteTypeFilter.musicArtist,
      HomeSectionType.favoriteMusicVideos => FavoriteTypeFilter.musicVideo,
      HomeSectionType.favoriteAlbums => FavoriteTypeFilter.musicAlbum,
      HomeSectionType.favoriteSongs => FavoriteTypeFilter.audio,
      _ => FavoriteTypeFilter.all,
    };
  }

  static String _favoriteRowIdForSection(HomeSectionType type) {
    return switch (type) {
      HomeSectionType.favoriteMovies => 'favorites_movies',
      HomeSectionType.favoriteSeries => 'favorites_series',
      HomeSectionType.favoriteEpisodes => 'favorites_episodes',
      HomeSectionType.favoritePeople => 'favorites_people',
      HomeSectionType.favoriteArtists => 'favorites_artists',
      HomeSectionType.favoriteMusicVideos => 'favorites_musicvideos',
      HomeSectionType.favoriteAlbums => 'favorites_albums',
      HomeSectionType.favoriteSongs => 'favorites_songs',
      _ => 'favorites',
    };
  }

  static String _favoriteTitleForSection(
    HomeSectionType type,
    AppLocalizations l10n,
  ) {
    final filter = _favoriteFilterForSection(type);
    return 'Favorite ${filter.displayName}';
  }

  Future<void> _loadResumeAndNextUpInBackground() {
    if (_bgMergeInFlight) return Future<void>.value();
    _bgMergeInFlight = true;
    return () async {
      try {
        // Fetched side by side but tolerated separately. A server that is
        // slow to answer one of these must not take the other down with it,
        // which would leave the merged row empty and drop it from the home
        // screen.
        if (_multiServerEnabled) {
          final resumeFuture = _loadRowOrNull(
            'resume',
            () => _multiServerRepo.getAggregatedResume(),
          );
          final nextUpFuture = _loadRowOrNull(
            'next up',
            () => _multiServerRepo.getAggregatedNextUp(),
          );
          _applyMergedResumeRows(await resumeFuture, await nextUpFuture);
        } else {
          final resumeFuture = _loadRowOrNull(
            'resume',
            () => _dataSource.loadResume(_serverId),
          );
          final nextUpFuture = _loadRowOrNull(
            'next up',
            () => _dataSource.loadNextUp(_serverId),
          );
          _applyMergedResumeRows(await resumeFuture, await nextUpFuture);
        }
      } catch (e) {
        debugPrint('[Home] Merged resume and next up load failed: $e');
      } finally {
        _bgMergeInFlight = false;
      }
    }();
  }

  /// Newest first by when the user last played the item.
  static int _byLastPlayedDate(AggregatedItem a, AggregatedItem b) {
    final aDate = a.rawData['UserData']?['LastPlayedDate'] as String? ?? '';
    final bDate = b.rawData['UserData']?['LastPlayedDate'] as String? ?? '';
    return bDate.compareTo(aDate);
  }

  /// [existing] with the unseen items of [incoming] appended. The first id
  /// wins, so Continue Watching keeps an episode Next Up also offers.
  ///
  /// The row is never sorted as a whole. A Next Up episode carries the last
  /// played date of its series, so it would sort in among items the viewer
  /// has already scrolled past and slide the row under them.
  @visibleForTesting
  static List<AggregatedItem> appendNewArrivals(
    List<AggregatedItem> existing,
    List<AggregatedItem> incoming,
  ) {
    final seen = {for (final item in existing) item.id};
    final added = <AggregatedItem>[];
    for (final item in incoming) {
      if (seen.add(item.id)) added.add(item);
    }
    added.sort(_byLastPlayedDate);
    return [...existing, ...added];
  }

  /// Returns null rather than throwing, so a caller merging several sources
  /// can keep the ones that answered. The failure is logged because a merged
  /// row that quietly loses one of its sources looks the same as a server with
  /// nothing to offer, which makes the difference impossible to report.
  static Future<HomeRow?> _loadRowOrNull(
    String label,
    Future<HomeRow> Function() load,
  ) async {
    try {
      return await load();
    } catch (e) {
      debugPrint('[Home] Failed to load $label for the merged row: $e');
      return null;
    }
  }

  /// Merges a fresh first page of Continue Watching and Next Up into the
  /// resume row. Resume items win the dedupe.
  void _applyMergedResumeRows(HomeRow? resumeRow, HomeRow? nextUpRow) {
    if (resumeRow == null && nextUpRow == null) return;
    final merged = <String, AggregatedItem>{};
    for (final item in _prefs.filterContinueWatching(
      resumeRow?.items ?? const [],
    )) {
      merged[item.id] = item;
    }
    for (final item in _prefs.filterNextUp(nextUpRow?.items ?? const [])) {
      merged.putIfAbsent(item.id, () => item);
    }
    final sorted = merged.values.toList()..sort(_byLastPlayedDate);
    final existing = _rows.firstWhereOrNull((r) => r.id == 'resume');
    if (existing != null &&
        keepsPagedRow(
          pagedDuringLoad: _rowsPagedThisLoad.contains('resume'),
          existingItemCount: existing.items.length,
          freshItemCount: sorted.length,
        )) {
      return;
    }
    // Each source contributed its first page, and the merged item count can't
    // stand in for a per source offset, so the paging cursor starts at one
    // page no matter how many unique items the merge kept.
    _rowOffsets['resume'] = _rowPageSize;
    _applyMergedResumeResult(
      sorted,
      totalCount: (resumeRow?.totalCount ?? 0) + (nextUpRow?.totalCount ?? 0),
    );
  }

  void _applyMergedResumeResult(
    List<AggregatedItem> mergedItems, {
    int? totalCount,
  }) {
    final resumeIndex = _rows.indexWhere((r) => r.id == 'resume');
    if (resumeIndex < 0) return;
    _rows = List.of(_rows);
    if (mergedItems.isEmpty) {
      _emptySectionIds.add('resume');
      _rows.removeAt(resumeIndex);
    } else {
      _emptySectionIds.remove('resume');
      _rows[resumeIndex] = _rows[resumeIndex].copyWith(
        items: mergedItems,
        isLoading: false,
        totalCount: totalCount ?? _rows[resumeIndex].totalCount,
      );
    }
    notifyListeners();
    _saveRowCache();
    _watchNext.update(_rows);
    _tvChannels.update();
  }

  /// The merged row draws on two endpoints, so it pages both at the same offset
  /// and appends what comes back. Each source is walked in full and the dedupe
  /// only drops what is already on screen, so nothing gets skipped. The counts
  /// the two report overlap, so a page that adds nothing new closes the row.
  Future<void> _loadMoreMergedResume(int rowIndex) async {
    final row = _rows[rowIndex];
    final offset = _rowOffsets[row.id] ?? row.items.length;

    final resumeFuture = _loadRowOrNull(
      'resume',
      () => _dataSource.loadResume(_serverId, startIndex: offset),
    );
    final nextUpFuture = _loadRowOrNull(
      'next up',
      () => _dataSource.loadNextUp(_serverId, startIndex: offset),
    );
    final resumeRow = await resumeFuture;
    final nextUpRow = await nextUpFuture;
    if (resumeRow == null && nextUpRow == null) return;
    _rowOffsets[row.id] = offset + _rowPageSize;

    final appended = appendNewArrivals(row.items, [
      ..._prefs.filterContinueWatching(resumeRow?.items ?? const []),
      ..._prefs.filterNextUp(nextUpRow?.items ?? const []),
    ]);
    final addedNothing = appended.length == row.items.length;

    final items = _filterEmptyElements(appended);
    final index = _rows.indexWhere((r) => r.id == row.id);
    if (index < 0) return;
    _rows = List.of(_rows);
    _rows[index] = _rows[index].copyWith(
      items: items,
      totalCount: addedNothing ? items.length : null,
    );
    notifyListeners();
  }

  static const _seerrEnrichConcurrency = 5;
  static const _seerrRowIdPrefix = 'seerr_';

  /// Last page fetched per Seerr row. Seerr counts in pages where the rest of
  /// the home rows count in items, so this can't share `_rowOffsets`.
  final Map<String, int> _seerrRowPages = {};

  /// The live slider behind each Seerr slider row, kept for paging.
  final Map<String, SeerrDiscoverSlider> _seerrSliderRows = {};

  /// A row for a slider an admin set up on Seerr's discover page. One Seerr
  /// no longer has, or has switched off, is left off Home rather than shown
  /// empty.
  Future<List<HomeRow>> _loadSeerrSliderRow(HomeSectionConfig cfg) async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) return const [];

      final slider = findSeerrSliderFor(cfg, await repo.getDiscoverSliders());
      if (slider == null || !slider.isSupported) return const [];

      final page = await repo.getSliderPage(slider);
      final items = _seerrAggregatedItems(
        page.results,
        null,
        GetIt.instance<SeerrPreferences>().blockNsfw,
      );
      _seerrRowPages[cfg.stableId] = 1;
      _seerrSliderRows[cfg.stableId] = slider;
      return [
        _seerrRow(
          cfg.stableId,
          slider.title,
          items,
          totalCount: page.totalPages > 1 ? items.length + 1 : items.length,
        ),
      ];
    } catch (e) {
      debugPrint('[SeerrHomeRow] Failed to load Seerr slider row: $e');
      return const [];
    }
  }

  /// Appends the next page of a slider row, the way [_loadMoreSeerrRow] does
  /// for the built-in Seerr rows.
  Future<void> _loadMoreSeerrSliderRow(
    int rowIndex,
    SeerrDiscoverSlider slider,
  ) async {
    final row = _rows[rowIndex];
    final repo = await GetIt.instance.getAsync<SeerrRepository>();
    await repo.ensureInitialized();
    if (!repo.isAvailable) return;

    final nextPage = (_seerrRowPages[row.id] ?? 1) + 1;
    final page = await repo.getSliderPage(slider, page: nextPage);
    _seerrRowPages[row.id] = nextPage;
    _appendSeerrRowItems(
      row,
      page.results,
      null,
      exhausted: nextPage >= page.totalPages,
    );
  }

  Future<List<HomeRow>> _loadSeerrRow(
    SeerrRowType type,
    String title,
    String rowId,
  ) async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      final seerrPrefs = GetIt.instance<SeerrPreferences>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) {
        return [];
      }

      final blockNsfw = seerrPrefs.blockNsfw;
      final limit = seerrPrefs.fetchLimit.limit;

      List<SeerrDiscoverItem> rawItems = [];
      var hasMorePages = false;

      if (type == SeerrRowType.movieGenres) {
        final genres = await repo.getGenreSliderMovies();
        return [
          _seerrRow(rowId, title, [
            for (final g in genres)
              _seerrFilterItem(
                id: g.id.toString(),
                name: g.name,
                imagePath: seerrGenreBackdropUrl(g.id, g.backdrops) ?? '',
                type: 'Genre',
                mediaType: 'movie',
                filterType: 'genre',
              ),
          ]),
        ];
      } else if (type == SeerrRowType.seriesGenres) {
        final genres = await repo.getGenreSliderTv();
        return [
          _seerrRow(rowId, title, [
            for (final g in genres)
              _seerrFilterItem(
                id: g.id.toString(),
                name: g.name,
                imagePath: seerrGenreBackdropUrl(g.id, g.backdrops) ?? '',
                type: 'Genre',
                mediaType: 'tv',
                filterType: 'genre',
              ),
          ]),
        ];
      } else if (type == SeerrRowType.networks) {
        return [
          _seerrRow(rowId, title, [
            for (final n in SeerrDiscoverViewModel.popularNetworks)
              _seerrFilterItem(
                id: n.id.toString(),
                name: n.name,
                imagePath: n.logoPath ?? '',
                type: 'Network',
                mediaType: 'tv',
                filterType: 'network',
              ),
          ]),
        ];
      } else if (type == SeerrRowType.studios) {
        return [
          _seerrRow(rowId, title, [
            for (final s in SeerrDiscoverViewModel.popularStudios)
              _seerrFilterItem(
                id: s.id.toString(),
                name: s.name,
                imagePath: s.logoPath ?? '',
                type: 'Studio',
                mediaType: 'movie',
                filterType: 'studio',
              ),
          ]),
        ];
      } else if (type == SeerrRowType.recentRequests) {
        final user = await repo.getCurrentUser();
        final response = await repo.getRequests(
          requestedBy: user.canViewAllRequests ? null : user.id,
          limit: limit,
        );
        rawItems = await _enrichSeerrItems(
          repo,
          _seerrItemsFromRequests(response.results),
        );
        hasMorePages = (response.pageInfo?.pages ?? 1) > 1;
      } else if (type == SeerrRowType.recentlyAdded) {
        final media = await repo.getRecentlyAdded(limit: limit);
        final mapped = media
            .map(
              (m) => SeerrDiscoverItem(
                id: m.tmdbId ?? m.id,
                title: m.title,
                name: m.name,
                overview: m.overview,
                releaseDate: m.releaseDate,
                firstAirDate: m.firstAirDate,
                mediaType: m.mediaType,
                posterPath: m.posterPath,
                backdropPath: m.backdropPath,
                mediaInfo: SeerrMediaInfo(
                  id: m.id,
                  tmdbId: m.tmdbId,
                  status: m.status,
                ),
              ),
            )
            .toList();
        rawItems = await _enrichSeerrItems(repo, mapped);
      } else {
        final page = await _loadSeerrPage(repo, type, page: 1, limit: limit);
        if (page != null) {
          rawItems = type == SeerrRowType.yourWatchlist
              ? await _enrichSeerrItems(repo, page.results)
              : page.results;
          hasMorePages = page.totalPages > 1;
        }
      }

      final items = _seerrAggregatedItems(rawItems, type, blockNsfw);
      _seerrRowPages[rowId] = 1;

      // Paging keys off `hasMore`, so a row with further pages has to claim a
      // total above what it holds. The real total is no help because the
      // filtering above drops items the count still includes.
      return [
        _seerrRow(
          rowId,
          title,
          items,
          totalCount: hasMorePages ? items.length + 1 : items.length,
        ),
      ];
    } catch (e) {
      debugPrint('[SeerrHomeRow] Failed to load Seerr row $type: $e');
      return [];
    }
  }

  static const forYouRowId = 'seerr_for_you';

  /// Personal picks to request: what TMDB recommends next to the titles the
  /// viewer watched lately or favourited, minus what the server already has.
  Future<List<HomeRow>> _loadSeerrForYouRow(
    AppLocalizations l10n, {
    bool forceRefresh = false,
  }) async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) return [];
      final blockNsfw = GetIt.instance<SeerrPreferences>().blockNsfw;

      final taste = _taste();
      final picks = await ForYouService.instance.load(
        serverId: _serverId,
        loadHistory: () => _dataSource.loadTasteHistory(_serverId),
        fetchRecommendations: (seed) => seedRecommendations(repo, seed),
        loadExtras: () => _loadTasteExtras(repo, taste.profile),
        weigh: taste.weigh,
        hidden: {...taste.feedback.hiddenKeys, ...taste.profile.seenKeys},
        blockAdult: blockNsfw,
        forceRefresh: forceRefresh,
      );
      _maybePromptTaste(taste.profile);

      final items = <AggregatedItem>[];
      for (final pick in picks) {
        // Same card shape and NSFW filtering as the other Seerr rows.
        final base = _seerrAggregatedItems([pick.item], null, blockNsfw);
        if (base.isEmpty) continue;
        items.add(
          AggregatedItem(
            id: base.first.id,
            serverId: base.first.serverId,
            rawData: {
              ...base.first.rawData,
              'Type': pick.mediaType == 'tv' ? 'Series' : 'Movie',
              'SeerrMediaType': pick.mediaType,
              tasteGenreIdsKey: pick.item.genreIds,
              forYouFlag: true,
              forYouReasonKey: pick.because.title,
            },
          ),
        );
      }
      // No history yet, or nothing left to suggest: no row rather than an
      // empty one.
      if (items.isEmpty) return [];
      return [
        _seerrRow(forYouRowId, l10n.seerrForYouRow, items,
            totalCount: items.length),
      ];
    } catch (e) {
      debugPrint('[SeerrHomeRow] Failed to load For You row: $e');
      return [];
    }
  }

  static const top10MoviesRowId = 'top10_movies';

  /// The card that switches the Top 10 between films and series.
  static const top10SwitchFlag = 'Top10Switch';

  bool _top10Switches = false;
  bool _top10ShowsSeries = false;

  /// Whether the films' Top 10 can switch to series, and is showing them.
  bool get top10Switches => _top10Switches;
  bool get top10ShowsSeries => _top10ShowsSeries;

  /// VJOD puts the switch in the row's head instead of a first card.
  static bool get _switchInHeader =>
      ThemeRegistry.active.id == ThemeRegistry.vjodId ||
      ThemeRegistry.active.id == ThemeRegistry.ecrinId;

  /// Shows the Top 10 of the other kind in the films' row.
  Future<void> toggleTop10() async {
    _top10ShowsSeries = !_top10ShowsSeries;
    final l10n = currentAppLocalizations();
    final rows = await _loadTop10Row(l10n, 'movie');
    if (rows.isNotEmpty) _replaceRowById(rows.single);
  }
  static const top10SeriesRowId = 'top10_series';
  static const surpriseRowId = 'surprise';

  /// Marks a Surprise card, so a tap starts playback instead of the page.
  static const surpriseFlag = 'MoonfinSurprise';

  /// Whether [row] is a Top 10, drawn with its rank on each card.
  static bool isTop10Row(HomeRow row) =>
      row.id == top10MoviesRowId || row.id == top10SeriesRowId;

  /// Votes a title needs before its rating can top the year's chart, so a
  /// film rated 9 by a dozen people stays out of it.
  static const _yearChartMinVotes = {'movie': 300, 'tv': 150};

  /// The Top 10 films or series ([mediaType] `movie` or `tv`), whatever the
  /// server holds: a title still to request opens the request sheet like the
  /// other suggestions.
  Future<List<HomeRow>> _loadTop10Row(
    AppLocalizations l10n,
    String section, {
    bool forceRefresh = false,
  }) async {
    // The films' row takes the series' place when they share it.
    final switches = _top10Switches && section == 'movie';
    final mediaType = switches && _top10ShowsSeries ? 'tv' : section;
    final isTv = mediaType == 'tv';
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) return [];
      final prefs = GetIt.instance<SeerrPreferences>();
      final chart = await _top10Chart(
        repo,
        mediaType,
        yearBest: prefs.top10YearBest,
        forceRefresh: forceRefresh,
      );
      final items = [
        for (final pick in chart)
          ?_suggestionCard(pick, mediaType, blockNsfw: prefs.blockNsfw),
      ].take(10).toList();
      // A Top 3 isn't much of a chart.
      if (items.length < 3) return [];
      if (switches && !_switchInHeader) {
        items.insert(
          0,
          AggregatedItem(
            id: top10SwitchFlag,
            serverId: 'seerr',
            rawData: {
              'Name': isTv ? l10n.top10SwitchToMovies : l10n.top10SwitchToSeries,
              'Type': 'Genre',
              top10SwitchFlag: true,
            },
          ),
        );
      }
      return [
        HomeRow(
          id: section == 'tv' ? top10SeriesRowId : top10MoviesRowId,
          title: switches
              ? l10n.top10Row
              : (isTv ? l10n.top10SeriesRow : l10n.top10MoviesRow),
          rowType: HomeRowType.pluginDynamic,
          items: items,
          totalCount: items.length,
        ),
      ];
    } catch (e) {
      debugPrint('[Top10] Failed to load the Top 10 $mediaType row: $e');
      return [];
    }
  }

  /// Charts move by the day at most, and one costs a call per source, so it
  /// is kept a few hours.
  static const _chartLifetime = Duration(hours: 3);
  final Map<String, ({DateTime at, List<SeerrDiscoverItem> chart})>
  _chartCache = {};

  /// The titles of a Top 10 in order, longer than ten so the adult filter
  /// can take some out.
  ///
  /// By default, what is popular right now: the charts of every streaming
  /// service in the viewer's country, the week's trends on TMDB and what
  /// the members of Trakt and BetaSeries watch most, fused so a title on
  /// several of them ranks higher and shows once, minus what is popular but
  /// poorly rated. A source that fails is left out. With [yearBest], the best
  /// rated releases of the last twelve months instead. Either way, a film
  /// still only in cinemas makes way.
  Future<List<SeerrDiscoverItem>> _top10Chart(
    SeerrRepository repo,
    String mediaType, {
    required bool yearBest,
    required bool forceRefresh,
  }) async {
    final isTv = mediaType == 'tv';
    final region = PlatformDispatcher.instance.locale.countryCode ?? 'FR';
    final key = '$mediaType|$yearBest|$region';
    final cached = _chartCache[key];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.at) < _chartLifetime) {
      return cached.chart;
    }

    List<SeerrDiscoverItem> chart;
    if (yearBest) {
      final window = yearChartWindow(DateTime.now());
      final results = await _chartPage(
        () => isTv
            ? repo.discoverTv(
                sortBy: 'vote_average.desc',
                voteCountGte: _yearChartMinVotes['tv'],
                firstAirDateGte: window.from,
                firstAirDateLte: window.to,
              )
            : repo.discoverMovies(
                sortBy: 'vote_average.desc',
                voteCountGte: _yearChartMinVotes['movie'],
                primaryReleaseDateGte: window.from,
                primaryReleaseDateLte: window.to,
              ),
      );
      chart = chartPicks(results, limit: results.length);
    } else {
      // Charts that only name TMDB ids, to turn into cards below.
      final idCharts = Future.wait([
        for (final traktChart in TraktChart.values)
          _chartSource(
            () => GetIt.instance<TraktClient>().chart(traktChart, mediaType),
          ),
        _chartSource(
          () => isTv
              ? GetIt.instance<BetaSeriesClient>().showChart(country: region)
              : GetIt.instance<BetaSeriesClient>().movieChart(),
        ),
      ]);
      final charts = await Future.wait([
        _chartPage(
          () => isTv
              ? repo.getTrendingTv(limit: 20)
              : repo.getTrendingMovies(limit: 20),
        ),
        for (final provider in chartStreamingServices)
          _chartPage(
            () => repo.discoverOnStreamingService(
              mediaType: mediaType,
              region: region,
              providerId: provider,
            ),
          ),
      ]);
      // A title those rank that no other chart shows has no card yet.
      final known = {
        for (final c in charts)
          for (final item in c) item.id: item,
      };
      final idCards = await Future.wait([
        for (final ids in await idCharts)
          chartCards(
            ids,
            known: known,
            fetch: (tmdbId) => repo.getDiscoverItem(mediaType, tmdbId),
          ),
      ]);
      chart = [
        for (final item in fuseCharts([
          for (final c in [...charts, ...idCards]) chartPicks(c, limit: 20),
        ]))
          if (isWellRated(item)) item,
      ];
    }
    if (!isTv) chart = await _outAtHome(repo, chart);
    // Nothing came back: no row, and the next load asks again.
    if (chart.isNotEmpty) {
      _chartCache[key] = (at: DateTime.now(), chart: chart);
    }
    return chart;
  }

  /// What [fetch] brings, or nothing when it fails, so one source can't sink
  /// a row.
  static Future<List<T>> _chartSource<T>(
    Future<List<T>> Function() fetch,
  ) async {
    try {
      return await fetch();
    } catch (e) {
      debugPrint('[Charts] A source failed: $e');
      return const [];
    }
  }

  static Future<List<SeerrDiscoverItem>> _chartPage(
    Future<SeerrDiscoverPage> Function() fetch,
  ) => _chartSource(() async => (await fetch()).results);

  /// How far down a film chart the release dates are checked: enough for a
  /// Top 10 once the films still in cinemas are out.
  static const _homeCheckDepth = 16;

  /// The films of [chart] that can be watched at home, among the first
  /// [depth]: one still only in cinemas can't be had yet. A film the library
  /// holds stays, and so does one whose dates can't be read.
  Future<List<SeerrDiscoverItem>> _outAtHome(
    SeerrRepository repo,
    List<SeerrDiscoverItem> chart, {
    int depth = _homeCheckDepth,
  }) async {
    final now = DateTime.now();
    final head = chart.take(depth).toList();
    // A few at a time, so the server isn't flooded.
    final keep = await mapBounded<SeerrDiscoverItem, bool>(
      head,
      4,
      (film) => SeerrMediaStatus.isAvailable(film.mediaInfo?.status)
          ? Future.value(true)
          : repo
                .getMovieReleases(film.id)
                .then(
                  (releases) => isOutAtHome(releases, now),
                  onError: (Object e) => true,
                ),
    );
    return [
      for (final (i, film) in head.indexed)
        if (keep[i] ?? true) film,
    ];
  }

  static const frenchMoviesRowId = 'french_movies';
  static const frenchSeriesRowId = 'french_series';
  static const frenchClassicsRowId = 'french_classics';

  /// A French row ([section] is one of the French sections), whatever the
  /// server holds; a title still to request opens the request sheet.
  Future<List<HomeRow>> _loadFrenchRow(
    AppLocalizations l10n,
    HomeSectionType section, {
    bool forceRefresh = false,
  }) async {
    final (id, title, mediaType) = switch (section) {
      HomeSectionType.frenchSeries => (
        frenchSeriesRowId,
        l10n.frenchSeriesRow,
        'tv',
      ),
      HomeSectionType.frenchClassics => (
        frenchClassicsRowId,
        l10n.frenchClassicsRow,
        'movie',
      ),
      _ => (frenchMoviesRowId, l10n.frenchMoviesRow, 'movie'),
    };
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) return [];
      final prefs = GetIt.instance<SeerrPreferences>();
      final cached = _chartCache[id];
      final List<SeerrDiscoverItem> picks;
      if (!forceRefresh &&
          cached != null &&
          DateTime.now().difference(cached.at) < _chartLifetime) {
        picks = cached.chart;
      } else {
        picks = switch (section) {
          HomeSectionType.frenchSeries => await _frenchSeries(repo),
          HomeSectionType.frenchClassics => await _frenchClassics(repo),
          _ => await _frenchMovies(repo),
        };
        if (picks.isNotEmpty) {
          _chartCache[id] = (at: DateTime.now(), chart: picks);
        }
      }
      final items = [
        for (final pick in picks)
          ?_suggestionCard(pick, mediaType, blockNsfw: prefs.blockNsfw),
      ].take(20).toList();
      // A handful isn't worth a row.
      if (items.length < 5) return [];
      return [
        HomeRow(
          id: id,
          title: title,
          rowType: HomeRowType.pluginDynamic,
          items: items,
          totalCount: items.length,
        ),
      ];
    } catch (e) {
      debugPrint('[French] Failed to load the $id row: $e');
      return [];
    }
  }

  /// The best rated French titles (TMDB counts a title as French by its
  /// original language) between [from] and [to], among those enough people
  /// rated. Either end may stay open.
  static Future<List<SeerrDiscoverItem>> _frenchAcclaimed(
    SeerrRepository repo,
    String mediaType, {
    DateTime? from,
    DateTime? to,
    required int minVotes,
  }) => _chartPage(
    () => mediaType == 'tv'
        ? repo.discoverTv(
            language: 'fr',
            sortBy: 'vote_average.desc',
            voteCountGte: minVotes,
            firstAirDateGte: from == null ? null : tmdbDay(from),
            firstAirDateLte: to == null ? null : tmdbDay(to),
          )
        : repo.discoverMovies(
            language: 'fr',
            sortBy: 'vote_average.desc',
            voteCountGte: minVotes,
            primaryReleaseDateGte: from == null ? null : tmdbDay(from),
            primaryReleaseDateLte: to == null ? null : tmdbDay(to),
          ),
  );

  /// French cinema now: the hits of the last eighteen months, those France
  /// went to see most in cinemas this decade first, then the award winners
  /// and the best rated of the last five years, taking turns, then only what
  /// can be watched at home.
  ///
  /// This decade's hits are the admissions recorded in the app, taking turns
  /// with the French films TMDB ranks highest at the box office since the
  /// decade began, so a new hit shows up on its own.
  Future<List<SeerrDiscoverItem>> _frenchMovies(SeerrRepository repo) async {
    final now = DateTime.now();
    final decade = decadeOf(now);
    final winners = _chartSource(
      () => GetIt.instance<FilmAwardsClient>().frenchWinners(),
    );
    final (boxOffice, recent, acclaimed) = await (
      _chartPage(
        () => repo.discoverMovies(
          language: 'fr',
          sortBy: 'revenue.desc',
          primaryReleaseDateGte: tmdbDay(DateTime(decade)),
          primaryReleaseDateLte: tmdbDay(now),
        ),
      ),
      _chartPage(
        () => repo.discoverMovies(
          language: 'fr',
          primaryReleaseDateGte: tmdbDay(
            DateTime(now.year, now.month - 18, now.day),
          ),
          primaryReleaseDateLte: tmdbDay(now),
        ),
      ),
      _frenchAcclaimed(
        repo,
        'movie',
        from: DateTime(now.year - 5, now.month, now.day),
        minVotes: 300,
      ),
    ).wait;
    final known = {
      for (final film in [...boxOffice, ...recent, ...acclaimed]) film.id: film,
    };
    Future<SeerrDiscoverItem> fetch(int tmdbId) =>
        repo.getDiscoverItem('movie', tmdbId);
    final (recorded, awarded) = await (
      chartCards(
        frenchHitsByDecade[decade] ?? const [],
        known: known,
        fetch: fetch,
      ),
      winners.then((ids) => chartCards(ids, known: known, fetch: fetch)),
    ).wait;
    final hits = takeTurns([
      recorded,
      chartPicks(boxOffice, limit: 10),
    ], keyOf: tmdbKey);
    return _outAtHome(
      repo,
      takeTurns([
        takeTurns([hits, _worthShowing(recent)], keyOf: tmdbKey),
        awarded,
        chartPicks(acclaimed, limit: 20),
      ], keyOf: tmdbKey),
      depth: 20,
    );
  }

  /// French series: what France watched most this week on BetaSeries, the
  /// popular of the last three years and the best rated of the last ten,
  /// taking turns.
  Future<List<SeerrDiscoverItem>> _frenchSeries(SeerrRepository repo) async {
    final now = DateTime.now();
    final watched = _chartSource(
      () => GetIt.instance<BetaSeriesClient>().frenchShowChart(),
    );
    final (popular, acclaimed) = await (
      _chartPage(
        () => repo.discoverTv(
          language: 'fr',
          firstAirDateGte: tmdbDay(DateTime(now.year - 3, now.month, now.day)),
        ),
      ),
      _frenchAcclaimed(
        repo,
        'tv',
        from: DateTime(now.year - 10, now.month, now.day),
        minVotes: 100,
      ),
    ).wait;
    final watchedCards = await chartCards(
      await watched,
      known: {
        for (final show in [...popular, ...acclaimed]) show.id: show,
      },
      fetch: (tmdbId) => repo.getDiscoverItem('tv', tmdbId),
    );
    return takeTurns([
      watchedCards,
      _worthShowing(popular),
      chartPicks(acclaimed, limit: 20),
    ], keyOf: tmdbKey);
  }

  /// The classics of French cinema: the films France went to see most of
  /// all time and in the decades before this one, the latest first, taking
  /// turns with the best rated French films of all time. All long out, so no
  /// release check.
  Future<List<SeerrDiscoverItem>> _frenchClassics(SeerrRepository repo) async {
    final decade = decadeOf(DateTime.now());
    final pastDecades =
        frenchHitsByDecade.keys.where((d) => d < decade).toList()
          ..sort((a, b) => b.compareTo(a));
    final acclaimed = await _frenchAcclaimed(repo, 'movie', minVotes: 1000);
    final hits = await chartCards(
      takeTurns([
        frenchHitsAllTime,
        for (final past in pastDecades) frenchHitsByDecade[past]!,
      ]),
      known: {for (final film in acclaimed) film.id: film},
      fetch: (tmdbId) => repo.getDiscoverItem('movie', tmdbId),
      depth: 20,
    );
    return takeTurns([hits, chartPicks(acclaimed, limit: 20)], keyOf: tmdbKey);
  }

  /// The titles of a popularity list fit to show: with a poster, each once,
  /// and not popular for the wrong reasons.
  static List<SeerrDiscoverItem> _worthShowing(List<SeerrDiscoverItem> list) =>
      [
        for (final item in chartPicks(list, limit: 20))
          if (isWellRated(item)) item,
      ];

  /// A movie and a series to start without choosing, drawn fresh on each
  /// load, the way Netflix's Play Something works.
  Future<List<HomeRow>> _loadSurpriseRow(AppLocalizations l10n) async {
    try {
      final picks = await _dataSource.loadSurprisePicks(_serverId);
      if (picks.isEmpty) return [];
      final items = [
        for (final pick in picks)
          AggregatedItem(
            id: pick.id,
            serverId: pick.serverId,
            rawData: {...pick.rawData, surpriseFlag: true},
          ),
      ];
      return [
        HomeRow(
          id: surpriseRowId,
          title: l10n.surpriseRow,
          rowType: HomeRowType.pluginDynamic,
          items: items,
          totalCount: items.length,
        ),
      ];
    } catch (e) {
      debugPrint('[Surprise] Failed to load the Surprise row: $e');
      return [];
    }
  }

  /// Marks a For You card, so a tap offers the request instead of the page.
  static const forYouFlag = 'SeerrForYou';

  /// The title that earned a For You card its place.
  static const forYouReasonKey = 'SeerrForYouBecause';

  static const myRequestsRowId = 'seerr_my_requests';
  static const becauseRowIdPrefix = 'seerr_because_';

  /// Where a My Requests card stands, a [MyRequestState] name.
  static const myRequestStateKey = 'MoonfinRequestState';

  /// How far a My Requests download got, from 0 to 1.
  static const myRequestProgressKey = 'MoonfinRequestProgress';

  /// Told the titles of requests that came through since the last look, so
  /// the screen can announce them. Set by the home screen.
  void Function(List<String> titles)? onRequestsReady;

  /// The viewer's own requests, what can be watched first, then what is
  /// downloading or waiting, with how far each one got.
  Future<List<HomeRow>> _loadMyRequestsRow(AppLocalizations l10n) async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) return [];
      final seerrPrefs = GetIt.instance<SeerrPreferences>();

      final user = await repo.getCurrentUser();
      final response = await repo.getRequests(
        requestedBy: user.id,
        sort: 'modified',
        limit: 50,
      );
      final now = DateTime.now();
      var entries = myRequestEntries(response.results, now: now);
      // Seerr can lag behind the library: a title already in it is ready.
      final candidates = [
        for (final e in libraryCandidates(entries))
          if (e.media.tmdbId != null) e,
      ];
      if (candidates.isNotEmpty) {
        final inLibrary = await _dataSource.loadLibraryTmdbKeys(_serverId, [
          for (final e in candidates)
            (
              mediaType: e.request.type == 'tv' ? 'tv' : 'movie',
              tmdbId: e.media.tmdbId!,
            ),
        ]);
        entries = promoteInLibrary(entries, inLibrary, now: now);
      }

      final ready = newlyReady(entries, seerrPrefs.announcedReadyRequests);
      final announced = {
        ...?seerrPrefs.announcedReadyRequests,
        for (final e in entries)
          if (e.state == MyRequestState.ready) e.readyKey,
      };
      // Old keys add up: keep only the latest few hundred.
      final keep = announced.length > 300
          ? announced.skip(announced.length - 300).toList()
          : announced.toList();
      await seerrPrefs.setAnnouncedReadyRequests(keep);

      if (entries.isEmpty) return [];
      final enriched = await _enrichSeerrItems(
        repo,
        _seerrItemsFromRequests([for (final e in entries) e.request]),
      );
      final byKey = {
        for (final e in entries) e.key: e,
      };
      final items = <AggregatedItem>[];
      for (final raw in enriched) {
        final entry = byKey['${raw.mediaType}:${raw.id}'];
        if (entry == null) continue;
        final base = _seerrAggregatedItems(
          [raw],
          SeerrRowType.recentRequests,
          seerrPrefs.blockNsfw,
        );
        if (base.isEmpty) continue;
        items.add(
          AggregatedItem(
            id: base.first.id,
            serverId: base.first.serverId,
            rawData: {
              ...base.first.rawData,
              myRequestStateKey: entry.state.name,
              myRequestProgressKey: ?entry.progress,
            },
          ),
        );
      }

      if (ready.isNotEmpty) {
        onRequestsReady?.call([
          for (final e in ready)
            e.media.title ?? e.media.name ?? '',
        ]..removeWhere((t) => t.isEmpty));
      }
      if (items.isEmpty) return [];
      return [
        _seerrRow(myRequestsRowId, l10n.myRequestsRow, items,
            totalCount: items.length),
      ];
    } catch (e) {
      debugPrint('[SeerrHomeRow] Failed to load My Requests row: $e');
      return [];
    }
  }

  /// "Because you watched X" rows, one per title the viewer cares about
  /// most, from the same Seerr calls as the For You row.
  Future<List<HomeRow>> _loadBecauseRows(
    AppLocalizations l10n, {
    bool forceRefresh = false,
  }) async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) return [];
      final blockNsfw = GetIt.instance<SeerrPreferences>().blockNsfw;

      final taste = _taste();
      final rows = await ForYouService.instance.loadBecauseRows(
        serverId: _serverId,
        loadHistory: () => _dataSource.loadTasteHistory(_serverId),
        fetchRecommendations: (seed) => seedRecommendations(repo, seed),
        loadExtras: () => _loadTasteExtras(repo, taste.profile),
        weigh: taste.weigh,
        hidden: {...taste.feedback.hiddenKeys, ...taste.profile.seenKeys},
        blockAdult: blockNsfw,
        forceRefresh: forceRefresh,
      );

      final result = <HomeRow>[];
      for (final row in rows) {
        final items = <AggregatedItem>[];
        for (final entry in row.items) {
          final card = _suggestionCard(
            entry.item,
            entry.mediaType,
            reason: row.seed.title,
            blockNsfw: blockNsfw,
          );
          if (card != null) items.add(card);
        }
        if (items.length < 5) continue;
        result.add(
          _seerrRow(
            '$becauseRowIdPrefix${row.seed.mediaType}_${row.seed.tmdbId}',
            row.seed.source == TasteSource.watched
                ? l10n.becauseYouWatched(row.seed.title)
                : l10n.becauseYouLike(row.seed.title),
            items,
            totalCount: items.length,
          ),
        );
      }
      return result;
    } catch (e) {
      debugPrint('[SeerrHomeRow] Failed to load Because rows: $e');
      return [];
    }
  }

  static const sagaRowId = 'seerr_sagas';
  static const gemsRowId = 'seerr_gems';
  static const upcomingRowId = 'seerr_upcoming';
  static const familyRowId = 'family_night';

  /// A Seerr suggestion as a card. Something to ask for opens the request
  /// sheet, under [reason] when there is one; what the library holds or
  /// already awaits opens its page.
  AggregatedItem? _suggestionCard(
    SeerrDiscoverItem item,
    String mediaType, {
    String? reason,
    required bool blockNsfw,
  }) {
    // Kept like the request rows, so what the library holds stays.
    final base = _seerrAggregatedItems(
      [item],
      SeerrRowType.recentRequests,
      blockNsfw,
    );
    if (base.isEmpty) return null;
    final requestable = _isRequestable(item.mediaInfo?.status);
    return AggregatedItem(
      id: base.first.id,
      serverId: base.first.serverId,
      rawData: {
        ...base.first.rawData,
        'Type': mediaType == 'tv' ? 'Series' : 'Movie',
        'SeerrMediaType': mediaType,
        tasteGenreIdsKey: item.genreIds,
        if (requestable) forYouFlag: true,
        if (requestable && reason != null) forYouReasonKey: reason,
      },
    );
  }

  /// The next film of each saga the viewer is part way through, whether the
  /// library has it or it is one request away.
  Future<List<HomeRow>> _loadSagaRow(
    AppLocalizations l10n, {
    bool forceRefresh = false,
  }) async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) return [];
      final prefs = GetIt.instance<SeerrPreferences>();
      final blockNsfw = prefs.blockNsfw;
      final feedback = TasteFeedback.decode(prefs.tasteFeedbackJson);

      final picks = await SagaService.instance.load(
        serverId: _serverId,
        loadWatched: () async {
          final history = await _dataSource.loadTasteHistory(_serverId);
          return [
            for (final item in history.recent)
              if (item.type == 'Movie')
                if (int.tryParse(item.tmdbId ?? '') case final id?
                    when id > 0)
                  (tmdbId: id, title: item.name),
          ];
        },
        collectionOf: (tmdbId) async =>
            (await repo.getMovieDetails(tmdbId)).collection?.id,
        fetchCollection: repo.getCollectionDetails,
        exclude: feedback.hiddenKeys,
        blockAdult: blockNsfw,
        forceRefresh: forceRefresh,
      );

      final items = [
        for (final pick in picks)
          if (_suggestionCard(
                pick.item,
                'movie',
                reason: pick.afterTitle,
                blockNsfw: blockNsfw,
              )
              case final card?)
            card,
      ];
      if (items.isEmpty) return [];
      return [
        _seerrRow(sagaRowId, l10n.sagaRow, items, totalCount: items.length),
      ];
    } catch (e) {
      debugPrint('[SeerrHomeRow] Failed to load Saga row: $e');
      return [];
    }
  }

  /// Well-loved titles few people know, close to what the viewer likes.
  Future<List<HomeRow>> _loadGemsRow(
    AppLocalizations l10n, {
    bool forceRefresh = false,
  }) async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) return [];
      final blockNsfw = GetIt.instance<SeerrPreferences>().blockNsfw;
      final taste = _taste();

      final picks = await ForYouService.instance.loadGems(
        serverId: _serverId,
        loadHistory: () => _dataSource.loadTasteHistory(_serverId),
        fetchRecommendations: (seed) => seedRecommendations(repo, seed),
        loadExtras: () => _loadTasteExtras(repo, taste.profile),
        weigh: taste.weigh,
        hidden: {...taste.feedback.hiddenKeys, ...taste.profile.seenKeys},
        blockAdult: blockNsfw,
        forceRefresh: forceRefresh,
      );

      final items = [
        for (final pick in picks)
          if (_suggestionCard(
                pick.item,
                pick.mediaType,
                reason: pick.because.title,
                blockNsfw: blockNsfw,
              )
              case final card?)
            card,
      ];
      if (items.length < 5) return [];
      return [
        _seerrRow(gemsRowId, l10n.gemsRow, items, totalCount: items.length),
      ];
    } catch (e) {
      debugPrint('[SeerrHomeRow] Failed to load Gems row: $e');
      return [];
    }
  }

  /// What comes out in the year ahead that the viewer would want, to
  /// request before it is out.
  Future<List<HomeRow>> _loadUpcomingRow(
    AppLocalizations l10n, {
    bool forceRefresh = false,
  }) async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) return [];
      final blockNsfw = GetIt.instance<SeerrPreferences>().blockNsfw;
      final taste = _taste();

      Future<List<(SeerrDiscoverItem, String)>> listed(
        Future<SeerrDiscoverPage> Function({int page}) fetch,
        String mediaType,
      ) async {
        try {
          final pages = await Future.wait([fetch(page: 1), fetch(page: 2)]);
          return [
            for (final page in pages)
              for (final item in page.results) (item, mediaType),
          ];
        } catch (e) {
          debugPrint('[SeerrHomeRow] Upcoming $mediaType failed: $e');
          return const [];
        }
      }

      final (raw, movies, series) = await (
        ForYouService.instance.loadRaw(
          serverId: _serverId,
          loadHistory: () => _dataSource.loadTasteHistory(_serverId),
          fetchRecommendations: (seed) => seedRecommendations(repo, seed),
          loadExtras: () => _loadTasteExtras(repo, taste.profile),
          forceRefresh: forceRefresh,
        ),
        listed(repo.getUpcomingMovies, 'movie'),
        listed(repo.getUpcomingTv, 'tv'),
      ).wait;

      final picks = UpcomingPicks.rank(
        seeds: raw.seeds,
        recommendationsBySeed: raw.recommendations,
        upcoming: takeTurns([movies, series]),
        excludeKeys: {...raw.exclude, ...taste.feedback.hiddenKeys},
        blockAdult: blockNsfw,
        weigh: taste.weigh,
      );
      final items = [
        for (final pick in picks)
          if (_suggestionCard(
                pick.item,
                pick.mediaType,
                reason: switch (pick.because?.title) {
                  final title? when title.isNotEmpty => title,
                  _ => null,
                },
                blockNsfw: blockNsfw,
              )
              case final card?)
            card,
      ];
      if (items.length < 5) return [];
      return [
        _seerrRow(
          upcomingRowId,
          l10n.upcomingRow,
          items,
          totalCount: items.length,
        ),
      ];
    } catch (e) {
      debugPrint('[SeerrHomeRow] Failed to load Upcoming row: $e');
      return [];
    }
  }

  /// Unwatched family films from the library, best rated first.
  Future<List<HomeRow>> _loadFamilyRow(AppLocalizations l10n) async {
    try {
      final items = await _dataSource.loadFamilyNight(_serverId);
      if (items.length < 4) return [];
      return [
        HomeRow(
          id: familyRowId,
          title: l10n.familyNightRow,
          rowType: HomeRowType.pluginDynamic,
          items: items,
          totalCount: items.length,
        ),
      ];
    } catch (e) {
      debugPrint('[FamilyNight] Failed to load the Family night row: $e');
      return [];
    }
  }

  /// The TMDB genre ids a suggestion card carries, for "Not interested".
  static const tasteGenreIdsKey = 'SeerrGenreIds';

  /// Asks the screen to show the taste questionnaire. [firstTime] opens it
  /// outright; otherwise it is a gentle reminder the viewer can ignore.
  void Function({required bool firstTime})? onTastePrompt;

  bool _tastePromptChecked = false;

  /// How often the taste reminder may come back.
  static const tasteReminderInterval = Duration(days: 30);

  ({TasteProfile profile, TasteFeedback feedback, TasteWeigher weigh})
  _taste() {
    final prefs = GetIt.instance<SeerrPreferences>();
    final profile = TasteProfile.decode(prefs.tasteProfileJson);
    final feedback = TasteFeedback.decode(prefs.tasteFeedbackJson);
    return (
      profile: profile,
      feedback: feedback,
      weigh: (item, mediaType) =>
          tasteFactor(item, mediaType, profile, feedback),
    );
  }

  Future<TasteExtras> _loadTasteExtras(
    SeerrRepository repo,
    TasteProfile profile,
  ) => loadTasteExtras(repo, profile);

  /// Opens the questionnaire the first time Seerr suggestions show, then
  /// reminds about it now and then, never more than once per session.
  void _maybePromptTaste(TasteProfile profile) {
    if (_tastePromptChecked || onTastePrompt == null) return;
    _tastePromptChecked = true;
    final prefs = GetIt.instance<SeerrPreferences>();
    final now = DateTime.now();
    final promptedMs = prefs.tastePromptedAt;
    final prompted = promptedMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(promptedMs);

    final bool firstTime;
    if (prompted == null) {
      firstTime = !profile.answered;
      if (profile.answered) return;
    } else {
      if (now.difference(prompted) < tasteReminderInterval) return;
      final updated = profile.updatedAt;
      if (updated != null && now.difference(updated) < tasteReminderInterval) {
        return;
      }
      firstTime = false;
    }
    unawaited(prefs.setTastePromptedAt(now.millisecondsSinceEpoch));
    onTastePrompt?.call(firstTime: firstTime);
  }

  /// Rebuilds the suggestion rows after the taste answers changed.
  Future<void> refreshAfterTasteChange() async {
    ForYouService.instance.clearCache();
    await load(preserveExisting: true);
  }

  /// Hides a suggestion for good and makes titles of its genres rarer.
  Future<void> markNotInterested(AggregatedItem item) async {
    final mediaType = item.rawData['SeerrMediaType'] as String? ??
        (item.type == 'Series' ? 'tv' : 'movie');
    final tmdbId = int.tryParse(item.id);
    if (tmdbId == null) return;
    final ids = [
      for (final id in (item.rawData[tasteGenreIdsKey] as List?) ?? const [])
        if (id is int) id,
    ];
    final prefs = GetIt.instance<SeerrPreferences>();
    final feedback = TasteFeedback.decode(prefs.tasteFeedbackJson)
        .notInterested(
          forYouKey(mediaType, tmdbId),
          TasteGenre.of(ids, mediaType),
        );
    await prefs.setTasteFeedbackJson(feedback.encode());

    for (final row in _rows.toList()) {
      if (row.id != forYouRowId &&
          row.id != sagaRowId &&
          row.id != gemsRowId &&
          row.id != upcomingRowId &&
          !row.id.startsWith(becauseRowIdPrefix)) {
        continue;
      }
      if (!row.items.any((i) => i.id == item.id)) continue;
      final items = row.items.where((i) => i.id != item.id).toList();
      _replaceRowById(row.copyWith(items: items, totalCount: items.length));
    }
  }

  /// Takes a requested title out of the For You row right away.
  void removeFromForYouRow(AggregatedItem item) {
    final mediaType = item.rawData['SeerrMediaType'] as String? ?? 'movie';
    final tmdbId = int.tryParse(item.id);
    if (tmdbId != null) {
      ForYouService.instance.markRequested(mediaType, tmdbId);
    }
    final index = _rows.indexWhere((r) => r.id == forYouRowId);
    if (index >= 0) {
      final row = _rows[index];
      final items = row.items.where((i) => i.id != item.id).toList();
      _replaceRowById(row.copyWith(items: items, totalCount: items.length));
    }
    // A Because row keeps the card, now marked as requested, since its row
    // is about one title rather than a list of things to ask for.
    for (final row in _rows.toList()) {
      if (!row.id.startsWith(becauseRowIdPrefix) &&
          row.id != sagaRowId &&
          row.id != gemsRowId &&
          row.id != upcomingRowId) {
        continue;
      }
      if (!row.items.any((i) => i.id == item.id)) continue;
      final items = [
        for (final i in row.items)
          if (i.id == item.id)
            AggregatedItem(
              id: i.id,
              serverId: i.serverId,
              rawData: {
                ...i.rawData,
                forYouFlag: false,
                'SeerrStatus': SeerrMediaStatus.pending,
              },
            )
          else
            i,
      ];
      _replaceRowById(row.copyWith(items: items));
    }
  }

  /// Appends the next Seerr page to [rowIndex]. Called from [loadMoreForRow],
  /// which owns the in-flight guard and the `hasMore` check.
  Future<void> _loadMoreSeerrRow(int rowIndex, SeerrRowType type) async {
    final row = _rows[rowIndex];
    final repo = await GetIt.instance.getAsync<SeerrRepository>();
    final seerrPrefs = GetIt.instance<SeerrPreferences>();
    await repo.ensureInitialized();
    if (!repo.isAvailable) return;

    final limit = seerrPrefs.fetchLimit.limit;
    final nextPage = (_seerrRowPages[row.id] ?? 1) + 1;

    // Assume this is the last page until a response says otherwise, so a row
    // without a paged endpoint stops asking rather than retrying forever.
    var rawItems = const <SeerrDiscoverItem>[];
    var exhausted = true;

    if (type == SeerrRowType.recentRequests) {
      final user = await repo.getCurrentUser();
      final response = await repo.getRequests(
        requestedBy: user.canViewAllRequests ? null : user.id,
        limit: limit,
        offset: (nextPage - 1) * limit,
      );
      rawItems = await _enrichSeerrItems(
        repo,
        _seerrItemsFromRequests(response.results),
      );
      exhausted = nextPage >= (response.pageInfo?.pages ?? nextPage);
    } else {
      final page = await _loadSeerrPage(
        repo,
        type,
        page: nextPage,
        limit: limit,
      );
      if (page != null) {
        rawItems = type == SeerrRowType.yourWatchlist
            ? await _enrichSeerrItems(repo, page.results)
            : page.results;
        exhausted = nextPage >= page.totalPages;
      }
    }

    // Advance even when the page contributed nothing. Availability filtering can
    // empty a whole page, and holding the pointer back would refetch that same
    // page on every scroll instead of moving on.
    _seerrRowPages[row.id] = nextPage;
    _appendSeerrRowItems(row, rawItems, type, exhausted: exhausted);
  }

  /// Adds a fetched page to a Seerr row, skipping what it already shows.
  void _appendSeerrRowItems(
    HomeRow row,
    List<SeerrDiscoverItem> rawItems,
    SeerrRowType? type, {
    required bool exhausted,
  }) {
    final existingIds = row.items.map((item) => item.id).toSet();
    final items = [
      ...row.items,
      ..._seerrAggregatedItems(
        rawItems,
        type,
        GetIt.instance<SeerrPreferences>().blockNsfw,
      ).where((item) => !existingIds.contains(item.id)),
    ];

    _replaceRowById(
      row.copyWith(
        items: items,
        totalCount: exhausted ? items.length : items.length + 1,
      ),
    );
  }

  /// Row ids are the prefix followed by the type's serialized name, so deriving
  /// the type keeps this in step as row types come and go.
  SeerrRowType? _seerrRowTypeForId(String rowId) {
    if (!rowId.startsWith(_seerrRowIdPrefix)) return null;
    final name = rowId.substring(_seerrRowIdPrefix.length);
    for (final type in SeerrRowType.values) {
      if (type.serializedName == name) return type;
    }
    return null;
  }

  Future<List<SeerrDiscoverItem>> _enrichSeerrItems(
    SeerrRepository repo,
    List<SeerrDiscoverItem> items,
  ) async =>
      (await mapBounded(
        items,
        _seerrEnrichConcurrency,
        (item) => _enrichSeerrItem(repo, item),
      )).whereType<SeerrDiscoverItem>().toList();

  List<SeerrDiscoverItem> _seerrItemsFromRequests(List<SeerrRequest> requests) {
    return requests.where((r) => r.media != null).map((r) {
      final media = r.media!;
      return SeerrDiscoverItem(
        id: media.tmdbId ?? media.id,
        title: media.title ?? media.name,
        name: media.name ?? media.title,
        overview: media.overview,
        releaseDate: media.releaseDate,
        firstAirDate: media.firstAirDate,
        mediaType: r.type,
        posterPath: media.posterPath,
        backdropPath: media.backdropPath,
        mediaInfo: SeerrMediaInfo(
          id: media.id,
          tmdbId: media.tmdbId,
          status: media.status,
        ),
      );
    }).toList();
  }

  /// A null [type] is a discover slider row, which hides what is available
  /// like the other discovery rows.
  List<AggregatedItem> _seerrAggregatedItems(
    List<SeerrDiscoverItem> rawItems,
    SeerrRowType? type,
    bool blockNsfw,
  ) {
    // The request, watchlist and recently added rows are meant to show media the
    // user already has, so only the discovery rows hide what is available.
    final hidesAvailable =
        type != SeerrRowType.recentlyAdded &&
        type != SeerrRowType.recentRequests &&
        type != SeerrRowType.yourWatchlist;

    return rawItems
        .where((item) {
          if (hidesAvailable && (item.isAvailable || item.isBlacklisted)) {
            return false;
          }
          if (blockNsfw) {
            if (item.adult) return false;
            final text = '${item.displayTitle} ${item.overview ?? ''}';
            if (SeerrDiscoverViewModel.nsfwPatterns.any(
              (p) => p.hasMatch(text),
            )) {
              return false;
            }
          }
          return true;
        })
        .map(
          (item) => AggregatedItem(
            id: item.id.toString(),
            serverId: 'seerr',
            rawData: {
              'Name': item.displayTitle,
              'Type': item.mediaType == 'tv' ? 'Series' : 'Movie',
              'Overview': item.overview ?? '',
              'PosterPath': item.posterPath ?? '',
              'BackdropPath': item.backdropPath ?? '',
              'ProductionYear': _extractYear(
                item.releaseDate ?? item.firstAirDate,
              ),
              'SeerrMediaType': item.mediaType,
              'SeerrStatus': item.mediaInfo?.status,
              // Something still to ask for opens the request sheet. Only
              // with a known media type, which the request is made for.
              if (_isRequestable(item.mediaInfo?.status) &&
                  (item.mediaType == 'movie' || item.mediaType == 'tv'))
                forYouFlag: true,
            },
          ),
        )
        .toList();
  }

  /// Whether Seerr would take a request for a title in [status]: unknown to
  /// it, or removed since.
  static bool _isRequestable(int? status) =>
      status == null ||
      status == SeerrMediaStatus.unknown ||
      status == SeerrMediaStatus.deleted;

  HomeRow _seerrRow(
    String rowId,
    String title,
    List<AggregatedItem> items, {
    int totalCount = 0,
  }) {
    return HomeRow(
      id: rowId,
      title: title,
      rowType: HomeRowType.pluginDynamic,
      items: items,
      totalCount: totalCount,
    );
  }

  /// Jump tiles with no fetch behind them, so the row renders complete on the
  /// first frame while the artwork catches up.
  HomeRow _seerrShortcutsRow(
    AppLocalizations l10n, {
    Map<SeerrShortcut, String> backdrops = const {},
  }) => _seerrRow(
    'seerr_shortcuts',
    l10n.seerrShortcutsRow,
    [
      for (final shortcut in SeerrShortcut.values)
        AggregatedItem(
          id: 'seerr_shortcut_${shortcut.name}',
          serverId: 'seerr',
          rawData: {
            'Name': shortcut.label(l10n),
            'Type': 'Folder',
            'Overview': '',
            'SeerrShortcut': shortcut.name,
            'BackdropPath': backdrops[shortcut] ?? '',
          },
        ),
    ],
  );

  /// One trending read dresses every tile. Artwork is the only thing it adds,
  /// so a failure still leaves a usable row.
  Future<HomeRow> _loadSeerrShortcutsRow(AppLocalizations l10n) async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) return _seerrShortcutsRow(l10n);

      final page = await repo.getTrending(
        limit: GetIt.instance<SeerrPreferences>().fetchLimit.limit,
      );
      final items = page.results.toList()..shuffle();
      List<String> pathsFor(String mediaType) => [
        for (final item in items)
          if (item.mediaType == mediaType &&
              (item.backdropPath?.isNotEmpty ?? false))
            item.backdropPath!,
      ];

      return _seerrShortcutsRow(
        l10n,
        backdrops: pickShortcutBackdrops(
          shortcuts: SeerrShortcut.values,
          movieBackdrops: pathsFor('movie'),
          tvBackdrops: pathsFor('tv'),
        ),
      );
    } catch (_) {
      return _seerrShortcutsRow(l10n);
    }
  }

  AggregatedItem _seerrFilterItem({
    required String id,
    required String name,
    required String imagePath,
    required String type,
    required String mediaType,
    required String filterType,
  }) {
    return AggregatedItem(
      id: id,
      serverId: 'seerr',
      rawData: {
        'Name': name,
        'Type': type,
        'Overview': '',
        'PosterPath': imagePath,
        'BackdropPath': imagePath,
        'MediaType': mediaType,
        'FilterType': filterType,
        'FilterName': name,
      },
    );
  }

  Future<SeerrDiscoverPage?> _loadSeerrPage(
    SeerrRepository repo,
    SeerrRowType type, {
    required int page,
    required int limit,
  }) async {
    final offset = (page - 1) * limit;
    switch (type) {
      case SeerrRowType.yourWatchlist:
        return repo.getWatchlist(page: page);
      case SeerrRowType.trending:
        return repo.getTrending(limit: limit, offset: offset);
      case SeerrRowType.popularMovies:
        return repo.getTrendingMovies(limit: limit, offset: offset);
      case SeerrRowType.popularSeries:
        return repo.getTrendingTv(limit: limit, offset: offset);
      case SeerrRowType.upcomingMovies:
        return repo.getUpcomingMovies(page: page);
      case SeerrRowType.upcomingSeries:
        return repo.getUpcomingTv(page: page);
      default:
        return null;
    }
  }

  Future<SeerrDiscoverItem> _enrichSeerrItem(
    SeerrRepository repo,
    SeerrDiscoverItem item,
  ) async {
    if (item.backdropPath != null &&
        item.voteAverage != null &&
        (item.releaseDate != null || item.firstAirDate != null)) {
      return item;
    }
    final tmdbId = item.mediaInfo?.tmdbId ?? item.id;
    if (tmdbId <= 0) return item;
    try {
      if (item.mediaType == 'tv') {
        final details = await repo.getTvDetails(tmdbId);
        return SeerrDiscoverItem(
          id: item.id,
          mediaType: item.mediaType,
          title: item.title ?? details.title,
          name: item.name ?? details.name,
          originalTitle: item.originalTitle,
          originalName: item.originalName,
          posterPath: details.posterPath ?? item.posterPath,
          backdropPath: details.backdropPath ?? item.backdropPath,
          overview: details.overview ?? item.overview,
          releaseDate: item.releaseDate ?? details.firstAirDate,
          firstAirDate: item.firstAirDate ?? details.firstAirDate,
          originalLanguage: item.originalLanguage,
          genreIds: item.genreIds,
          voteAverage: details.voteAverage ?? item.voteAverage,
          voteCount: item.voteCount,
          popularity: item.popularity,
          adult: item.adult,
          mediaInfo: item.mediaInfo,
          character: item.character,
          job: item.job,
          department: item.department,
        );
      }
      final details = await repo.getMovieDetails(tmdbId);
      return SeerrDiscoverItem(
        id: item.id,
        mediaType: item.mediaType,
        title: item.title ?? details.title,
        name: item.name,
        originalTitle: item.originalTitle,
        originalName: item.originalName,
        posterPath: details.posterPath ?? item.posterPath,
        backdropPath: details.backdropPath ?? item.backdropPath,
        overview: details.overview ?? item.overview,
        releaseDate: item.releaseDate ?? details.releaseDate,
        firstAirDate: item.firstAirDate ?? details.releaseDate,
        originalLanguage: item.originalLanguage,
        genreIds: item.genreIds,
        voteAverage: details.voteAverage ?? item.voteAverage,
        voteCount: item.voteCount,
        popularity: item.popularity,
        adult: item.adult,
        mediaInfo: item.mediaInfo,
        character: item.character,
        job: item.job,
        department: item.department,
      );
    } catch (_) {
      return item;
    }
  }


  Future<List<HomeRow>> _loadImdbRow(
    HomeSectionType sectionType,
    String title,
    String rowId,
  ) async {
    try {
      final customService = GetIt.instance<CustomExternalListsService>();
      final config = HomeSectionConfig.pluginDynamic(
        serverId: 'seerr', // placeholder
        pluginSection: rowId,
        pluginDisplayText: title,
        pluginSource: HomeSectionPluginSource.custom,
        pluginAdditionalData: jsonEncode({
          'source': 'imdb',
          'type': rowId,
        }),
      );

      var items = await customService.loadCustomRowFromCache(
        config,
        maxAge: CustomExternalListsService.cacheMaxAge,
      );
      if (items.isEmpty) {
        items = await customService.fetchCustomRow(config);
      }

      if (items.isEmpty) {
        return const [];
      }

      final aggregatedItems = items.map((item) {
        final itemId = item.imdbId.isNotEmpty ? item.imdbId : item.tmdbId;
        return AggregatedItem(
          id: itemId,
          serverId: 'seerr',
          rawData: {
            'Name': item.title,
            'Type': item.type,
            'Overview': '',
            'PosterPath': item.posterUrl ?? '',
            'BackdropPath': item.backdropUrl ?? '',
            'ProductionYear': item.year,
            'SeerrMediaType': item.type == 'Series' ? 'tv' : 'movie',
            'OfficialRating': item.officialRating,
            'ProviderIds': {
              if (item.imdbId.isNotEmpty) 'Imdb': item.imdbId,
              if (item.tmdbId.isNotEmpty) 'Tmdb': item.tmdbId,
            },
          },
        );
      }).toList();

      return [
        HomeRow(
          id: rowId,
          title: title,
          rowType: HomeRowType.pluginDynamic,
          items: withoutUnratedOrBlockedItems(aggregatedItems),
        )
      ];
    } catch (e) {
      debugPrint('[ImdbRow] Failed to load IMDb row $sectionType: $e');
      return const [];
    }
  }

  Future<List<HomeRow>> _loadTmdbChartRow(
    HomeSectionType sectionType,
    String title,
    String rowId,
  ) async {
    try {
      final customService = GetIt.instance<CustomExternalListsService>();
      final config = HomeSectionConfig.pluginDynamic(
        serverId: 'seerr', // placeholder
        pluginSection: rowId,
        pluginDisplayText: title,
        pluginSource: HomeSectionPluginSource.custom,
        pluginAdditionalData: jsonEncode({
          'source': 'tmdb_chart',
          'type': _tmdbChartTypeForSection(sectionType),
        }),
      );

      var items = await customService.loadCustomRowFromCache(
        config,
        maxAge: CustomExternalListsService.cacheMaxAge,
      );
      if (items.isEmpty) {
        items = await customService.fetchCustomRow(config);
      }

      if (items.isEmpty) {
        return const [];
      }

      final aggregatedItems = items.map((item) {
        final itemId = item.imdbId.isNotEmpty ? item.imdbId : item.tmdbId;
        return AggregatedItem(
          id: itemId,
          serverId: 'seerr',
          rawData: {
            'Name': item.title,
            'Type': item.type,
            'Overview': '',
            'PosterPath': item.posterUrl ?? '',
            'BackdropPath': item.backdropUrl ?? '',
            'ProductionYear': item.year,
            'SeerrMediaType': item.type == 'Series' ? 'tv' : 'movie',
            'OfficialRating': item.officialRating,
            'ProviderIds': {
              if (item.imdbId.isNotEmpty) 'Imdb': item.imdbId,
              if (item.tmdbId.isNotEmpty) 'Tmdb': item.tmdbId,
            },
          },
        );
      }).toList();

      return [
        HomeRow(
          id: rowId,
          title: title,
          rowType: HomeRowType.pluginDynamic,
          items: withoutUnratedOrBlockedItems(aggregatedItems),
        )
      ];
    } catch (e) {
      debugPrint('[TmdbChartRow] Failed to load TMDB chart row $sectionType: $e');
      return const [];
    }
  }

  Future<List<HomeRow>> _loadSeasonalRow(
    AppLocalizations l10n, {
    bool forceRefresh = false,
  }) async {
    try {
      if (forceRefresh) _seasonalMemo = null;
      final sync = GetIt.instance<PluginSyncService>();
      var body = _seasonalMemo;
      if (body == null) {
        final country = seasonalCountryParam(
          _prefs.get(UserPreferences.seasonalRowCountry),
          deviceCountry: deviceCountryCode(),
        );
        body = await sync.fetchSeasonalRow(_client, country: country);
        if (body == null) return const [];
        _seasonalMemo = body;
      }

      final mapped = mapSeasonalResponse(
        body,
        serverId: _serverId,
        hiddenHolidays: UserPreferences.parseSeasonalRowHiddenHolidays(
          _prefs.get(UserPreferences.seasonalRowHiddenHolidays),
        ),
      );
      if (mapped == null) return const [];

      // Suggestions are Seerr cards, so a device with Seerr switched off keeps
      // them out even though the server was happy to send them.
      final items = [
        ...withoutBlockedItems(mapped.owned),
        if (sync.seerrAvailable) ...withoutUnratedOrBlockedItems(mapped.suggestions),
      ];
      if (items.isEmpty) return const [];

      return [
        HomeRow(
          id: 'seasonal',
          title: seasonalHolidayTitle(mapped.holiday, l10n),
          rowType: HomeRowType.pluginDynamic,
          items: items,
        ),
      ];
    } catch (e) {
      debugPrint('[SeasonalRow] Failed to load the seasonal row: $e');
      return const [];
    }
  }

  /// The parts of a seasonal answer Home can show, or null when the viewer hid
  /// the holiday, there is no holiday, or nothing came back for it.
  @visibleForTesting
  static SeasonalRowData? mapSeasonalResponse(
    Map<String, dynamic> body, {
    required String serverId,
    required Set<String> hiddenHolidays,
  }) {
    final holiday = body['holiday'] as String?;
    if (holiday == null || holiday.isEmpty || hiddenHolidays.contains(holiday)) {
      return null;
    }

    final owned = <AggregatedItem>[];
    for (final raw in (body['items'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      final id = data['Id']?.toString();
      if (id == null || id.isEmpty) continue;
      owned.add(AggregatedItem(id: id, serverId: serverId, rawData: data));
    }

    final suggestions = <AggregatedItem>[];
    for (final raw in (body['suggestions'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final providerIds = raw['providerIds'];
      final tmdbId = (providerIds is Map ? providerIds['Tmdb'] : null)?.toString() ?? raw['id']?.toString() ?? '';
      final imdbId = (providerIds is Map ? providerIds['Imdb'] : null)?.toString() ?? '';
      if (tmdbId.isEmpty && imdbId.isEmpty) continue;
      final poster = raw['posterUrl'] as String?;
      suggestions.add(AggregatedItem(
        id: tmdbId.isNotEmpty ? tmdbId : imdbId,
        serverId: 'seerr',
        rawData: {
          'Name': raw['name'] ?? '',
          'Type': 'Movie',
          'Overview': raw['overview'] ?? '',
          'PosterPath': poster ?? '',
          'BackdropPath': raw['backdropUrl'] ?? '',
          'ProductionYear': raw['productionYear'],
          'CommunityRating': raw['rating'],
          'Genres': raw['genres'],
          'RunTimeTicks': raw['runTimeTicks'],
          'SeerrMediaType': 'movie',
          'OfficialRating': raw['officialRating'],
          'ProviderIds': {
            if (imdbId.isNotEmpty) 'Imdb': imdbId,
            if (tmdbId.isNotEmpty) 'Tmdb': tmdbId,
          },
        },
      ));
    }

    if (owned.isEmpty && suggestions.isEmpty) return null;
    return SeasonalRowData(holiday: holiday, owned: owned, suggestions: suggestions);
  }

  String _tmdbChartTypeForSection(HomeSectionType sectionType) {
    return switch (sectionType) {
      HomeSectionType.tmdbPopularMovies => 'movie/popular',
      HomeSectionType.tmdbTopRatedMovies => 'movie/top_rated',
      HomeSectionType.tmdbNowPlayingMovies => 'movie/now_playing',
      HomeSectionType.tmdbUpcomingMovies => 'movie/upcoming',
      HomeSectionType.tmdbPopularTv => 'tv/popular',
      HomeSectionType.tmdbTopRatedTv => 'tv/top_rated',
      HomeSectionType.tmdbAiringTodayTv => 'tv/airing_today',
      HomeSectionType.tmdbOnTheAirTv => 'tv/on_the_air',
      HomeSectionType.tmdbTrendingMovieDaily => 'trending/movie/day',
      HomeSectionType.tmdbTrendingMovieWeekly => 'trending/movie/week',
      HomeSectionType.tmdbTrendingTvDaily => 'trending/tv/day',
      HomeSectionType.tmdbTrendingTvWeekly => 'trending/tv/week',
      HomeSectionType.tmdbTrendingAllWeekly => 'trending/all/week',
      _ => 'movie/popular',
    };
  }

  int? _extractYear(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;
    try {
      final parts = dateString.split('-');
      if (parts.isNotEmpty) {
        return int.tryParse(parts[0]);
      }
    } catch (_) {}
    return null;
  }

  List<AggregatedItem> _filterAndFormatRadarrItems(List<AggregatedItem> rawItems) {
    final now = DateTime.now();
    final showCinema = _prefs.get(UserPreferences.radarrCalendarShowCinema);
    final showDigital = _prefs.get(UserPreferences.radarrCalendarShowDigital);
    final showPhysical = _prefs.get(UserPreferences.radarrCalendarShowPhysical);
    final showDate = _prefs.get(UserPreferences.radarrCalendarShowDate);

    final List<AggregatedItem> filtered = [];

    for (final item in rawItems) {
      final inCinemasStr = item.rawData['InCinemas'] as String?;
      final digitalReleaseStr = item.rawData['DigitalRelease'] as String?;
      final physicalReleaseStr = item.rawData['PhysicalRelease'] as String?;

      final inCinemas = inCinemasStr != null ? DateTime.tryParse(inCinemasStr) : null;
      final digitalRelease = digitalReleaseStr != null ? DateTime.tryParse(digitalReleaseStr) : null;
      final physicalRelease = physicalReleaseStr != null ? DateTime.tryParse(physicalReleaseStr) : null;

      final enabledReleases = <DateTime, String>{};
      if (showCinema && inCinemas != null && inCinemas.isAfter(now.subtract(const Duration(days: 1)))) {
        enabledReleases[inCinemas] = 'Cinema: ';
      }
      if (showDigital && digitalRelease != null && digitalRelease.isAfter(now.subtract(const Duration(days: 1)))) {
        enabledReleases[digitalRelease] = 'Digital: ';
      }
      if (showPhysical && physicalRelease != null && physicalRelease.isAfter(now.subtract(const Duration(days: 1)))) {
        enabledReleases[physicalRelease] = 'Physical: ';
      }

      if (enabledReleases.isEmpty) continue;

      final sortedDates = enabledReleases.keys.toList()..sort();
      final targetReleaseDate = sortedDates.first;
      final releaseType = enabledReleases[targetReleaseDate]!;

      String? subtitleText;
      if (showDate) {
        final dateStr = _formatDateHuman(targetReleaseDate);
        subtitleText = '$releaseType$dateStr';
      }

      final newRawData = Map<String, dynamic>.from(item.rawData);
      newRawData['Subtitle'] = subtitleText;
      newRawData['CalendarDate'] = targetReleaseDate.toIso8601String();

      filtered.add(AggregatedItem(
        id: item.id,
        serverId: item.serverId,
        rawData: newRawData,
      ));
    }

    filtered.sort((a, b) {
      final dateA = a.rawData['CalendarDate'] as String? ?? '';
      final dateB = b.rawData['CalendarDate'] as String? ?? '';
      return dateA.compareTo(dateB);
    });

    return filtered;
  }

  List<AggregatedItem> _formatSonarrItems(List<AggregatedItem> rawItems) {
    final showDate = _prefs.get(UserPreferences.sonarrCalendarShowDate);
    final showEpisodeInfo = _prefs.get(UserPreferences.sonarrCalendarShowEpisodeInfo);

    return rawItems.map((item) {
      final airDateUtcStr = item.rawData['CalendarDate'] as String?;
      final airDateUtc = airDateUtcStr != null ? DateTime.tryParse(airDateUtcStr) : null;
      if (airDateUtc == null) return item;

      final sNum = item.rawData['SeasonNumber'] as String? ?? '0';
      final eNum = item.rawData['EpisodeNumber'] as String? ?? '0';

      String? subtitleText;
      if (showDate && showEpisodeInfo) {
        final dateStr = _formatDateHuman(airDateUtc);
        subtitleText = 'Next Episode: $dateStr (S$sNum:E$eNum)';
      } else if (showDate) {
        final dateStr = _formatDateHuman(airDateUtc);
        subtitleText = 'Next Episode: $dateStr';
      } else if (showEpisodeInfo) {
        subtitleText = 'Next Episode: (S$sNum:E$eNum)';
      }

      final newRawData = Map<String, dynamic>.from(item.rawData);
      newRawData['Subtitle'] = subtitleText;

      return AggregatedItem(
        id: item.id,
        serverId: item.serverId,
        rawData: newRawData,
      );
    }).toList();
  }

  Future<List<HomeRow>> _loadRadarrCalendarRow({bool forceRefresh = false}) async {
    final merge = _prefs.get(UserPreferences.mergeRadarrSonarrCalendars);
    if (merge) {
      return _loadMergedCalendarRow(forceRefresh: forceRefresh);
    }
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final lastFetch = _prefs.get(UserPreferences.lastRadarrCalendarFetchTime);
      final cacheAge = nowMs - lastFetch;
      final shouldFetch = forceRefresh || cacheAge > const Duration(days: 1).inMilliseconds;

      List<AggregatedItem> items;
      if (shouldFetch) {
        final fetchedItems = await _fetchRadarrCalendarFromApi();
        if (fetchedItems != null) {
          await _saveRadarrCalendarToCache(fetchedItems);
          await _prefs.set(UserPreferences.lastRadarrCalendarFetchTime, nowMs);
          items = _filterAndFormatRadarrItems(fetchedItems);
        } else {
          final cached = await _loadRadarrCalendarFromCache();
          items = _filterAndFormatRadarrItems(cached);
        }
      } else {
        final cached = await _loadRadarrCalendarFromCache();
        items = _filterAndFormatRadarrItems(cached);
        if (items.isEmpty) {
          final fetchedItems = await _fetchRadarrCalendarFromApi();
          if (fetchedItems != null) {
            await _saveRadarrCalendarToCache(fetchedItems);
            await _prefs.set(UserPreferences.lastRadarrCalendarFetchTime, nowMs);
            items = _filterAndFormatRadarrItems(fetchedItems);
          }
        }
      }

      return [
        HomeRow(
          id: 'radarr_calendar',
          title: 'Upcoming Movies (Radarr)',
          rowType: HomeRowType.pluginDynamic,
          items: items,
        )
      ];
    } catch (e) {
      debugPrint('[RadarrCalendar] Failed to load: $e');
      return const [];
    }
  }

  Future<List<HomeRow>> _loadSonarrCalendarRow({bool forceRefresh = false}) async {
    final merge = _prefs.get(UserPreferences.mergeRadarrSonarrCalendars);
    if (merge) {
      final hasRadarrConfig = _prefs.homeSectionsConfig.any((c) => c.enabled && c.type == HomeSectionType.radarrCalendar);
      if (hasRadarrConfig) {
        return const [];
      } else {
        return _loadMergedCalendarRow(forceRefresh: forceRefresh);
      }
    }
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final lastFetch = _prefs.get(UserPreferences.lastSonarrCalendarFetchTime);
      final cacheAge = nowMs - lastFetch;
      final shouldFetch = forceRefresh || cacheAge > const Duration(days: 1).inMilliseconds;

      List<AggregatedItem> items;
      if (shouldFetch) {
        final fetchedItems = await _fetchSonarrCalendarFromApi();
        if (fetchedItems != null) {
          await _saveSonarrCalendarToCache(fetchedItems);
          await _prefs.set(UserPreferences.lastSonarrCalendarFetchTime, nowMs);
          items = _formatSonarrItems(fetchedItems);
        } else {
          final cached = await _loadSonarrCalendarFromCache();
          items = _formatSonarrItems(cached);
        }
      } else {
        final cached = await _loadSonarrCalendarFromCache();
        items = _formatSonarrItems(cached);
        if (items.isEmpty) {
          final fetchedItems = await _fetchSonarrCalendarFromApi();
          if (fetchedItems != null) {
            await _saveSonarrCalendarToCache(fetchedItems);
            await _prefs.set(UserPreferences.lastSonarrCalendarFetchTime, nowMs);
            items = _formatSonarrItems(fetchedItems);
          }
        }
      }

      return [
        HomeRow(
          id: 'sonarr_calendar',
          title: 'Upcoming TV Shows (Sonarr)',
          rowType: HomeRowType.pluginDynamic,
          items: items,
        )
      ];
    } catch (e) {
      debugPrint('[SonarrCalendar] Failed to load: $e');
      return const [];
    }
  }

  /// Entries written before CacheVerV2 have a different shape, so the marker on
  /// its own decides staleness. Artwork fields are deliberately not checked,
  /// because an entry whose poster is genuinely missing is still valid and
  /// refetching it only writes the same empty value back.
  static bool _isStaleCalendarCache(List<AggregatedItem> items) =>
      items.any((x) => !x.rawData.containsKey('CacheVerV2'));

  Future<List<AggregatedItem>> _loadRadarrCalendarFromCache() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/radarr_calendar_cache.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List;
        final items = list.map((x) => _aggregatedItemFromJson(x as Map<String, dynamic>)).toList();
        if (_isStaleCalendarCache(items)) {
          debugPrint('[RadarrCalendarCache] Old cache detected, invalidating to force fresh fetch');
          try {
            await file.delete();
          } catch (_) {}
          return const [];
        }
        return items;
      }
    } catch (e) {
      debugPrint('[RadarrCalendarCache] Failed to load: $e');
    }
    return const [];
  }

  Future<void> _saveRadarrCalendarToCache(List<AggregatedItem> items) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/radarr_calendar_cache.json');
      final content = jsonEncode(items.map((x) => _aggregatedItemToJson(x)).toList());
      await file.writeAsString(content, flush: true);
    } catch (e) {
      debugPrint('[RadarrCalendarCache] Failed to save: $e');
    }
  }

  Future<List<AggregatedItem>> _loadSonarrCalendarFromCache() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/sonarr_calendar_cache.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List;
        final items = list.map((x) => _aggregatedItemFromJson(x as Map<String, dynamic>)).toList();
        if (_isStaleCalendarCache(items)) {
          debugPrint('[SonarrCalendarCache] Old cache detected, invalidating to force fresh fetch');
          try {
            await file.delete();
          } catch (_) {}
          return const [];
        }
        return items;
      }
    } catch (e) {
      debugPrint('[SonarrCalendarCache] Failed to load: $e');
    }
    return const [];
  }

  Future<void> _saveSonarrCalendarToCache(List<AggregatedItem> items) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/sonarr_calendar_cache.json');
      final content = jsonEncode(items.map((x) => _aggregatedItemToJson(x)).toList());
      await file.writeAsString(content, flush: true);
    } catch (e) {
      debugPrint('[SonarrCalendarCache] Failed to save: $e');
    }
  }

  Map<String, dynamic> _aggregatedItemToJson(AggregatedItem item) {
    return {
      'id': item.id,
      'serverId': item.serverId,
      'rawData': item.rawData,
    };
  }

  AggregatedItem _aggregatedItemFromJson(Map<String, dynamic> json) {
    return AggregatedItem(
      id: json['id'] as String,
      serverId: json['serverId'] as String,
      rawData: Map<String, dynamic>.from(json['rawData'] as Map),
    );
  }

  Future<List<AggregatedItem>?> _fetchRadarrCalendarFromApi() async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      final now = DateTime.now();
      final start = now.toIso8601String().substring(0, 10);
      final end = now.add(const Duration(days: 90)).toIso8601String().substring(0, 10);

      // The plugin fetches the Radarr calendar server side, so the API key stays on the server and
      // this still works when a remote client cant reach a LAN only Radarr.
      final results = await repo.getRadarrCalendar(start: start, end: end);

      final enrichCompleters = await mapBounded(
        results,
        5,
        (res) async {
          if (res is! Map) return null;
          final tmdbIdVal = res['tmdbId'];
          if (tmdbIdVal == null || tmdbIdVal == 0) return null;
          final tmdbId = tmdbIdVal.toString();

          final title = res['title'] as String? ?? 'Unknown';
          final overview = res['overview'] as String? ?? '';
          final year = res['year'] as int?;

          final inCinemasStr = res['inCinemas'] as String?;
          final digitalReleaseStr = res['digitalRelease'] as String?;
          final physicalReleaseStr = res['physicalRelease'] as String?;

          final inCinemas = inCinemasStr != null ? DateTime.tryParse(inCinemasStr) : null;
          final digitalRelease = digitalReleaseStr != null ? DateTime.tryParse(digitalReleaseStr) : null;
          final physicalRelease = physicalReleaseStr != null ? DateTime.tryParse(physicalReleaseStr) : null;

          final allReleases = <DateTime>[];
          if (inCinemas != null && inCinemas.isAfter(now.subtract(const Duration(days: 1)))) {
            allReleases.add(inCinemas);
          }
          if (digitalRelease != null && digitalRelease.isAfter(now.subtract(const Duration(days: 1)))) {
            allReleases.add(digitalRelease);
          }
          if (physicalRelease != null && physicalRelease.isAfter(now.subtract(const Duration(days: 1)))) {
            allReleases.add(physicalRelease);
          }

          if (allReleases.isEmpty) return null;

          final sortedDates = allReleases..sort();
          final defaultReleaseDate = sortedDates.first;

          String? posterPath;
          String? backdropPath;
          final images = res['images'] as List?;
          if (images != null) {
            for (final img in images) {
              if (img is! Map) continue;
              final type = img['coverType'] as String?;
              final remoteUrl = img['remoteUrl'] as String? ?? img['url'] as String?;
              // Only external image URLs are used. A local arr image would need the API key and
              // wouldnt be reachable from a remote client anyway.
              if (remoteUrl != null && remoteUrl.startsWith('http')) {
                if (type == 'poster') {
                  posterPath = remoteUrl;
                } else if (type == 'fanart') {
                  backdropPath = remoteUrl;
                }
              }
            }
          }

          if (posterPath == null || posterPath.isEmpty) {
            try {
              final details = await repo.getMovieDetails(int.parse(tmdbId));
              posterPath = _tmdbImageUrl(details.posterPath, 300) ?? '';
              backdropPath = _tmdbImageUrl(details.backdropPath, 1280) ?? '';
            } catch (_) {}
          }

          return _CalendarItemWithDate(
            item: AggregatedItem(
              id: tmdbId,
              serverId: 'seerr',
              rawData: {
                'Name': title,
                'Type': 'Movie',
                'Overview': overview,
                'PosterPath': posterPath,
                'BackdropPath': backdropPath,
                'ProductionYear': year,
                'SeerrMediaType': 'movie',
                'InCinemas': inCinemasStr,
                'DigitalRelease': digitalReleaseStr,
                'PhysicalRelease': physicalReleaseStr,
                'CalendarDate': defaultReleaseDate.toIso8601String(),
                'CacheVerV2': true,
              },
            ),
            date: defaultReleaseDate,
          );
        },
      );

      final calendarItems = enrichCompleters.whereType<_CalendarItemWithDate>().toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      return calendarItems.map((c) => c.item).toList();
    } catch (e) {
      debugPrint('[RadarrCalendarApi] Failed to fetch: $e');
      return null;
    }
  }

  Future<List<AggregatedItem>?> _fetchSonarrCalendarFromApi() async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      final now = DateTime.now();
      final start = now.toIso8601String().substring(0, 10);
      final end = now.add(const Duration(days: 90)).toIso8601String().substring(0, 10);

      // The plugin fetches the Sonarr calendar server side, so the API key stays on the server and
      // this still works when a remote client cant reach a LAN only Sonarr.
      final results = await repo.getSonarrCalendar(start: start, end: end);

      final groupedEpisodes = <int, Map<String, dynamic>>{};
      for (final res in results) {
        if (res is! Map) continue;
        final seriesMap = res['series'];
        if (seriesMap is! Map) continue;

        final tvdbIdVal = seriesMap['tvdbId'];
        if (tvdbIdVal == null || tvdbIdVal == 0) continue;
        final tvdbId = tvdbIdVal as int;

        final airDateUtcStr = res['airDateUtc'] as String?;
        final airDateUtc = airDateUtcStr != null ? DateTime.tryParse(airDateUtcStr) : null;
        if (airDateUtc == null) continue;

        final existing = groupedEpisodes[tvdbId];
        if (existing == null) {
          groupedEpisodes[tvdbId] = {
            'series': seriesMap,
            'airDate': airDateUtc,
            'seasonNumber': res['seasonNumber'],
            'episodeNumber': res['episodeNumber'],
          };
        } else {
          final existingAirDate = existing['airDate'] as DateTime;
          if (airDateUtc.isBefore(existingAirDate)) {
            existing['airDate'] = airDateUtc;
            existing['seasonNumber'] = res['seasonNumber'];
            existing['episodeNumber'] = res['episodeNumber'];
          }
        }
      }

      final enrichCompleters = await mapBounded(
        groupedEpisodes.values.toList(),
        5,
        (episodeInfo) async {
          final seriesMap = episodeInfo['series'] as Map;
          final tvdbId = seriesMap['tvdbId'] as int;
          final seriesTitle = seriesMap['title'] as String? ?? 'Unknown';
          final overview = seriesMap['overview'] as String? ?? '';
          final airDateUtc = episodeInfo['airDate'] as DateTime;

          int? tmdbId;
          final tmdbIdVal = seriesMap['tmdbId'];
          if (tmdbIdVal != null && tmdbIdVal != 0) {
            tmdbId = tmdbIdVal as int;
          } else {
            try {
              final tvDetails = await repo.getTvDetailsByTvdb(tvdbId);
              tmdbId = tvDetails.id;
            } catch (_) {}
          }

          if (tmdbId == null || tmdbId == 0) return null;

          String? posterPath;
          String? backdropPath;
          final images = seriesMap['images'] as List?;
          if (images != null) {
            for (final img in images) {
              if (img is! Map) continue;
              final type = img['coverType'] as String?;
              final remoteUrl = img['remoteUrl'] as String? ?? img['url'] as String?;
              // Only external image URLs are used. A local arr image would need the API key and
              // wouldnt be reachable from a remote client anyway.
              if (remoteUrl != null && remoteUrl.startsWith('http')) {
                if (type == 'poster') {
                  posterPath = remoteUrl;
                } else if (type == 'fanart') {
                  backdropPath = remoteUrl;
                }
              }
            }
          }

          if (posterPath == null || posterPath.isEmpty) {
            try {
              final details = await repo.getTvDetails(tmdbId);
              posterPath = _tmdbImageUrl(details.posterPath, 300) ?? '';
              backdropPath = _tmdbImageUrl(details.backdropPath, 1280) ?? '';
            } catch (_) {}
          }

          final sNum = (episodeInfo['seasonNumber'] ?? 0).toString();
          final eNum = (episodeInfo['episodeNumber'] ?? 0).toString();

          return _CalendarItemWithDate(
            item: AggregatedItem(
              id: tmdbId.toString(),
              serverId: 'seerr',
              rawData: {
                'Name': seriesTitle,
                'Type': 'Series',
                'Overview': overview,
                'PosterPath': posterPath,
                'BackdropPath': backdropPath,
                'SeerrMediaType': 'tv',
                'SeasonNumber': sNum,
                'EpisodeNumber': eNum,
                'CalendarDate': airDateUtc.toIso8601String(),
                'CacheVerV2': true,
              },
            ),
            date: airDateUtc,
          );
        },
      );

      final calendarItems = enrichCompleters.whereType<_CalendarItemWithDate>().toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      return calendarItems.map((c) => c.item).toList();
    } catch (e) {
      debugPrint('[SonarrCalendarApi] Failed to fetch: $e');
      return null;
    }
  }

  String? _tmdbImageUrl(String? path, int width) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return 'https://image.tmdb.org/t/p/w$width$path';
  }

  String _formatDateHuman(DateTime date) {
    final months = [
      'Jan.',
      'Feb.',
      'Mar.',
      'Apr.',
      'May',
      'Jun.',
      'Jul.',
      'Aug.',
      'Sep.',
      'Oct.',
      'Nov.',
      'Dec.'
    ];
    final month = months[date.month - 1];
    final day = date.day;
    final suffix = switch (day) {
      1 || 21 || 31 => 'st',
      2 || 22 => 'nd',
      3 || 23 => 'rd',
      _ => 'th',
    };
    return '$month $day$suffix';
  }

  Future<List<HomeRow>> _loadMergedCalendarRow({bool forceRefresh = false}) async {
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // 1. Load Radarr items
      final lastRadarrFetch = _prefs.get(UserPreferences.lastRadarrCalendarFetchTime);
      final radarrCacheAge = nowMs - lastRadarrFetch;
      final shouldFetchRadarr = forceRefresh || radarrCacheAge > const Duration(days: 1).inMilliseconds;

      List<AggregatedItem> radarrItems;
      if (shouldFetchRadarr) {
        final fetched = await _fetchRadarrCalendarFromApi();
        if (fetched != null) {
          radarrItems = fetched;
          await _saveRadarrCalendarToCache(radarrItems);
          await _prefs.set(UserPreferences.lastRadarrCalendarFetchTime, nowMs);
        } else {
          radarrItems = await _loadRadarrCalendarFromCache();
        }
      } else {
        radarrItems = await _loadRadarrCalendarFromCache();
        if (radarrItems.isEmpty) {
          final fetched = await _fetchRadarrCalendarFromApi();
          if (fetched != null) {
            radarrItems = fetched;
            await _saveRadarrCalendarToCache(radarrItems);
            await _prefs.set(UserPreferences.lastRadarrCalendarFetchTime, nowMs);
          }
        }
      }

      // 2. Load Sonarr items
      final lastSonarrFetch = _prefs.get(UserPreferences.lastSonarrCalendarFetchTime);
      final sonarrCacheAge = nowMs - lastSonarrFetch;
      final shouldFetchSonarr = forceRefresh || sonarrCacheAge > const Duration(days: 1).inMilliseconds;

      List<AggregatedItem> sonarrItems;
      if (shouldFetchSonarr) {
        final fetched = await _fetchSonarrCalendarFromApi();
        if (fetched != null) {
          sonarrItems = fetched;
          await _saveSonarrCalendarToCache(sonarrItems);
          await _prefs.set(UserPreferences.lastSonarrCalendarFetchTime, nowMs);
        } else {
          sonarrItems = await _loadSonarrCalendarFromCache();
        }
      } else {
        sonarrItems = await _loadSonarrCalendarFromCache();
        if (sonarrItems.isEmpty) {
          final fetched = await _fetchSonarrCalendarFromApi();
          if (fetched != null) {
            sonarrItems = fetched;
            await _saveSonarrCalendarToCache(sonarrItems);
            await _prefs.set(UserPreferences.lastSonarrCalendarFetchTime, nowMs);
          }
        }
      }

      // 3. Merge and sort
      final filteredRadarr = _filterAndFormatRadarrItems(radarrItems);
      final filteredSonarr = _formatSonarrItems(sonarrItems);
      final mergedItems = [...filteredRadarr, ...filteredSonarr];
      mergedItems.sort((a, b) {
        final dateA = a.rawData['CalendarDate'] as String? ?? '';
        final dateB = b.rawData['CalendarDate'] as String? ?? '';
        return dateA.compareTo(dateB);
      });

      return [
        HomeRow(
          id: 'merged_calendar',
          title: 'Upcoming Releases',
          rowType: HomeRowType.pluginDynamic,
          items: mergedItems,
        )
      ];
    } catch (e) {
      debugPrint('[MergedCalendar] Failed to load merged calendar: $e');
      return const [];
    }
  }

  Future<void> _checkAndTriggerDailyExternalRowsRefresh() async {
    final lastRefreshMs = _prefs.get(UserPreferences.lastExternalRowsRefreshTime);
    final now = DateTime.now();
    final lastRefreshDate = DateTime.fromMillisecondsSinceEpoch(lastRefreshMs);
    final isDifferentDay = lastRefreshMs == 0 ||
        now.year != lastRefreshDate.year ||
        now.month != lastRefreshDate.month ||
        now.day != lastRefreshDate.day ||
        now.difference(lastRefreshDate).inHours >= 24;

    if (!isDifferentDay) return;

    debugPrint('[DailyRefresh] Day changed or first run. Triggering background cache refresh of enabled lists...');

    await _prefs.set(UserPreferences.lastExternalRowsRefreshTime, now.millisecondsSinceEpoch);
    _seasonalMemo = null;

    unawaited(() async {
      try {
        // Let the initial home load settle before this network sweep and its
        // follow-up load() run.
        await Future.delayed(const Duration(seconds: 15));
        if (_client.userId != _ownerUserId) return;

        final futures = <Future<void>>[];

        final customService = GetIt.instance<CustomExternalListsService>();
        final configs = _prefs.homeSectionsConfig;
        for (final config in configs) {
          if (config.pluginSource == HomeSectionPluginSource.custom && config.enabled) {
            futures.add(() async {
              try {
                await customService.fetchCustomRow(config, forceRefresh: true);
              } catch (e) {
                debugPrint('[DailyRefresh] Failed to refresh custom row ${config.pluginSection}: $e');
              }
            }());
          }
        }

        if (futures.isNotEmpty) {
          await Future.wait(futures);
          debugPrint('[DailyRefresh] Background cache refresh complete. Reloading HomeViewModel rows...');
          await load(preserveExisting: true);
        }
      } catch (e) {
        debugPrint('[DailyRefresh] Error during background refresh: $e');
      }
    }());
  }
}

class _CalendarItemWithDate {
  final AggregatedItem item;
  final DateTime date;
  _CalendarItemWithDate({required this.item, required this.date});
}

/// A seasonal answer from Moonbase, mapped to Home items. Owned movies belong
/// to this server and play, suggestions are Seerr cards.
class SeasonalRowData {
  final String holiday;
  final List<AggregatedItem> owned;
  final List<AggregatedItem> suggestions;
  const SeasonalRowData({
    required this.holiday,
    required this.owned,
    required this.suggestions,
  });
}
