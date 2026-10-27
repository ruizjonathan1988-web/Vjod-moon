import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../../../preference/seerr_preferences.dart';
import '../../../preference/user_preferences.dart';
import 'tv_playlists.dart';
import 'xtream_cache_store.dart';
import 'xtream_catalog.dart';

/// The language tags the signed-in profile asked for first, most wanted
/// first. Empty means no preference.
List<String> currentProviderLanguages() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<SeerrPreferences>()) return const [];
  return getIt<SeerrPreferences>().vjodProviderLanguages;
}

XtreamAccount? _accountFrom(String json) {
  if (json.isEmpty) return null;
  try {
    return XtreamAccount.fromJson(jsonDecode(json));
  } catch (_) {
    return null;
  }
}

/// The provider account the house's Jellyfin hands out, if any.
XtreamAccount? _jellyfinAccount(SeerrPreferences prefs) =>
    _accountFrom(prefs.vjodJellyfinProviderAccountJson);

/// The provider account the seedbox last handed this device, if any.
XtreamAccount? _serverAccount(SeerrPreferences prefs) {
  final json = prefs.vjodCatalogServerAccountJson;
  if (json.isEmpty) return null;
  try {
    return XtreamAccount.fromJson(jsonDecode(json));
  } catch (_) {
    return null;
  }
}

Future<void> _saveServerAccount(
  SeerrPreferences prefs,
  XtreamAccount account,
) async {
  await prefs.setVjodCatalogServerAccountJson(jsonEncode(account.toJson()));
  // Loads the new account's catalogue (already saved on the device) now
  // rather than at the next hourly check.
  currentProviderCatalog()?.warmUp();
}

Future<void>? _bootstrap;

/// Reads the account out of the seedbox's file once, for a device that was
/// given the seedbox's address but has never had its file yet.
void _bootstrapServerAccount(SeerrPreferences prefs, String url) {
  _bootstrap ??= () async {
    try {
      final body = await fetchServerCatalog(url);
      if (body == null) return;
      final cache = await compute(decodeCatalogCache, body);
      final provider = cache?.provider;
      if (provider == null) return;
      await writeCatalogCache(
        catalogCacheKey(provider.portal, provider.username),
        body,
      );
      await _saveServerAccount(prefs, provider);
    } finally {
      _bootstrap = null;
    }
  }();
}

/// The provider catalogue this device and profile play from. With the
/// seedbox's address set, the account it hands out wins, so changing
/// provider in Jellyfin moves every device; otherwise the profile's first
/// Xtream source. Null in a browser (an HTTPS page can't reach a plain-HTTP
/// provider), in kids mode (the provider's catalogue isn't filtered), or with
/// no account at all.
XtreamCatalog? currentProviderCatalog() {
  if (kIsWeb) return null;
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<SeerrPreferences>()) return null;
  if (getIt.isRegistered<UserPreferences>() &&
      getIt<UserPreferences>().get(UserPreferences.kidsModeEnabled)) {
    return null;
  }
  final prefs = getIt<SeerrPreferences>();
  final serverUrl = prefs.vjodCatalogServerUrl;
  final fromServer = serverUrl.isEmpty ? null : _serverAccount(prefs);
  if (serverUrl.isNotEmpty && fromServer == null) {
    _bootstrapServerAccount(prefs, serverUrl);
  }
  // The seedbox's file first (set by hand on the owner's devices), then the
  // account Jellyfin hands out to the whole house, then the profile's own.
  final catalog = XtreamCatalog.forPlaylists([
    ?fromServer?.toPlaylist(),
    ?_jellyfinAccount(prefs)?.toPlaylist(),
    ...TvPlaylists.decode(prefs.vjodTvPlaylistsJson),
  ]);
  if (catalog == null) return null;
  catalog.serverCatalogUrl = serverUrl;
  catalog.onServerAccount = (account) =>
      unawaited(_saveServerAccount(prefs, account));
  return catalog;
}

/// Whether this device plays the provider's catalogue with the account the
/// seedbox hands out rather than one saved in a profile.
bool providerAccountFromServer() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<SeerrPreferences>()) return false;
  final prefs = getIt<SeerrPreferences>();
  return (prefs.vjodCatalogServerUrl.isNotEmpty &&
          _serverAccount(prefs) != null) ||
      _jellyfinAccount(prefs) != null;
}
