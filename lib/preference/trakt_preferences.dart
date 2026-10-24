import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../auth/repositories/session_repository.dart';

/// The Trakt account linked on this device, one per server user.
class TraktPreferences {
  TraktPreferences(this._store, this._session);

  final PreferenceStore _store;
  final SessionRepository _session;

  String _userKey(String key) => 'trakt_${key}_${_session.activeUserId ?? ''}';

  String get accessToken => _store.getString(_userKey('access_token')) ?? '';
  String get refreshToken => _store.getString(_userKey('refresh_token')) ?? '';

  /// When [accessToken] stops working, or null when none is stored.
  DateTime? get expiresAt {
    final ms = _store.getInt(_userKey('expires_at'));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// The account's name on Trakt, to show which one is linked.
  String get username => _store.getString(_userKey('username')) ?? '';

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
  }) async {
    await _store.setString(_userKey('access_token'), accessToken);
    await _store.setString(_userKey('refresh_token'), refreshToken);
    await _store.setInt(
      _userKey('expires_at'),
      expiresAt.millisecondsSinceEpoch,
    );
  }

  Future<void> setUsername(String value) =>
      _store.setString(_userKey('username'), value);

  Future<void> clear() async {
    for (final key in ['access_token', 'refresh_token', 'expires_at', 'username']) {
      await _store.remove(_userKey(key));
    }
  }
}
