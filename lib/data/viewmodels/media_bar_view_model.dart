import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:server_core/server_core.dart';

import '../../preference/user_preferences.dart';
import '../models/aggregated_item.dart';
import '../models/bookshelf_detail.dart';
import '../models/gallery_detail.dart';
import '../models/media_bar_slide_item.dart';
import '../models/media_bar_state.dart';
import '../repositories/mdblist_repository.dart';
import '../repositories/media_bar_repository.dart';
import '../services/media_bar_cache_store.dart';
import '../../util/startup_timeline.dart';
import '../services/tonight/tonight_service.dart';

class MediaBarViewModel extends ChangeNotifier {
  final MediaBarRepository _repository;
  final MdbListRepository _mdbListRepository;
  final UserPreferences _prefs;
  final MediaServerClient _client;

  MediaBarState _state = const MediaBarLoading();
  MediaBarState get state => _state;

  /// The last slides, painted at once on a cold start while the fresh ones
  /// load.
  final _cache = MediaBarCacheStore();
  bool _triedCache = false;

  String _cacheKey() =>
      '${_client.baseUrl}|${_client.userId}|${_prefs.get(UserPreferences.mediaBarMode)}'
      '|${_prefs.get(UserPreferences.mediaBarContentType)}'
      '|${_prefs.get(UserPreferences.mediaBarItemCount)}'
      '|${_prefs.get(UserPreferences.mediaBarSourceType)}';

  final _ratings = <String, Map<String, double>>{};
  final _bookshelfDetails = <String, BookshelfDetail>{};
  final _bookshelfDetailInFlight = <String>{};
  final _galleryDetails = <String, GalleryDetail>{};
  final _galleryDetailInFlight = <String>{};
  final _ratingsInFlight = <String>{};
  bool _isLoading = false;
  int _loadGeneration = 0;

  String get baseUrl => _client.baseUrl;

  late String _lastMode;
  late String _lastContentType;
  late String _lastItemCount;
  late String _lastSource;

  List<MediaBarSlideItem> get items =>
      _state is MediaBarReady ? (_state as MediaBarReady).items : const [];

  Map<String, double> ratingsFor(String itemId) => _ratings[itemId] ?? const {};

  Future<void> ensureRatings(String itemId) async {
    if (itemId.isEmpty) return;
    if (!_prefs.get(UserPreferences.enableAdditionalRatings)) return;
    if (_ratings.containsKey(itemId)) return;
    if (!_ratingsInFlight.add(itemId)) return;
    try {
      final item = items.where((i) => i.itemId == itemId).firstOrNull;
      if (item == null) return;
      await _loadItemRatings(item);
      if (_ratings.containsKey(itemId)) {
        notifyListeners();
      }
    } finally {
      _ratingsInFlight.remove(itemId);
    }
  }

  BookshelfDetail? bookshelfDetailFor(String itemId) =>
      _bookshelfDetails[itemId];

  Future<void> ensureBookshelfDetail(String itemId) async {
    if (itemId.isEmpty) return;
    if (_bookshelfDetails.containsKey(itemId)) return;
    if (!_bookshelfDetailInFlight.add(itemId)) return;

    try {
      final raw = await _client.itemsApi.getItem(itemId);
      if (raw.isEmpty) return;
      final aggregated = AggregatedItem(
        id: itemId,
        serverId: raw['ServerId']?.toString() ?? '',
        rawData: raw,
      );
      _bookshelfDetails[itemId] = BookshelfDetail.fromItem(itemId, aggregated);
      notifyListeners();
    } catch (_) {
      // Leave uncached so a later selection can retry.
    } finally {
      _bookshelfDetailInFlight.remove(itemId);
    }
  }

  GalleryDetail? galleryDetailFor(String itemId) => _galleryDetails[itemId];

  Future<void> ensureGalleryDetail(String itemId) async {
    if (itemId.isEmpty) return;
    if (_galleryDetails.containsKey(itemId)) return;
    if (!_galleryDetailInFlight.add(itemId)) return;

    try {
      final raw = await _client.itemsApi.getItem(itemId);
      if (raw.isEmpty) return;
      final aggregated = AggregatedItem(
        id: itemId,
        serverId: raw['ServerId']?.toString() ?? '',
        rawData: raw,
      );
      _galleryDetails[itemId] = GalleryDetail.fromItem(itemId, aggregated);
      notifyListeners();
    } catch (_) {
    } finally {
      _galleryDetailInFlight.remove(itemId);
    }
  }

  MediaBarViewModel(
    this._repository,
    this._mdbListRepository,
    this._prefs,
    this._client,
  ) {
    _lastMode = UserPreferences.normalizeMediaBarMode(
      _prefs.get(UserPreferences.mediaBarMode),
    );
    _lastContentType = _prefs.get(UserPreferences.mediaBarContentType);
    _lastItemCount = _prefs.get(UserPreferences.mediaBarItemCount);
    _lastSource = _prefs.get(UserPreferences.mediaBarSourceType);
    _prefs.addListener(_onPrefsChanged);
    TonightService.instance.answersChanged.addListener(_onTonightChanged);
  }

  Timer? _tonightRetry;
  int _tonightRetries = 0;

  /// Tonight can take a while the first time, while it reads the play
  /// history, and the usual draw stands in meanwhile. Asks again a little
  /// later, twice at most, so the bar comes round to tonight's picks.
  void _retryTonightIfMissed(List<MediaBarSlideItem> items) {
    if (_prefs.get(UserPreferences.mediaBarSourceType) !=
        UserPreferences.mediaBarSourceTonight) {
      return;
    }
    if (items.any((item) => item.kicker != null)) {
      _tonightRetries = 0;
      return;
    }
    if (_tonightRetries >= 2) return;
    _tonightRetries++;
    _tonightRetry?.cancel();
    _tonightRetry = Timer(const Duration(seconds: 30), () => load(force: true));
  }

  /// A new evening described: the Tonight slides change with it.
  void _onTonightChanged() {
    if (_prefs.get(UserPreferences.mediaBarSourceType) ==
        UserPreferences.mediaBarSourceTonight) {
      load(force: true);
    }
  }

  void _onPrefsChanged() {
    final mode = UserPreferences.normalizeMediaBarMode(
      _prefs.get(UserPreferences.mediaBarMode),
    );
    final contentType = _prefs.get(UserPreferences.mediaBarContentType);
    final itemCount = _prefs.get(UserPreferences.mediaBarItemCount);
    final source = _prefs.get(UserPreferences.mediaBarSourceType);

    if (mode != _lastMode ||
        contentType != _lastContentType ||
        itemCount != _lastItemCount ||
        source != _lastSource) {
      _lastMode = mode;
      _lastContentType = contentType;
      _lastItemCount = itemCount;
      _lastSource = source;
      _tonightRetries = 0;
      load(force: true);
    }
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    _tonightRetry?.cancel();
    TonightService.instance.answersChanged.removeListener(_onTonightChanged);
    super.dispose();
  }

  Future<void> load({
    BuildContext? context,
    bool preserveCurrent = true,
    bool force = false,
  }) async {
    if (_state is! MediaBarLoading && !force) return;
    if (_isLoading) return;
    _isLoading = true;
    final loadGeneration = ++_loadGeneration;
    final previousReady = _state is MediaBarReady
        ? _state as MediaBarReady
        : null;
    _ratings.clear();
    _bookshelfDetails.clear();
    _bookshelfDetailInFlight.clear();
    _galleryDetails.clear();
    _galleryDetailInFlight.clear();
    _ratingsInFlight.clear();
    if (!preserveCurrent || previousReady == null) {
      _state = const MediaBarLoading();
      notifyListeners();
    }

    try {
      var fallback = previousReady;
      if (!_triedCache && previousReady == null) {
        _triedCache = true;
        final mode = _prefs.get(UserPreferences.mediaBarMode);
        if (UserPreferences.isMediaBarModeEnabled(mode)) {
          final cached = await _cache.read(_cacheKey());
          if (cached != null &&
              loadGeneration == _loadGeneration &&
              _state is MediaBarLoading) {
            fallback = MediaBarReady(cached);
            _state = fallback;
            StartupTimeline.mark('Bandeau affiché (mémoire)');
            notifyListeners();
          }
        }
      }

      final nextState = await _repository.loadItems();
      if (loadGeneration != _loadGeneration) return;
      StartupTimeline.mark('Bandeau à jour');
      if (nextState is MediaBarReady) {
        unawaited(_cache.write(_cacheKey(), nextState.items));
      }
      if (nextState is MediaBarError && fallback != null) {
        _state = fallback;
        notifyListeners();
        return;
      }

      if (nextState is MediaBarError &&
          previousReady != null &&
          preserveCurrent) {
        _state = previousReady;
      } else {
        _state = nextState;
      }

      notifyListeners();

      if (_state is MediaBarReady) {
        _loadRatings((_state as MediaBarReady).items);
        _retryTonightIfMissed((_state as MediaBarReady).items);
      }
    } finally {
      _isLoading = false;
    }
  }

  Future<void> _loadRatings(List<MediaBarSlideItem> items) async {
    if (!_prefs.get(UserPreferences.enableAdditionalRatings)) return;

    await Future.wait(
      items.map((item) async {
        if (item.tmdbId == null) return;
        await _loadItemRatings(item);
        if (_ratings.containsKey(item.itemId)) {
          notifyListeners();
        }
      }),
    );
  }

  Future<void> _loadItemRatings(MediaBarSlideItem item) async {
    try {
      final tmdbId = await _mdbListRepository.resolveTmdbId(
        itemId: item.itemId,
        serverId: null,
        knownTmdbId: item.tmdbId,
      );
      if (tmdbId == null) return;
      final result = await _mdbListRepository.getRatings(
        tmdbId: tmdbId,
        mediaType: item.itemType,
      );
      if (result != null && result.isNotEmpty) {
        _ratings[item.itemId] = result;
      }
    } catch (_) {}
  }
}
