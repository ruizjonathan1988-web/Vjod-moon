// VJOD's simple mode: the same app and the same look, with less to find
// one's way through. Four tabs (Accueil, Films, Séries, TV), a short avatar
// menu, one button per title (Regarder when it plays, from the server or the
// IPTV provider, Demander otherwise) and slightly bigger text.
//
// It belongs to a profile. The administrator turns it on for a Jellyfin user
// (from the app's user administration), and every device that signs in as
// that user follows. It is kept in Jellyfin itself, in the user's display
// preferences, so nothing has to be set on each device.
//
// Everything the mode changes is decided here, so it stays light on the rest
// of the app and could be lifted into an app of its own later.
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../auth/repositories/session_repository.dart';
import '../../../preference/user_preferences.dart';
import '../../../ui/screens/detail/detail_buttons.dart' show DetailButton;
import 'catalogue_availability.dart';

/// Where the flag lives in Jellyfin: a display-preferences record of its own.
const simpleModePrefsId = 'vjod';
const simpleModeClient = 'vjod';
const simpleModeKey = 'simpleMode';

/// A little bigger everywhere, no more: the screens are drawn for the normal
/// size and must keep fitting.
const simpleModeTextScale = 1.1;

/// Whether the profile in use is in simple mode (as last read from the
/// server; the device remembers it for a start without network).
bool vjodSimpleMode() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<UserPreferences>()) return false;
  return getIt<UserPreferences>().get(UserPreferences.vjodSimpleMode);
}

/// The flag as the server stores it.
bool simpleModeFromPrefs(Map<String, String> customPrefs) =>
    customPrefs[simpleModeKey] == 'true';

/// The display preferences with the flag set or cleared, the rest kept.
DisplayPreferences withSimpleMode(DisplayPreferences prefs, bool on) =>
    DisplayPreferences(
      id: prefs.id.isEmpty ? simpleModePrefsId : prefs.id,
      sortBy: prefs.sortBy,
      sortOrder: prefs.sortOrder,
      viewType: prefs.viewType,
      customPrefs: {...prefs.customPrefs, simpleModeKey: on ? 'true' : 'false'},
    );

/// Reads a user's flag from the server. Null when it can't be read.
Future<bool?> readSimpleMode(String userId) async {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<MediaServerClient>()) return null;
  try {
    final prefs = await getIt<MediaServerClient>()
        .displayPreferencesApi
        .getDisplayPreferences(simpleModePrefsId, client: simpleModeClient, userId: userId);
    return simpleModeFromPrefs(prefs.customPrefs);
  } catch (e) {
    debugPrint('[SimpleMode] read failed: $e');
    return null;
  }
}

/// Sets a user's flag on the server: the administrator for anyone, a viewer
/// for themselves. Throws when the server refuses.
Future<void> writeSimpleMode(String userId, bool on) async {
  final api = GetIt.instance<MediaServerClient>().displayPreferencesApi;
  DisplayPreferences current;
  try {
    current = await api.getDisplayPreferences(simpleModePrefsId, client: simpleModeClient, userId: userId);
  } catch (_) {
    current = const DisplayPreferences(id: simpleModePrefsId);
  }
  await api.saveDisplayPreferences(
    simpleModePrefsId,
    withSimpleMode(current, on),
    client: simpleModeClient,
    userId: userId,
  );
  if (userId == GetIt.instance<SessionRepository>().activeUserId) {
    await GetIt.instance<UserPreferences>().set(UserPreferences.vjodSimpleMode, on);
  }
}

String? _syncedFor;

/// Takes on the signed-in user's flag from the server. Called when the app
/// starts and after a profile change; nothing read leaves things as they are.
Future<void> syncSimpleModeFromServer() async {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<SessionRepository>() || !getIt.isRegistered<UserPreferences>()) return;
  final userId = getIt<SessionRepository>().activeUserId;
  if (userId == null || userId.isEmpty) return;
  // Once per profile and launch: it is asked from screens that come and go.
  if (_syncedFor == userId) return;
  _syncedFor = userId;
  final on = await readSimpleMode(userId);
  if (on == null) _syncedFor = null;
  if (on == null) return;
  final prefs = getIt<UserPreferences>();
  if (prefs.get(UserPreferences.vjodSimpleMode) != on) {
    await prefs.set(UserPreferences.vjodSimpleMode, on);
  }
}

/// The one thing a title offers in simple mode.
enum SimpleAction { watch, request, requested }

/// Regarder when it plays now (server first, else the provider), Demandé once
/// asked for, Demander otherwise.
SimpleAction simpleActionFor(CatalogueAvailability a) => switch (a) {
  CatalogueAvailability.server || CatalogueAvailability.iptv => SimpleAction.watch,
  CatalogueAvailability.requested => SimpleAction.requested,
  CatalogueAvailability.toRequest => SimpleAction.request,
};

/// On a title's page, beside the one main button: the trailer and the list.
/// Everything else stays behind « + ».
const simpleModeFicheButtons = [
  DetailButton.trailer,
  DetailButton.favorite,
  DetailButton.seerrWatchlist,
];
