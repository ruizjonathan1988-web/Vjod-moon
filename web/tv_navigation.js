/**
 * VJOD - remote control help for TV browsers (tv_navigation.js)
 *
 * The app itself (Flutter) now recognises a TV browser and switches to the
 * same remote-friendly layout as the Android TV app: arrows, OK and focus
 * are handled there. This file only does what Flutter can't: turn the
 * remote's Back button, which Samsung and LG send under codes of their own,
 * into a regular Escape key the app understands, hide the mouse cursor
 * while the arrows drive the app, and, on a browser that turns the arrows
 * into a cursor of its own (a box's, often), scroll when that cursor is
 * pushed against an edge of the screen.
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

  // Two ways to drive the app on a TV:
  //  - arrows that reach the app: a highlight moves from item to item, as
  //    in the TV app, and the page's own mouse cursor is hidden;
  //  - a browser (often a box's) that turns the arrows into a mouse cursor
  //    of its own: the app never sees the arrows, so pushing that cursor
  //    against an edge of the screen scrolls, the way those browsers scroll
  //    an ordinary page. Clicking works as it is.
  var style = document.createElement('style');
  style.textContent =
    'html.vjod-keys, html.vjod-keys * { cursor: none !important; }' +
    '#vjod-pointer-hint { position: fixed; left: 50%; bottom: 6%;' +
    ' transform: translateX(-50%); z-index: 2147483647;' +
    ' background: rgba(11,11,13,0.92); color: #EDEBE6;' +
    ' font: 600 22px/1.35 sans-serif; padding: 14px 26px; border-radius: 14px;' +
    ' box-shadow: 0 0 0 2px rgba(237,235,230,0.25); pointer-events: none;' +
    ' transition: opacity .4s; text-align: center; }';
  document.head.appendChild(style);
  var root = document.documentElement;
  root.classList.add('vjod-keys');

  var mouseX = -1, mouseY = -1, lastMove = 0, hintShown = false;

  function showHint() {
    if (hintShown) return;
    hintShown = true;
    try {
      if (window.localStorage.getItem('vjod_pointer_hint') === '1') return;
      window.localStorage.setItem('vjod_pointer_hint', '1');
    } catch (e) {}
    var french = (navigator.language || 'fr').toLowerCase().indexOf('fr') === 0;
    var hint = document.createElement('div');
    hint.id = 'vjod-pointer-hint';
    hint.textContent = french
      ? 'Poussez le curseur contre un bord de l\u2019\u00e9cran pour faire d\u00e9filer'
      : 'Push the cursor against an edge of the screen to scroll';
    document.body.appendChild(hint);
    setTimeout(function () { hint.style.opacity = '0'; }, 6000);
    setTimeout(function () { hint.remove(); }, 6600);
  }

  window.addEventListener('mousemove', function (e) {
    if (e.clientX === mouseX && e.clientY === mouseY) return;
    mouseX = e.clientX;
    mouseY = e.clientY;
    lastMove = Date.now();
    root.classList.remove('vjod-keys');
    showHint();
  }, true);

  window.addEventListener('keydown', function (e) {
    if (e.key && e.key.indexOf('Arrow') === 0) {
      root.classList.add('vjod-keys');
      lastMove = 0;
    }
  }, true);

  // How close to an edge counts as pushing against it, and how fast it
  // scrolls: a little faster the longer it is held.
  var EDGE = 0.045, STEP = 22, MAX_STEP = 70, held = 0;

  function wheel(x, y, dx, dy) {
    var target = document.elementFromPoint(x, y);
    if (!target) return;
    target.dispatchEvent(new WheelEvent('wheel', {
      clientX: x, clientY: y, screenX: x, screenY: y,
      deltaX: dx, deltaY: dy, deltaMode: 0,
      bubbles: true, cancelable: true, composed: true
    }));
  }

  setInterval(function () {
    // Only while the cursor is in use, and not long after it stopped.
    if (mouseX < 0 || Date.now() - lastMove > 15000) { held = 0; return; }
    var w = window.innerWidth, h = window.innerHeight;
    var dx = 0, dy = 0;
    if (mouseY >= h * (1 - EDGE)) dy = 1;
    else if (mouseY <= h * EDGE) dy = -1;
    if (mouseX >= w * (1 - EDGE)) dx = 1;
    else if (mouseX <= w * EDGE) dx = -1;
    if (!dx && !dy) { held = 0; return; }
    held++;
    var step = Math.min(MAX_STEP, STEP + held * 2);
    if (dy) {
      // The whole screen: the list under the middle of the screen.
      wheel(w / 2, h / 2, 0, dy * step);
    } else {
      // A row: the one at the cursor's height, scrolled sideways.
      wheel(w / 2, mouseY, dx * step, 0);
    }
  }, 40);

  // Second way for cursor browsers, for those that don't tell the page
  // where their cursor is: they scroll the page themselves when the cursor
  // is pushed against an edge. The app draws on a fixed canvas, so the page
  // has nothing to scroll. Give it something: an invisible area three
  // screens high and wide behind the app. Whatever the browser scrolls it
  // by is handed to the app as a wheel turn, and the area is put back in
  // the middle, ready for the next push.
  var lastArrow = 0;
  window.addEventListener('keydown', function (e) {
    if (e.key && e.key.indexOf('Arrow') === 0) lastArrow = Date.now();
  }, true);

  function setUpScrollProxy() {
    var spacer = document.createElement('div');
    spacer.setAttribute('aria-hidden', 'true');
    spacer.style.cssText =
      'position:absolute;top:0;left:0;width:300vw;height:300vh;' +
      'visibility:hidden;pointer-events:none;';
    root.appendChild(spacer);
    var css = document.createElement('style');
    css.textContent =
      'html { overflow: scroll !important; scrollbar-width: none; }' +
      'html::-webkit-scrollbar { display: none; }' +
      'flutter-view, flt-glass-pane { position: fixed !important; }';
    document.head.appendChild(css);

    var cx = 0, cy = 0, resetting = false;
    function centre() {
      cx = window.innerWidth;
      cy = window.innerHeight;
      resetting = true;
      window.scrollTo(cx, cy);
      setTimeout(function () { resetting = false; }, 0);
    }
    centre();
    window.addEventListener('resize', centre);

    window.addEventListener('scroll', function () {
      var dx = window.scrollX - cx, dy = window.scrollY - cy;
      if (resetting || (!dx && !dy)) return;
      // Arrows that reach the app move its highlight; any scroll they cause
      // on the way is not a push against an edge.
      if (Date.now() - lastArrow > 400) {
        var w = window.innerWidth, h = window.innerHeight;
        if (dy) wheel(w / 2, h / 2, 0, dy);
        if (dx) wheel(w / 2, mouseY >= 0 ? mouseY : h / 2, dx, 0);
      }
      centre();
    }, { passive: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setUpScrollProxy);
  } else {
    setUpScrollProxy();
  }

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
