import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../auth/repositories/session_repository.dart';
import 'home_section_config.dart';
import 'preference_constants.dart';
import 'seerr_row_config.dart';

class SeerrPreferences {
  final PreferenceStore _store;
  final SessionRepository _session;

  SeerrPreferences(this._store, this._session);

  String _userKey(String key) {
    final uid = _session.activeUserId ?? '';
    return 'seerr_${key}_$uid';
  }

    static String normalizeVariant(String? value) {
        final normalized = value?.trim().toLowerCase() ?? '';
        if (normalized == 'seerr' || normalized == 'jelly') {
            return 'seerr';
        }
        return 'seerr';
    }

  bool get enabled => _store.getBool(_userKey('enabled')) ?? false;
  Future<void> setEnabled(bool value) => _store.setBool(_userKey('enabled'), value);

  String get serverUrl => _store.getString(_userKey('server_url')) ?? '';
  Future<void> setServerUrl(String value) => _store.setString(_userKey('server_url'), value);

  String get authMethod => _store.getString(_userKey('auth_method')) ?? 'jellyfin';
  Future<void> setAuthMethod(String value) => _store.setString(_userKey('auth_method'), value);

  String get apiKey => _store.getString(_userKey('api_key')) ?? '';
  Future<void> setApiKey(String value) => _store.setString(_userKey('api_key'), value);

  bool get moonfinMode => _store.getBool(_userKey('moonfin_mode')) ?? false;
  Future<void> setMoonfinMode(bool value) => _store.setBool(_userKey('moonfin_mode'), value);

  String get moonfinDisplayName => _store.getString(_userKey('moonfin_display_name')) ?? '';
  Future<void> setMoonfinDisplayName(String value) =>
      _store.setString(_userKey('moonfin_display_name'), value);

  /// Label for the Seerr integration: the moonbase display name when one is set,
  /// otherwise [fallback] (typically l10n.seerr).
  String labelOrDefault(String fallback) {
    final name = moonfinDisplayName.trim();
    return name.isNotEmpty ? name : fallback;
  }

  String get moonfinVariant => normalizeVariant(_store.getString(_userKey('moonfin_variant')));
  bool get isSeerrVariant => moonfinVariant == 'seerr';
  Future<void> setMoonfinVariant(String value) =>
      _store.setString(_userKey('moonfin_variant'), normalizeVariant(value));

  String get moonfinUserId => _store.getString(_userKey('moonfin_user_id')) ?? '';
  Future<void> setMoonfinUserId(String value) =>
      _store.setString(_userKey('moonfin_user_id'), value);

  bool get lastConnectionSuccess =>
      _store.getBool(_userKey('last_connection_success')) ?? false;
  Future<void> setLastConnectionSuccess(bool value) =>
      _store.setBool(_userKey('last_connection_success'), value);

  bool get showInNavigation => _store.getBool(_userKey('show_in_navigation')) ?? true;
  Future<void> setShowInNavigation(bool value) =>
      _store.setBool(_userKey('show_in_navigation'), value);

  bool get showInToolbar => _store.getBool(_userKey('show_in_toolbar')) ?? true;
  Future<void> setShowInToolbar(bool value) =>
      _store.setBool(_userKey('show_in_toolbar'), value);

  String get requestsFilter => _store.getString(_userKey('requests_filter')) ?? '';
  Future<void> setRequestsFilter(String value) =>
      _store.setString(_userKey('requests_filter'), value);

  bool get showRequestStatus => _store.getBool(_userKey('show_request_status')) ?? true;
  Future<void> setShowRequestStatus(bool value) =>
      _store.setBool(_userKey('show_request_status'), value);

  /// The taste questionnaire's answers, as `TasteProfile.encode` wrote them.
  String? get tasteProfileJson => _store.getString(_userKey('taste_profile'));
  Future<void> setTasteProfileJson(String value) =>
      _store.setString(_userKey('taste_profile'), value);

  /// Titles and genres turned down, as `TasteFeedback.encode` wrote them.
  String? get tasteFeedbackJson => _store.getString(_userKey('taste_feedback'));
  Future<void> setTasteFeedbackJson(String value) =>
      _store.setString(_userKey('taste_feedback'), value);

  /// When the viewer was last asked about their taste, in milliseconds since
  /// the epoch, so the reminder comes back at a sane pace.
  int? get tastePromptedAt => _store.getInt(_userKey('taste_prompted_at'));
  Future<void> setTastePromptedAt(int value) =>
      _store.setInt(_userKey('taste_prompted_at'), value);

  /// Every sitting watched, as `EveningJournal.encode` wrote it.
  String? get tonightJournalJson =>
      _store.getString(_userKey('tonight_journal'));
  Future<void> setTonightJournalJson(String value) =>
      _store.setString(_userKey('tonight_journal'), value);

  /// Whether the journal was filled from the server's play history yet.
  bool get tonightBackfilled =>
      _store.getBool(_userKey('tonight_backfilled')) ?? false;
  Future<void> setTonightBackfilled(bool value) =>
      _store.setBool(_userKey('tonight_backfilled'), value);

  /// Whether VJOD shapes its rows to the viewer. On unless turned off.
  bool get vjodPersonalize =>
      _store.getBool(_userKey('vjod_personalize')) ?? true;
  Future<void> setVjodPersonalize(bool value) =>
      _store.setBool(_userKey('vjod_personalize'), value);

  /// Tonight's mood picked on Home, as `VjodMoodStore.write` wrote it.
  String? get vjodMood => _store.getString(_userKey('vjod_mood'));
  Future<void> setVjodMood(String value) =>
      _store.setString(_userKey('vjod_mood'), value);

  /// "J'ai aimé" and "Bof" given at the end credits, as `VjodVotes.encode`
  /// wrote them.
  String? get vjodVotesJson => _store.getString(_userKey('vjod_votes'));
  Future<void> setVjodVotesJson(String value) =>
      _store.setString(_userKey('vjod_votes'), value);

  /// This profile's saved TV sources (legal M3U/Xtream links), as
  /// `TvPlaylists.encode` wrote them. Each profile keeps its own.
  String? get vjodTvPlaylistsJson =>
      _store.getString(_userKey('vjod_tv_playlists'));
  Future<void> setVjodTvPlaylistsJson(String value) =>
      _store.setString(_userKey('vjod_tv_playlists'), value);

  /// Which external player the TV tab opens (a [TvApp] id). Empty means the
  /// default.
  String get vjodTvApp => _store.getString(_userKey('vjod_tv_app')) ?? '';
  Future<void> setVjodTvApp(String value) =>
      _store.setString(_userKey('vjod_tv_app'), value);

  /// Forgets what VJOD learned by itself: the journal of sittings, the
  /// "not interested", the votes and today's mood. The questionnaire's
  /// answers stay; they were given on purpose.
  Future<void> resetVjodLearning() async {
    await _store.setString(_userKey('tonight_journal'), '[]');
    // The journal stays empty rather than refilled from the server's history.
    await _store.setBool(_userKey('tonight_backfilled'), true);
    await _store.setString(_userKey('taste_feedback'), '');
    await _store.setString(_userKey('vjod_votes'), '');
    await _store.setString(_userKey('vjod_mood'), '');
  }

  /// The last answers given in the Tonight sheet.
  String? get tonightAnswersJson =>
      _store.getString(_userKey('tonight_answers'));
  Future<void> setTonightAnswersJson(String value) =>
      _store.setString(_userKey('tonight_answers'), value);

  /// What Tonight learned about how much each signal counts.
  String? get tonightWeightsJson =>
      _store.getString(_userKey('tonight_weights'));
  Future<void> setTonightWeightsJson(String value) =>
      _store.setString(_userKey('tonight_weights'), value);

  /// The last evening's picks, kept to learn from what came of them.
  String? get tonightSessionJson =>
      _store.getString(_userKey('tonight_session'));
  Future<void> setTonightSessionJson(String value) =>
      _store.setString(_userKey('tonight_session'), value);

  /// Titles turned down with "Another idea", and when.
  String? get tonightRejectionsJson =>
      _store.getString(_userKey('tonight_rejections'));
  Future<void> setTonightRejectionsJson(String value) =>
      _store.setString(_userKey('tonight_rejections'), value);

  /// Requests made from Tonight, to follow them until they land.
  String? get tonightPendingJson =>
      _store.getString(_userKey('tonight_pending'));
  Future<void> setTonightPendingJson(String value) =>
      _store.setString(_userKey('tonight_pending'), value);

  /// Sittings the monthly check-in already asked about.
  List<String> get tasteCheckInAsked =>
      _store.getStringList(_userKey('taste_checkin_asked')) ?? const [];
  Future<void> setTasteCheckInAsked(List<String> keys) =>
      _store.setStringList(_userKey('taste_checkin_asked'), keys);

  /// Requests already announced as ready, so each is announced once. Null
  /// until the first load, which only takes note of what is ready.
  List<String>? get announcedReadyRequests =>
      _store.getStringList(_userKey('announced_ready_requests'));
  Future<void> setAnnouncedReadyRequests(List<String> keys) =>
      _store.setStringList(_userKey('announced_ready_requests'), keys);

  bool get blockNsfw => _store.getBool(_userKey('block_nsfw')) ?? true;

  /// Whether the Top 10 rows rank the best rated releases of the last twelve
  /// months rather than this week's trends.
  bool get top10YearBest => _store.getBool(_userKey('top10_year_best')) ?? false;
  Future<void> setTop10YearBest(bool value) =>
      _store.setBool(_userKey('top10_year_best'), value);
  Future<void> setBlockNsfw(bool value) => _store.setBool(_userKey('block_nsfw'), value);

  bool get notifyOnNewRequests => _store.getBool(_userKey('notify_new_requests')) ?? true;
  Future<void> setNotifyOnNewRequests(bool value) =>
      _store.setBool(_userKey('notify_new_requests'), value);

  bool get notifyOnLibraryAdded => _store.getBool(_userKey('notify_library_added')) ?? true;
  Future<void> setNotifyOnLibraryAdded(bool value) =>
      _store.setBool(_userKey('notify_library_added'), value);

  bool get notifyOnIssues => _store.getBool(_userKey('notify_issues')) ?? true;
  Future<void> setNotifyOnIssues(bool value) =>
      _store.setBool(_userKey('notify_issues'), value);

  // Off by default: library churn (upgrades, re-scans) is noisy, and the
  // Seerr "library added" pref above already covers requested media.
  bool get notifyOnNewMedia =>
      _store.getBool(_userKey('notify_new_media')) ?? false;
  Future<void> setNotifyOnNewMedia(bool value) =>
      _store.setBool(_userKey('notify_new_media'), value);

  SeerrFetchLimit get fetchLimit {
    final stored = _store.getString(_userKey('fetch_limit'));
    if (stored == null || stored.isEmpty) return SeerrFetchLimit.medium;
    for (final v in SeerrFetchLimit.values) {
      if (v.name == stored) return v;
    }
    return SeerrFetchLimit.medium;
  }

  Future<void> setFetchLimit(SeerrFetchLimit value) =>
      _store.setString(_userKey('fetch_limit'), value.name);

  List<SeerrRowConfig> get rowsConfig =>
      SeerrRowConfig.fromJsonString(_store.getString(_userKey('rows_config')) ?? '');

  Future<void> setRowsConfig(List<SeerrRowConfig> value) =>
      _store.setString(_userKey('rows_config'), SeerrRowConfig.toJsonString(value));

  List<SeerrRowConfig> get homeRowsConfig {
    final raw = _store.getString(_userKey('home_rows_config'));
    if (raw != null && raw.isNotEmpty) {
      return SeerrRowConfig.fromJsonString(raw);
    }
    // Fall back to the old home_sections_config state when this has never been
    // saved, so upgrades keep the rows the user already chose.
    return _homeRowsConfigFromSections();
  }

  Future<void> setHomeRowsConfig(List<SeerrRowConfig> value) =>
      _store.setString(_userKey('home_rows_config'), SeerrRowConfig.toJsonString(value));

  List<SeerrRowConfig> _homeRowsConfigFromSections() {
    final sectionsJson = _store.getString('home_sections_config');
    if (sectionsJson == null || sectionsJson.isEmpty) {
      return SeerrRowConfig.defaults();
    }
    final sections = HomeSectionConfig.fromJsonString(sectionsJson);
    return SeerrRowConfig.defaults().map((row) {
      final idx = sections.indexWhere((s) => s.type == row.type.homeSectionType);
      return idx >= 0 ? row.copyWith(enabled: sections[idx].enabled) : row;
    }).toList();
  }

  bool isSeerrHomeRowEnabled(HomeSectionType type) {
    final seerrType = type.seerrRowType;
    if (seerrType == null || !enabled) return false;
    final config = homeRowsConfig.firstWhere(
      (c) => c.type == seerrType,
      orElse: () => SeerrRowConfig(type: seerrType, enabled: false, order: 0),
    );
    return config.enabled;
  }

  List<SeerrRowType> get activeRows {
    final configs = rowsConfig.where((c) => c.enabled).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return configs.map((c) => c.type).toList();
  }

  String get hdMovieProfileId => _store.getString(_userKey('hd_movie_profile_id')) ?? '';
  Future<void> setHdMovieProfileId(String value) =>
      _store.setString(_userKey('hd_movie_profile_id'), value);

  String get fourKMovieProfileId => _store.getString(_userKey('4k_movie_profile_id')) ?? '';
  Future<void> setFourKMovieProfileId(String value) =>
      _store.setString(_userKey('4k_movie_profile_id'), value);

  String get hdTvProfileId => _store.getString(_userKey('hd_tv_profile_id')) ?? '';
  Future<void> setHdTvProfileId(String value) =>
      _store.setString(_userKey('hd_tv_profile_id'), value);

  String get fourKTvProfileId => _store.getString(_userKey('4k_tv_profile_id')) ?? '';
  Future<void> setFourKTvProfileId(String value) =>
      _store.setString(_userKey('4k_tv_profile_id'), value);

  String get hdMovieRootFolderId => _store.getString(_userKey('hd_movie_root_folder_id')) ?? '';
  Future<void> setHdMovieRootFolderId(String value) =>
      _store.setString(_userKey('hd_movie_root_folder_id'), value);

  String get fourKMovieRootFolderId =>
      _store.getString(_userKey('4k_movie_root_folder_id')) ?? '';
  Future<void> setFourKMovieRootFolderId(String value) =>
      _store.setString(_userKey('4k_movie_root_folder_id'), value);

  String get hdTvRootFolderId => _store.getString(_userKey('hd_tv_root_folder_id')) ?? '';
  Future<void> setHdTvRootFolderId(String value) =>
      _store.setString(_userKey('hd_tv_root_folder_id'), value);

  String get fourKTvRootFolderId => _store.getString(_userKey('4k_tv_root_folder_id')) ?? '';
  Future<void> setFourKTvRootFolderId(String value) =>
      _store.setString(_userKey('4k_tv_root_folder_id'), value);

  String get hdMovieServerId => _store.getString(_userKey('hd_movie_server_id')) ?? '';
  Future<void> setHdMovieServerId(String value) =>
      _store.setString(_userKey('hd_movie_server_id'), value);

  String get fourKMovieServerId => _store.getString(_userKey('4k_movie_server_id')) ?? '';
  Future<void> setFourKMovieServerId(String value) =>
      _store.setString(_userKey('4k_movie_server_id'), value);

  String get hdTvServerId => _store.getString(_userKey('hd_tv_server_id')) ?? '';
  Future<void> setHdTvServerId(String value) =>
      _store.setString(_userKey('hd_tv_server_id'), value);

  String get fourKTvServerId => _store.getString(_userKey('4k_tv_server_id')) ?? '';
  Future<void> setFourKTvServerId(String value) =>
      _store.setString(_userKey('4k_tv_server_id'), value);

  Future<void> clearAll() async {
    final keys = [
      'enabled', 'server_url', 'auth_method', 'api_key',
      'moonfin_mode', 'moonfin_display_name', 'moonfin_variant', 'moonfin_user_id',
      'last_connection_success',
      'show_in_navigation', 'show_in_toolbar', 'show_request_status',
      'requests_filter',
      'block_nsfw', 'notify_new_requests', 'notify_library_added',
      'notify_issues', 'notify_new_media',
      'fetch_limit', 'rows_config', 'home_rows_config',
      'hd_movie_profile_id', '4k_movie_profile_id',
      'hd_tv_profile_id', '4k_tv_profile_id',
      'hd_movie_root_folder_id', '4k_movie_root_folder_id',
      'hd_tv_root_folder_id', '4k_tv_root_folder_id',
      'hd_movie_server_id', '4k_movie_server_id',
      'hd_tv_server_id', '4k_tv_server_id',
    ];
    for (final key in keys) {
      await _store.remove(_userKey(key));
    }
  }
}
