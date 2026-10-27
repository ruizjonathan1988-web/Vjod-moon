import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../../../preference/seerr_preferences.dart';
import '../../../preference/user_preferences.dart';
import 'tv_playlists.dart';
import 'xtream_catalog.dart';

/// The provider catalogue of the signed-in profile: the first Xtream source
/// it saved. Null in a browser (an HTTPS page can't reach a plain-HTTP
/// provider), in kids mode (the provider's catalogue isn't filtered), or when
/// the profile has no Xtream source.
XtreamCatalog? currentProviderCatalog() {
  if (kIsWeb) return null;
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<SeerrPreferences>()) return null;
  if (getIt.isRegistered<UserPreferences>() &&
      getIt<UserPreferences>().get(UserPreferences.kidsModeEnabled)) {
    return null;
  }
  return XtreamCatalog.forPlaylists(
    TvPlaylists.decode(getIt<SeerrPreferences>().vjodTvPlaylistsJson),
  );
}
