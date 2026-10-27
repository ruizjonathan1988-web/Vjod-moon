import 'dart:async';

import 'provider_catalog_access.dart';

/// Keeps the IPTV provider's catalogue ready without getting in the way of
/// the app starting: once home has its rows and a moment more for their
/// artwork, it loads the catalogue saved on the device, and fetches a fresh
/// one from the provider when the saved one is a day old. It looks again
/// every hour, so a box left on for days still updates daily, and a profile
/// switched to meanwhile gets its own provider's catalogue.
class ProviderCatalogRefresher {
  ProviderCatalogRefresher._();

  static bool _started = false;

  /// How long after home is ready the catalogue starts loading, so posters
  /// and backdrops come first.
  static const settleDelay = Duration(seconds: 20);
  static const checkEvery = Duration(hours: 1);
  static const _readyTimeout = Duration(seconds: 90);

  /// Starts the background work once per app run. [homeReady] says when home
  /// has finished loading its rows; past [_readyTimeout] it goes ahead anyway.
  static void start({required bool Function() homeReady}) {
    if (_started) return;
    _started = true;
    final began = DateTime.now();
    Timer.periodic(const Duration(seconds: 2), (wait) {
      final waited = DateTime.now().difference(began);
      if (!homeReady() && waited < _readyTimeout) return;
      wait.cancel();
      Timer(settleDelay, () {
        _check();
        Timer.periodic(checkEvery, (_) => _check());
      });
    });
  }

  static void _check() {
    final catalog = currentProviderCatalog();
    if (catalog == null) return;
    unawaited(catalog.ensureFresh());
  }
}
