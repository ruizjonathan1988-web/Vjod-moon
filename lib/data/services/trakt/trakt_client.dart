import 'package:dio/dio.dart';

/// The id Trakt gave this app. Like any client id it travels with every
/// request, so it is public by nature. The app signs viewers in without a
/// client secret, so Trakt issued none.
const traktClientId = 'TCAqoSzejS8EETqVZUEc3c0RhsSgxYcM-HYt0_vcHpE';

/// A chart Trakt keeps without any account, built from what its members
/// scrobble, so it follows what people really watch.
enum TraktChart {
  /// The most watched over the last seven days.
  watchedWeekly('watched/weekly'),

  /// What is being watched right now.
  trending('trending');

  const TraktChart(this.path);

  final String path;
}

/// What to show the viewer so they approve the app on Trakt.
class TraktDeviceCode {
  const TraktDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.expiresIn,
    required this.interval,
  });

  factory TraktDeviceCode.fromJson(Map<dynamic, dynamic> json) =>
      TraktDeviceCode(
        deviceCode: json['device_code'] as String,
        userCode: json['user_code'] as String,
        verificationUrl: json['verification_url'] as String,
        expiresIn: Duration(seconds: json['expires_in'] as int),
        interval: Duration(seconds: json['interval'] as int),
      );

  final String deviceCode;

  /// The code the viewer types on [verificationUrl].
  final String userCode;
  final String verificationUrl;
  final Duration expiresIn;

  /// How long to wait between two checks.
  final Duration interval;
}

/// The keys to the viewer's Trakt account.
class TraktTokens {
  const TraktTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory TraktTokens.fromJson(Map<dynamic, dynamic> json) {
    final created = json['created_at'];
    return TraktTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: (created is int
              ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
              : DateTime.now())
          .add(Duration(seconds: json['expires_in'] as int)),
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}

/// Why linking an account stopped.
enum TraktAuthFailure {
  /// The code ran out before the viewer approved it.
  expired,

  /// The viewer turned the app down on Trakt.
  denied,

  /// Trakt refused the code or the app, or answered something unexpected.
  refused,
}

class TraktAuthException implements Exception {
  const TraktAuthException(this.reason);

  final TraktAuthFailure reason;

  @override
  String toString() => 'TraktAuthException(${reason.name})';
}

/// The Trakt API: the public charts, and what a linked account allows.
class TraktClient {
  TraktClient({Dio? dio, String clientId = traktClientId})
    : _clientId = clientId,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.trakt.tv',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'Content-Type': 'application/json',
                'trakt-api-version': '2',
                'trakt-api-key': clientId,
              },
            ),
          );

  final String _clientId;
  final Dio _dio;

  /// The TMDB ids of [chart] for [mediaType] (`movie` or `tv`), best first.
  Future<List<int>> chart(
    TraktChart chart,
    String mediaType, {
    int limit = 20,
  }) async {
    final response = await _dio.get<Object?>(
      '/${_kind(mediaType)}/${chart.path}',
      queryParameters: {'limit': limit},
    );
    return parseTraktTitles(response.data, mediaType: mediaType);
  }

  /// Starts linking an account: a code for the viewer to type on Trakt.
  Future<TraktDeviceCode> deviceCode() async {
    final response = await _dio.post<Object?>(
      '/oauth/device/code',
      data: {'client_id': _clientId},
    );
    return TraktDeviceCode.fromJson(response.data! as Map);
  }

  /// The tokens once the viewer approved [deviceCode], null while Trakt is
  /// still waiting for them.
  Future<TraktTokens?> deviceToken(String deviceCode) async {
    final response = await _dio.post<Object?>(
      '/oauth/device/token',
      data: {'code': deviceCode, 'client_id': _clientId},
      options: Options(validateStatus: (_) => true),
    );
    return switch (response.statusCode) {
      200 => TraktTokens.fromJson(response.data! as Map),
      // Not approved yet, or asked too soon.
      400 || 429 => null,
      410 => throw const TraktAuthException(TraktAuthFailure.expired),
      418 => throw const TraktAuthException(TraktAuthFailure.denied),
      _ => throw const TraktAuthException(TraktAuthFailure.refused),
    };
  }

  /// New tokens for the ones [refreshToken] came with. The old refresh
  /// token stops working.
  Future<TraktTokens> refresh(String refreshToken) async {
    final response = await _dio.post<Object?>(
      '/oauth/token',
      data: {
        'refresh_token': refreshToken,
        'client_id': _clientId,
        'grant_type': 'refresh_token',
      },
    );
    return TraktTokens.fromJson(response.data! as Map);
  }

  /// The name of the account [accessToken] belongs to.
  Future<String?> username(String accessToken) async {
    final response = await _dio.get<Object?>(
      '/users/settings',
      options: _signedIn(accessToken),
    );
    final user = response.data is Map ? (response.data as Map)['user'] : null;
    final name = user is Map ? user['username'] : null;
    return name is String ? name : null;
  }

  /// The TMDB ids Trakt recommends to the account for [mediaType], from all
  /// it watched, best first. What the library already holds is left out.
  Future<List<int>> recommendations(
    String mediaType,
    String accessToken, {
    int limit = 20,
  }) async {
    final response = await _dio.get<Object?>(
      '/recommendations/${_kind(mediaType)}',
      queryParameters: {'limit': limit, 'ignore_collected': 'true'},
      options: _signedIn(accessToken),
    );
    return parseTraktTitles(response.data, mediaType: mediaType);
  }

  /// The TMDB ids Trakt's members tie to the title [tmdbId], closest first.
  /// Public: no account needed. Empty when Trakt doesn't know the title.
  Future<List<int>> related(
    String mediaType,
    int tmdbId, {
    int limit = 15,
  }) {
    final key = '$mediaType:$tmdbId';
    return _related.putIfAbsent(
      key,
      () => _fetchRelated(mediaType, tmdbId, limit: limit)
          .timeout(const Duration(seconds: 4))
          .catchError((Object _) {
            _related.remove(key);
            return const <int>[];
          }),
    );
  }

  final Map<String, Future<List<int>>> _related = {};

  Future<List<int>> _fetchRelated(
    String mediaType,
    int tmdbId, {
    int limit = 15,
  }) async {
    final type = mediaType == 'tv' ? 'show' : 'movie';
    final search = await _dio.get<Object?>(
      '/search/tmdb/$tmdbId',
      queryParameters: {'type': type},
    );
    int? traktId;
    final hits = search.data;
    if (hits is List) {
      for (final hit in hits) {
        final title = hit is Map ? hit[type] : null;
        final ids = title is Map ? title['ids'] : null;
        final id = ids is Map ? ids['trakt'] : null;
        if (id is int) {
          traktId = id;
          break;
        }
      }
    }
    if (traktId == null) return const [];
    final response = await _dio.get<Object?>(
      '/${_kind(mediaType)}/$traktId/related',
      queryParameters: {'limit': limit},
    );
    return parseTraktTitles(response.data, mediaType: mediaType);
  }

  static String _kind(String mediaType) =>
      mediaType == 'tv' ? 'shows' : 'movies';

  static Options _signedIn(String accessToken) =>
      Options(headers: {'Authorization': 'Bearer $accessToken'});
}

/// The TMDB ids in a list of titles from Trakt, in order. A chart wraps each
/// title under `movie` or `show`, a recommendation list doesn't; a title
/// Trakt could not match to TMDB is skipped.
List<int> parseTraktTitles(Object? json, {required String mediaType}) {
  if (json is! List) return const [];
  final key = mediaType == 'tv' ? 'show' : 'movie';
  final ids = <int>[];
  for (final entry in json) {
    if (entry is! Map) continue;
    final title = entry.containsKey(key) ? entry[key] : entry;
    final tmdb = title is Map && title['ids'] is Map
        ? (title['ids'] as Map)['tmdb']
        : null;
    if (tmdb is int && !ids.contains(tmdb)) ids.add(tmdb);
  }
  return ids;
}
