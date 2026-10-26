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
