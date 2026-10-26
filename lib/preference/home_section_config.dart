import 'dart:convert';

import 'package:collection/collection.dart';

import 'preference_constants.dart';

/// Categorizes a [HomeSectionConfig].
///
/// `builtin` entries map to a [HomeSectionType] handled natively by the app.
/// `pluginDynamic` entries are dynamic rows discovered from a third-party
/// Jellyfin plugin and are scoped to a specific server. The originating
/// plugin is identified by [HomeSectionPluginSource].
enum HomeSectionKind {
  builtin('builtin'),
  pluginDynamic('pluginDynamic');

  const HomeSectionKind(this.serializedName);
  final String serializedName;

  static HomeSectionKind fromSerialized(String? value) {
    for (final v in HomeSectionKind.values) {
      if (v.serializedName == value) return v;
    }
    return HomeSectionKind.builtin;
  }
}

/// Identifies which third-party plugin produced a `pluginDynamic` entry so
/// row loading can dispatch to the correct backend.
enum HomeSectionPluginSource {
  collections('collections'),

  genres('genres'),

  playlists('playlists'),

  custom('custom'),

  /// A slider an admin set up on Seerr's discover page.
  seerr('seerr');

  const HomeSectionPluginSource(this.serializedName);
  final String serializedName;

  static HomeSectionPluginSource fromSerialized(String? value) {
    for (final v in HomeSectionPluginSource.values) {
      if (v.serializedName == value) return v;
    }
    return HomeSectionPluginSource.collections;
  }
}

class HomeSectionConfig {
  final HomeSectionKind kind;
  final HomeSectionType type;
  final bool enabled;
  final int order;

  // pluginDynamic-only fields. Always null for builtin entries.
  final String? serverId;
  final String? pluginSection;
  final String? pluginAdditionalData;
  final String? pluginDisplayText;
  final HomeSectionPluginSource pluginSource;

  const HomeSectionConfig({
    this.kind = HomeSectionKind.builtin,
    this.type = HomeSectionType.none,
    this.enabled = true,
    this.order = 0,
    this.serverId,
    this.pluginSection,
    this.pluginAdditionalData,
    this.pluginDisplayText,
    this.pluginSource = HomeSectionPluginSource.collections,
  });

  factory HomeSectionConfig.pluginDynamic({
    required String serverId,
    required String pluginSection,
    String? pluginAdditionalData,
    String? pluginDisplayText,
    bool enabled = true,
    int order = 0,
    HomeSectionPluginSource pluginSource = HomeSectionPluginSource.collections,
  }) => HomeSectionConfig(
    kind: HomeSectionKind.pluginDynamic,
    type: HomeSectionType.none,
    enabled: enabled,
    order: order,
    serverId: serverId,
    pluginSection: pluginSection,
    pluginAdditionalData: pluginAdditionalData,
    pluginDisplayText: pluginDisplayText,
    pluginSource: pluginSource,
  );

  factory HomeSectionConfig.fromJson(Map<String, dynamic> json) {
    final kindRaw = json['kind'] as String?;
    final kind = kindRaw == null
        ? HomeSectionKind.builtin
        : HomeSectionKind.fromSerialized(kindRaw);
    final typeName = json['type'] as String? ?? 'none';
    final pluginSource = HomeSectionPluginSource.fromSerialized(
      json['pluginSource'] as String?,
    );
    return HomeSectionConfig(
      kind: kind,
      type: HomeSectionType.fromSerialized(typeName),
      enabled: json['enabled'] as bool? ?? true,
      order: json['order'] as int? ?? 0,
      serverId: _normalizedServerId(json['serverId']?.toString(), pluginSource),
      pluginSection: json['pluginSection'] as String?,
      pluginAdditionalData: json['pluginAdditionalData'] as String?,
      pluginDisplayText: json['pluginDisplayText'] as String?,
      pluginSource: pluginSource,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': type.serializedName,
      'enabled': enabled,
      'order': order,
    };
    if (kind != HomeSectionKind.builtin) {
      json['kind'] = kind.serializedName;
      json['pluginSource'] = pluginSource.serializedName;
      if (serverId != null) json['serverId'] = serverId;
      if (pluginSection != null) json['pluginSection'] = pluginSection;
      if (pluginAdditionalData != null) {
        json['pluginAdditionalData'] = pluginAdditionalData;
      }
      if (pluginDisplayText != null) {
        json['pluginDisplayText'] = pluginDisplayText;
      }
    }
    return json;
  }

  HomeSectionConfig copyWith({
    HomeSectionKind? kind,
    HomeSectionType? type,
    bool? enabled,
    int? order,
    String? serverId,
    String? pluginSection,
    String? pluginAdditionalData,
    String? pluginDisplayText,
    HomeSectionPluginSource? pluginSource,
  }) => HomeSectionConfig(
    kind: kind ?? this.kind,
    type: type ?? this.type,
    enabled: enabled ?? this.enabled,
    order: order ?? this.order,
    serverId: serverId ?? this.serverId,
    pluginSection: pluginSection ?? this.pluginSection,
    pluginAdditionalData: pluginAdditionalData ?? this.pluginAdditionalData,
    pluginDisplayText: pluginDisplayText ?? this.pluginDisplayText,
    pluginSource: pluginSource ?? this.pluginSource,
  );

  /// Custom rows belong to no server, and an empty serverId coming back from a saved
  /// layout would give the same row a second identity, so both ends use this placeholder.
  static String? _normalizedServerId(
    String? serverId,
    HomeSectionPluginSource source,
  ) =>
      (serverId == null || serverId.isEmpty) &&
              source == HomeSectionPluginSource.custom
          ? 'custom'
          : serverId;

  /// Stable identifier suitable for use as a row id / list key. Plugin
  /// entries combine the originating plugin, server, section and additional
  /// data so multiple instances of the same section can coexist.
  String get stableId {
    if (kind == HomeSectionKind.pluginDynamic) {
      final effectiveServerId =
          _normalizedServerId(serverId, pluginSource) ?? '';
      return 'pluginDynamic:${pluginSource.serializedName}:$effectiveServerId:${pluginSection ?? ''}:${pluginAdditionalData ?? ''}';
    }
    return 'builtin:${type.serializedName}';
  }

  bool get isBuiltin => kind == HomeSectionKind.builtin;
  bool get isPluginDynamic => kind == HomeSectionKind.pluginDynamic;

  /// The VJOD home: what was left half watched first, the Top 10 (films and
  /// series in one row), suggestions and French cinema. Tonight's picks sit
  /// above in the media bar. Every other row is here, switched off, to turn
  /// on in the settings.
  static List<HomeSectionConfig> defaults() => const [
    HomeSectionConfig(
      type: HomeSectionType.vjodMood,
      enabled: true,
      order: 0,
    ),
    HomeSectionConfig(
      type: HomeSectionType.resume,
      enabled: true,
      order: 1,
    ),
    HomeSectionConfig(
      type: HomeSectionType.nextUp,
      enabled: true,
      order: 2,
    ),
    // The recommended layout, also what the reset button brings back: the
    // evening's mood under the banner, then what to resume and the
    // requests that came in (the two rows looked at most), then a dozen
    // rows that alternate between personal picks, what's new, the charts
    // and a few moods. The other moods wait in Explorer.
    HomeSectionConfig(
      type: HomeSectionType.vjodUnwatchedGems,
      enabled: true,
      order: 6,
    ),
    HomeSectionConfig(
      type: HomeSectionType.top10Movies,
      enabled: true,
      order: 7,
    ),
    HomeSectionConfig(
      type: HomeSectionType.vjodMindBenders,
      enabled: false,
      order: 5,
    ),
    HomeSectionConfig(
      type: HomeSectionType.vjodThemeOfDay,
      enabled: true,
      order: 10,
    ),
    HomeSectionConfig(
      type: HomeSectionType.vjodMiniSeries,
      enabled: true,
      order: 14,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrForYou,
      enabled: true,
      order: 4,
    ),
    HomeSectionConfig(
      type: HomeSectionType.vjodShortGems,
      enabled: true,
      order: 13,
    ),
    HomeSectionConfig(
      type: HomeSectionType.vjodFeelGood,
      enabled: false,
      order: 10,
    ),
    HomeSectionConfig(
      type: HomeSectionType.vjodEpic,
      enabled: false,
      order: 11,
    ),
    HomeSectionConfig(
      type: HomeSectionType.vjodOutsideHabits,
      enabled: true,
      order: 16,
    ),
    HomeSectionConfig(
      type: HomeSectionType.vjodBinge,
      enabled: false,
      order: 13,
    ),
    HomeSectionConfig(
      type: HomeSectionType.frenchMovies,
      enabled: true,
      order: 12,
    ),
    HomeSectionConfig(
      type: HomeSectionType.top10Series,
      enabled: false,
      order: 5,
    ),
    HomeSectionConfig(
      type: HomeSectionType.frenchSeries,
      enabled: false,
      order: 5,
    ),
    HomeSectionConfig(
      type: HomeSectionType.frenchClassics,
      enabled: false,
      order: 5,
    ),
    HomeSectionConfig(
      type: HomeSectionType.libraryTilesSmall,
      enabled: false,
      order: 5,
    ),
    HomeSectionConfig(
      type: HomeSectionType.surprise,
      enabled: false,
      order: 5,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrMyRequests,
      enabled: true,
      order: 3,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrBecause,
      enabled: true,
      order: 8,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrSagas,
      enabled: true,
      order: 9,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrGems,
      enabled: false,
      order: 5,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrUpcoming,
      enabled: false,
      order: 5,
    ),
    HomeSectionConfig(
      type: HomeSectionType.familyNight,
      enabled: false,
      order: 5,
    ),
    HomeSectionConfig(
      type: HomeSectionType.latestMedia,
      enabled: true,
      order: 5,
    ),
    HomeSectionConfig(
      type: HomeSectionType.recentlyReleased,
      enabled: false,
      order: 4,
    ),
    HomeSectionConfig(
      type: HomeSectionType.liveTv,
      enabled: false,
      order: 5,
    ),
    HomeSectionConfig(
      type: HomeSectionType.libraryButtons,
      enabled: false,
      order: 6,
    ),
    HomeSectionConfig(
      type: HomeSectionType.resumeAudio,
      enabled: false,
      order: 7,
    ),
    HomeSectionConfig(
      type: HomeSectionType.resumeBook,
      enabled: false,
      order: 8,
    ),
    HomeSectionConfig(
      type: HomeSectionType.activeRecordings,
      enabled: false,
      order: 9,
    ),
    HomeSectionConfig(
      type: HomeSectionType.collections,
      enabled: false,
      order: 10,
    ),
    HomeSectionConfig(
      type: HomeSectionType.favoriteMovies,
      enabled: false,
      order: 11,
    ),
    HomeSectionConfig(
      type: HomeSectionType.favoriteSeries,
      enabled: false,
      order: 12,
    ),
    HomeSectionConfig(
      type: HomeSectionType.favoriteEpisodes,
      enabled: false,
      order: 13,
    ),
    HomeSectionConfig(
      type: HomeSectionType.favoritePeople,
      enabled: false,
      order: 14,
    ),
    HomeSectionConfig(
      type: HomeSectionType.favoriteArtists,
      enabled: false,
      order: 15,
    ),
    HomeSectionConfig(
      type: HomeSectionType.favoriteMusicVideos,
      enabled: false,
      order: 16,
    ),
    HomeSectionConfig(
      type: HomeSectionType.favoriteAlbums,
      enabled: false,
      order: 17,
    ),
    HomeSectionConfig(
      type: HomeSectionType.favoriteSongs,
      enabled: false,
      order: 18,
    ),
    HomeSectionConfig(
      type: HomeSectionType.genres,
      enabled: false,
      order: 19,
    ),
    HomeSectionConfig(
      type: HomeSectionType.playlists,
      enabled: false,
      order: 20,
    ),
    HomeSectionConfig(
      type: HomeSectionType.studios,
      enabled: false,
      order: 21,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrShortcuts,
      enabled: false,
      order: 22,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrRecentRequests,
      enabled: false,
      order: 21,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrWatchlist,
      enabled: true,
      order: 11,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrRecentlyAdded,
      enabled: false,
      order: 23,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrPopularMovies,
      enabled: false,
      order: 24,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrUpcomingMovies,
      enabled: false,
      order: 25,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrPopularSeries,
      enabled: false,
      order: 26,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrUpcomingSeries,
      enabled: false,
      order: 27,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrTrending,
      enabled: false,
      order: 28,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrMovieGenres,
      enabled: false,
      order: 29,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrStudios,
      enabled: false,
      order: 30,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrSeriesGenres,
      enabled: false,
      order: 31,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seerrNetworks,
      enabled: false,
      order: 32,
    ),
    HomeSectionConfig(
      type: HomeSectionType.radarrCalendar,
      enabled: false,
      order: 38,
    ),
    HomeSectionConfig(
      type: HomeSectionType.sonarrCalendar,
      enabled: false,
      order: 39,
    ),
    // These carry a toggle preference too, but they still need a section entry.
    // Without one there was nowhere for turning the row off to persist, so the
    // next sync kept bringing it back.
    HomeSectionConfig(
      type: HomeSectionType.sinceYouWatched1,
      enabled: false,
      order: 40,
    ),
    HomeSectionConfig(
      type: HomeSectionType.sinceYouWatched2,
      enabled: false,
      order: 41,
    ),
    HomeSectionConfig(
      type: HomeSectionType.sinceYouWatched3,
      enabled: false,
      order: 42,
    ),
    HomeSectionConfig(
      type: HomeSectionType.sinceYouWatched4,
      enabled: false,
      order: 43,
    ),
    HomeSectionConfig(
      type: HomeSectionType.sinceYouWatched5,
      enabled: false,
      order: 44,
    ),
    HomeSectionConfig(
      type: HomeSectionType.rewatch,
      enabled: false,
      order: 45,
    ),
    HomeSectionConfig(
      type: HomeSectionType.seasonal,
      enabled: true,
      order: 15,
    ),
    HomeSectionConfig(
      type: HomeSectionType.onNow,
      enabled: false,
      order: 47,
    ),
  ];

  static bool isSupportedJson(Map<String, dynamic> json) {
    if (json['kind'] != HomeSectionKind.pluginDynamic.serializedName) return true;
    final source = json['pluginSource'] as String?;
    return HomeSectionPluginSource.values.any((s) => s.serializedName == source);
  }

  static List<HomeSectionConfig> fromJsonString(String jsonString) {
    if (jsonString.isEmpty) return defaults();
    try {
      final list = jsonDecode(jsonString) as List;
      final parsed = <HomeSectionConfig>[];
      for (final e in list) {
        if (e is Map<String, dynamic> && isSupportedJson(e)) {
          final cfg = HomeSectionConfig.fromJson(e);
          if (cfg.isBuiltin && cfg.type == HomeSectionType.none) {
            continue;
          }
          parsed.add(cfg);
        }
      }
      return _appendMissingBuiltins(parsed);
    } catch (_) {
      return defaults();
    }
  }

  /// Adds any built-in sections missing from a user's saved config, like the
  /// Seerr watchlist, so they show up without needing a reset. New sections
  /// keep their default enabled state and go at the end to keep the user's
  /// existing order.
  static List<HomeSectionConfig> _appendMissingBuiltins(
    List<HomeSectionConfig> parsed,
  ) {
    final presentTypes = parsed
        .where((c) => c.isBuiltin)
        .map((c) => c.type)
        .toSet();
    var merged = List<HomeSectionConfig>.of(parsed);
    for (final def in defaults()) {
      if (!def.isBuiltin || presentTypes.contains(def.type)) continue;
      if (def.type == HomeSectionType.vjodMood) {
        // The mood sits right under the banner, above everything, without
        // moving what the viewer placed.
        final first = merged.fold<int>(1, (m, c) => c.order < m ? c.order : m);
        merged.add(def.copyWith(order: first - 1));
        continue;
      }
      final leader = _followsSection[def.type];
      final leaderConfig = leader == null
          ? null
          : merged.firstWhereOrNull((c) => c.isBuiltin && c.type == leader);
      if (leaderConfig == null) {
        final last = merged.fold<int>(-1, (m, c) => c.order > m ? c.order : m);
        merged.add(def.copyWith(order: last + 1));
      } else {
        merged = _insertAfter(merged, leaderConfig, def);
      }
    }
    return merged;
  }

  /// New sections that belong right under one the viewer already placed,
  /// and take its on or off.
  static const _followsSection = {
    HomeSectionType.top10Series: HomeSectionType.top10Movies,
    HomeSectionType.frenchMovies: HomeSectionType.top10Series,
    HomeSectionType.frenchSeries: HomeSectionType.frenchMovies,
    HomeSectionType.frenchClassics: HomeSectionType.frenchSeries,
    HomeSectionType.seerrUpcoming: HomeSectionType.seerrGems,
    HomeSectionType.vjodUnwatchedGems: HomeSectionType.nextUp,
    HomeSectionType.vjodMindBenders: HomeSectionType.top10Movies,
    HomeSectionType.vjodThemeOfDay: HomeSectionType.vjodMindBenders,
    HomeSectionType.vjodMiniSeries: HomeSectionType.vjodThemeOfDay,
    HomeSectionType.vjodShortGems: HomeSectionType.seerrForYou,
    HomeSectionType.vjodFeelGood: HomeSectionType.vjodShortGems,
    HomeSectionType.vjodEpic: HomeSectionType.vjodFeelGood,
    HomeSectionType.vjodOutsideHabits: HomeSectionType.vjodEpic,
    HomeSectionType.vjodBinge: HomeSectionType.vjodOutsideHabits,
  };

  /// [config] placed right after [leader], everything below moved down one.
  static List<HomeSectionConfig> _insertAfter(
    List<HomeSectionConfig> configs,
    HomeSectionConfig leader,
    HomeSectionConfig config,
  ) => [
    for (final c in configs)
      c.order > leader.order ? c.copyWith(order: c.order + 1) : c,
    // VJOD's rows come on whatever their neighbour does: they are the point.
    config.copyWith(
      order: leader.order + 1,
      enabled: config.type.isVjodRow ? config.enabled : leader.enabled,
    ),
  ];

  static String toJsonString(List<HomeSectionConfig> configs) =>
      jsonEncode(configs.map((c) => c.toJson()).toList());
}
