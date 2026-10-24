import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../preference/trakt_preferences.dart';
import 'trakt_client.dart';

/// The viewer's Trakt account on this device: linking it with a code, keeping
/// its tokens fresh, and what it recommends.
class TraktAccount extends ChangeNotifier {
  TraktAccount(this._client, this._prefs);

  final TraktClient _client;
  final TraktPreferences _prefs;

  /// Renewing early leaves room for a device that stays off a while.
  static const _renewAhead = Duration(days: 1);

  /// A renewal under way, shared so two callers don't both spend the same
  /// refresh token, which only works once.
  Future<String?>? _renewing;

  bool get isConnected => _prefs.refreshToken.isNotEmpty;

  /// The linked account's name on Trakt, empty when unknown.
  String get username => _prefs.username;

  /// Starts linking: the code to show the viewer.
  Future<TraktDeviceCode> startConnecting() => _client.deviceCode();

  /// Waits for the viewer to approve [code] on Trakt, checking as often as
  /// Trakt allows, then keeps the account. Returns false when [isCancelled]
  /// stopped it first; throws a [TraktAuthException] when Trakt turned it
  /// down or the code ran out.
  Future<bool> finishConnecting(
    TraktDeviceCode code, {
    required bool Function() isCancelled,
  }) async {
    final deadline = DateTime.now().add(code.expiresIn);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(code.interval);
      if (isCancelled()) return false;
      TraktTokens? tokens;
      try {
        tokens = await _client.deviceToken(code.deviceCode);
      } on DioException catch (e) {
        // A dropped connection: the next check may get through.
        debugPrint('[Trakt] Checking the code failed: ${e.type.name}');
        continue;
      }
      if (tokens == null) continue;
      if (isCancelled()) return false;
      await _save(tokens);
      try {
        await _prefs.setUsername(
          await _client.username(tokens.accessToken) ?? '',
        );
      } catch (e) {
        // The name is only shown; the account works without it.
        debugPrint('[Trakt] Could not read the account name: $e');
      }
      notifyListeners();
      return true;
    }
    throw const TraktAuthException(TraktAuthFailure.expired);
  }

  Future<void> disconnect() async {
    await _prefs.clear();
    notifyListeners();
  }

  /// The TMDB ids Trakt recommends for [mediaType], nothing when no account
  /// is linked.
  Future<List<int>> recommendations(String mediaType) async {
    final token = await _accessToken();
    if (token == null) return const [];
    return _client.recommendations(mediaType, token);
  }

  /// A token that works, renewed first when it is about to run out. Null
  /// when no account is linked, or when Trakt no longer accepts it, in which
  /// case the account is let go so the settings offer to link it again.
  Future<String?> _accessToken() async {
    if (!isConnected) return null;
    final expiresAt = _prefs.expiresAt;
    if (expiresAt != null &&
        DateTime.now().add(_renewAhead).isBefore(expiresAt)) {
      return _prefs.accessToken;
    }
    return _renewing ??= _renew().whenComplete(() => _renewing = null);
  }

  Future<String?> _renew() async {
    try {
      final tokens = await _client.refresh(_prefs.refreshToken);
      await _save(tokens);
      return tokens.accessToken;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400 || status == 401) {
        debugPrint('[Trakt] The account was let go: $status');
        await disconnect();
        return null;
      }
      // Trakt is out of reach for now: the old token may still do.
      final expiresAt = _prefs.expiresAt;
      return expiresAt != null && DateTime.now().isBefore(expiresAt)
          ? _prefs.accessToken
          : null;
    }
  }

  Future<void> _save(TraktTokens tokens) => _prefs.saveTokens(
    accessToken: tokens.accessToken,
    refreshToken: tokens.refreshToken,
    expiresAt: tokens.expiresAt,
  );
}
