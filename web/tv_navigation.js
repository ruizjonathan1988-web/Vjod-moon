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
 * pushed against an edge of the screen: each push is an arrow press, so
 * every screen moves the way it does with the TV app's remote.
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

  // Arrows pressed on a remote that reaches the app, as opposed to the ones
  // this script sends on its behalf.
  var sending = false, lastArrow = 0;
  window.addEventListener('keydown', function (e) {
    if (sending || !e.key || e.key.indexOf('Arrow') !== 0) return;
    root.classList.add('vjod-keys');
    lastMove = 0;
    lastArrow = Date.now();
  }, true);

  // A push against an edge becomes an arrow press, so every screen moves
  // exactly as it does with the TV app's remote: the highlight goes to the
  // next item and the screen follows it, wherever that is.
  var ARROWS = {
    up: ['ArrowUp', 38], down: ['ArrowDown', 40],
    left: ['ArrowLeft', 37], right: ['ArrowRight', 39]
  };
  var lastPress = 0;
  function press(dir, held) {
    var now = Date.now();
    // About four steps a second, a little quicker while held.
    if (now - lastPress < (held > 6 ? 150 : 240)) return;
    lastPress = now;
    var k = ARROWS[dir];
    var target = document.activeElement || document.body;
    sending = true;
    try {
      ['keydown', 'keyup'].forEach(function (type) {
        target.dispatchEvent(new KeyboardEvent(type, {
          key: k[0], code: k[0], keyCode: k[1], which: k[1],
          bubbles: true, cancelable: true, composed: true
        }));
      });
    } finally {
      sending = false;
    }
  }

  // First way: the browser tells the page where its cursor is. Holding it
  // against an edge keeps pressing that way.
  var EDGE = 0.045, held = 0;
  setInterval(function () {
    // Only while the cursor is in use, and not long after it stopped.
    if (mouseX < 0 || Date.now() - lastMove > 15000) { held = 0; return; }
    var w = window.innerWidth, h = window.innerHeight;
    var dir = null;
    if (mouseY >= h * (1 - EDGE)) dir = 'down';
    else if (mouseY <= h * EDGE) dir = 'up';
    else if (mouseX >= w * (1 - EDGE)) dir = 'right';
    else if (mouseX <= w * EDGE) dir = 'left';
    if (!dir) { held = 0; return; }
    held++;
    press(dir, held);
  }, 40);

  // Second way, for browsers that keep their cursor to themselves: they
  // scroll the page when the cursor is pushed against an edge. The app
  // draws on a fixed surface, so the page has nothing to scroll. Give it
  // something: an invisible area three screens high and wide behind the
  // app. Each scroll of it becomes an arrow press, and the area is put back
  // in the middle, ready for the next push.
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

    var cx = 0, cy = 0, resetting = false, streak = 0, lastScroll = 0;
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
      var now = Date.now();
      streak = now - lastScroll < 400 ? streak + 1 : 0;
      lastScroll = now;
      // Arrows that reach the app already move it; a scroll they cause on
      // the way is not a push against an edge.
      if (now - lastArrow > 400) {
        if (Math.abs(dy) >= Math.abs(dx)) press(dy > 0 ? 'down' : 'up', streak);
        else press(dx > 0 ? 'right' : 'left', streak);
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
