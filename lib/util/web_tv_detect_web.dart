import 'package:web/web.dart' as web;

const _storageKey = 'vjod_tv_mode';

/// Words TV browsers put in their user agent.
const _tvMarkers = [
  'smart-tv',
  'smarttv',
  'tizen',
  'web0s',
  'webos',
  'netcast',
  'nettv',
  'hbbtv',
  'vidaa',
  'bravia',
  'googletv',
  'android tv',
  'crkey',
  'aftb',
  'aftm',
  'afts',
  'aftt',
  'aftka',
  'aftmm',
  'appletv',
  'philipstv',
  'viera',
  'roku',
  'operatv',
];

const _debugKey = 'vjod_tv_debug';

/// Whether the diagnostic panel is on: `?tvdebug=1` turns it on and
/// `?tvdebug=0` off, remembered, since the address loses its query as soon
/// as the app moves to another screen.
bool webTvDebugEnabled() {
  try {
    final asked = Uri.base.queryParameters['tvdebug'];
    if (asked == '1' || asked == '0') {
      web.window.localStorage.setItem(_debugKey, asked!);
      return asked == '1';
    }
    return web.window.localStorage.getItem(_debugKey) == '1';
  } catch (_) {
    return false;
  }
}

bool isWebTvBrowser() {
  try {
    final forced = Uri.base.queryParameters['tv'];
    if (forced == '1' || forced == '0') {
      try {
        web.window.localStorage.setItem(_storageKey, forced!);
      } catch (_) {}
      return forced == '1';
    }
    try {
      final saved = web.window.localStorage.getItem(_storageKey);
      if (saved == '1') return true;
      if (saved == '0') return false;
    } catch (_) {}
    final ua = web.window.navigator.userAgent.toLowerCase();
    return _tvMarkers.any(ua.contains);
  } catch (_) {
    return false;
  }
}
