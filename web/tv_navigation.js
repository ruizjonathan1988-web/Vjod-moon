/**
 * VJOD - remote control help for TV browsers (tv_navigation.js)
 *
 * The app itself (Flutter) now recognises a TV browser and switches to the
 * same remote-friendly layout as the Android TV app: arrows, OK and focus
 * are handled there. This file only does what Flutter can't: turn the
 * remote's Back button, which Samsung and LG send under codes of their own,
 * into a regular Escape key the app understands.
 *
 * On a computer, a phone or a tablet it stops at once and changes nothing.
 * `?tv=1` / `?tv=0` in the address forces TV mode on or off (remembered).
 */
(function () {
  'use strict';

  var markers = [
    'smart-tv', 'smarttv', 'tizen', 'web0s', 'webos', 'netcast', 'nettv',
    'hbbtv', 'vidaa', 'bravia', 'googletv', 'android tv', 'crkey', 'aftb',
    'aftm', 'afts', 'aftt', 'aftka', 'aftmm', 'appletv', 'philipstv',
    'viera', 'roku', 'operatv'
  ];

  function isTvBrowser() {
    try {
      var forced = new URLSearchParams(window.location.search).get('tv');
      if (forced === '1') return true;
      if (forced === '0') return false;
    } catch (e) {}
    try {
      var saved = window.localStorage.getItem('vjod_tv_mode');
      if (saved === '1') return true;
      if (saved === '0') return false;
    } catch (e) {}
    var ua = (navigator.userAgent || '').toLowerCase();
    for (var i = 0; i < markers.length; i++) {
      if (ua.indexOf(markers[i]) !== -1) return true;
    }
    return false;
  }

  if (!isTvBrowser()) return;

  // Samsung Tizen: 10009. LG webOS: 461.
  var BACK_CODES = [10009, 461];
  var KNOWN_BACK = ['Escape', 'GoBack', 'BrowserBack', 'Backspace'];

  function relay(type, original) {
    var target = document.activeElement || document.body;
    var ev = new KeyboardEvent(type, {
      key: 'Escape',
      code: 'Escape',
      keyCode: 27,
      which: 27,
      bubbles: true,
      cancelable: true
    });
    target.dispatchEvent(ev);
    original.preventDefault();
    original.stopImmediatePropagation();
  }

  ['keydown', 'keyup'].forEach(function (type) {
    window.addEventListener(type, function (e) {
      if (BACK_CODES.indexOf(e.keyCode) === -1) return;
      if (KNOWN_BACK.indexOf(e.key) !== -1) return;
      relay(type, e);
    }, true);
  });
})();
