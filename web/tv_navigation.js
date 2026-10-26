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
    '#vjod-pointer-hint { position: fixed; left: 50%; bottom: 16%;' +
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
      if (window.localStorage.getItem('vjod_pointer_hint3') === '1') return;
      window.localStorage.setItem('vjod_pointer_hint3', '1');
    } catch (e) {}
    var french = (navigator.language || 'fr').toLowerCase().indexOf('fr') === 0;
    var hint = document.createElement('div');
    hint.id = 'vjod-pointer-hint';
    hint.textContent = french
      ? 'Pour vous d\u00e9placer : poussez le curseur contre un bord de l\u2019\u00e9cran, ou amenez-le en bas \u00e0 droite pour des fl\u00e8ches \u00e0 cliquer'
      : 'To move: push the cursor against an edge of the screen, or bring it to the bottom right corner for arrows to click';
    document.body.appendChild(hint);
    setTimeout(function () { hint.style.opacity = '0'; }, 9000);
    setTimeout(function () { hint.remove(); }, 9600);
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
  // Where the app listens: its own element on the page. Events sent
  // anywhere else (the page's body, or a video or frame the app shows above
  // itself) may never reach it.
  function appElement() {
    return document.querySelector('flutter-view') ||
      document.querySelector('flt-glass-pane') || document.body;
  }
  function keyTarget() {
    var app = appElement();
    var active = document.activeElement;
    return active && active !== document.body && app.contains(active)
      ? active : app;
  }

  function wheel(x, y, dx, dy) {
    var target = appElement();
    // Shaped like a real mouse wheel's notches: whole multiples of 120,
    // with the matching legacy wheelDelta. Anything else, the app reads as
    // a laptop touchpad gesture, which half its screens don't scroll with.
    dx = Math.round(dx / 120) * 120;
    dy = Math.round(dy / 120) * 120;
    if (!dx && !dy) return;
    var ev = new WheelEvent('wheel', {
      clientX: x, clientY: y, screenX: x, screenY: y,
      deltaX: dx, deltaY: dy, deltaMode: 0,
      bubbles: true, cancelable: true, composed: true
    });
    try {
      Object.defineProperty(ev, 'wheelDeltaX', { value: -dx });
      Object.defineProperty(ev, 'wheelDeltaY', { value: -dy });
      Object.defineProperty(ev, 'wheelDelta', { value: -(dy || dx) });
    } catch (e) {}
    var free = target.dispatchEvent(ev);
    diag.wheels++;
    // The app cancels a wheel turn it scrolled with.
    if (!free) diag.wheelsTaken++;
    showDiag();
  }

  // With ?tvdebug=1 (remembered, ?tvdebug=0 to stop): a panel saying what
  // this script sent and what the app did with it, readable on a photo.
  var diag = { pushes: 0, wheels: 0, wheelsTaken: 0, keys: 0, keysTaken: 0,
    target: '-' };
  var diagOn = false;
  try {
    var asked = new URLSearchParams(window.location.search).get('tvdebug');
    if (asked === '1' || asked === '0') {
      window.localStorage.setItem('vjod_tv_debug', asked);
    }
    diagOn = window.localStorage.getItem('vjod_tv_debug') === '1';
  } catch (e) {}
  var diagEl = null;
  function showDiag() {
    if (!diagOn) return;
    if (!diagEl) {
      diagEl = document.createElement('div');
      diagEl.style.cssText =
        'position:fixed;left:12px;top:12px;z-index:2147483647;' +
        'pointer-events:none;background:rgba(0,0,0,.88);color:#7FD6A8;' +
        'font:15px/1.4 monospace;padding:10px 12px;white-space:pre;';
      document.body.appendChild(diagEl);
    }
    var a = document.activeElement;
    diagEl.textContent =
      'Poussees ' + diag.pushes +
      '\nMolette ' + diag.wheels + ' / prise par l\'app ' + diag.wheelsTaken +
      '\nFleches ' + diag.keys + ' / prises par l\'app ' + diag.keysTaken +
      '\nCible ' + diag.target +
      '\nActif ' + (a ? a.tagName.toLowerCase() : '-') +
      '\nApp ' + (document.querySelector('flutter-view') ? 'flutter-view'
        : (document.querySelector('flt-glass-pane') ? 'flt-glass-pane'
        : 'introuvable'));
  }
  if (diagOn) setInterval(showDiag, 1000);

  // A small arrow at the edge being pushed, so the viewer sees the push
  // was felt.
  var flashEl = null, flashTimer = 0;
  function flash(dir) {
    if (!flashEl) {
      flashEl = document.createElement('div');
      flashEl.style.cssText =
        'position:fixed;z-index:2147483647;pointer-events:none;' +
        'width:56px;height:56px;border-radius:28px;display:flex;' +
        'align-items:center;justify-content:center;font:700 30px sans-serif;' +
        'color:#0B0B0D;background:rgba(237,235,230,0.9);transition:opacity .3s;';
      document.body.appendChild(flashEl);
    }
    var pos = {
      down: 'left:calc(50% - 28px);bottom:18px;top:auto;right:auto;',
      up: 'left:calc(50% - 28px);top:18px;bottom:auto;right:auto;',
      right: 'right:18px;top:calc(50% - 28px);left:auto;bottom:auto;',
      left: 'left:18px;top:calc(50% - 28px);right:auto;bottom:auto;'
    }[dir];
    flashEl.style.cssText = flashEl.style.cssText.replace(
      /(left|right|top|bottom):[^;]*;/g, '') + pos;
    flashEl.textContent = { down: '\u25BC', up: '\u25B2', right: '\u25B6', left: '\u25C0' }[dir];
    flashEl.style.opacity = '1';
    clearTimeout(flashTimer);
    flashTimer = setTimeout(function () { flashEl.style.opacity = '0'; }, 350);
  }

  var lastPress = 0;
  function press(dir, held) {
    var now = Date.now();
    // About four steps a second, a little quicker while held.
    if (now - lastPress < (held > 6 ? 150 : 240)) return;
    lastPress = now;
    flash(dir);
    diag.pushes++;
    // Best: the app's own remote. It presses the key on whatever has the
    // focus, exactly as the TV app's remote does, on every screen.
    if (typeof window.vjodTvKey === 'function') {
      diag.target = 'app';
      var taken = false;
      try { taken = !!window.vjodTvKey(dir); } catch (e) {}
      diag.keys++;
      if (taken) diag.keysTaken++;
      showDiag();
      if (taken) return;
    }
    // Otherwise a wheel turn, for the screens that scroll like a page.
    var w = window.innerWidth, h = window.innerHeight;
    var amount = held > 6 ? 240 : 120;
    if (dir === 'down' || dir === 'up') {
      wheel(w / 2, h * 0.75, 0, dir === 'down' ? amount : -amount);
    } else {
      wheel(w / 2, mouseY >= 0 ? mouseY : h / 2,
        dir === 'right' ? amount : -amount, 0);
    }
    showDiag();
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
    function sizeSpacer() {
      spacer.style.cssText =
        'position:absolute;top:0;left:0;visibility:hidden;pointer-events:none;' +
        'width:' + (window.innerWidth * 3) + 'px;' +
        'height:' + (window.innerHeight * 3) + 'px;';
    }
    sizeSpacer();
    root.appendChild(spacer);
    var css = document.createElement('style');
    css.textContent =
      'html { overflow: scroll !important; scrollbar-width: none; }' +
      'html::-webkit-scrollbar { display: none; }' +
      'flutter-view, flt-glass-pane { position: fixed !important; }';
    document.head.appendChild(css);

    var cx = 0, cy = 0, resetting = false, streak = 0, lastScroll = 0;
    // Back to the middle. Where the page actually lands is the new
    // reference, read once the browser has settled, so a page that can't
    // reach the exact middle never reads as a push of its own.
    function centre() {
      resetting = true;
      window.scrollTo(window.innerWidth, window.innerHeight);
      setTimeout(function () {
        cx = window.scrollX;
        cy = window.scrollY;
        resetting = false;
      }, 60);
    }
    centre();
    window.addEventListener('resize', function () { sizeSpacer(); centre(); });

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

  // Third way, which needs nothing from the browser but a click: a small
  // pad of arrows in the bottom right corner, for the cursor to click (or
  // hold).
  function setUpPad() {
    var pad = document.createElement('div');
    pad.id = 'vjod-pad';
    pad.style.cssText =
      'position:fixed;right:22px;bottom:22px;z-index:2147483646;' +
      'display:grid;grid-template-columns:repeat(3,64px);' +
      'grid-template-rows:repeat(3,64px);gap:6px;opacity:0;' +
      'transition:opacity .25s;pointer-events:none;';
    var cells = [null, 'up', null, 'left', null, 'right', null, 'down', null];
    var glyph = { up: '\u25B2', down: '\u25BC', left: '\u25C0', right: '\u25B6' };
    cells.forEach(function (dir) {
      var cell = document.createElement('div');
      if (dir) {
        cell.textContent = glyph[dir];
        cell.style.cssText =
          'width:64px;height:64px;border-radius:32px;display:flex;' +
          'align-items:center;justify-content:center;cursor:pointer;' +
          'font:700 26px sans-serif;color:#EDEBE6;' +
          'background:rgba(11,11,13,0.85);' +
          'box-shadow:0 0 0 2px rgba(237,235,230,0.35);user-select:none;';
        var timer = 0, count = 0;
        var stop = function () { clearInterval(timer); timer = 0; count = 0; };
        var start = function (e) {
          e.preventDefault();
          e.stopPropagation();
          stop();
          lastPress = 0;
          press(dir, 0);
          timer = setInterval(function () { count++; press(dir, count); }, 120);
        };
        cell.addEventListener('mousedown', start);
        cell.addEventListener('touchstart', start, { passive: false });
        ['mouseup', 'mouseleave', 'touchend', 'touchcancel'].forEach(
          function (t) { cell.addEventListener(t, stop); });
        cell.addEventListener('click', function (e) {
          e.preventDefault();
          e.stopPropagation();
        });
      }
      pad.appendChild(cell);
    });
    document.body.appendChild(pad);

    // Hidden until the cursor comes near the bottom right corner, so the
    // screen stays clean for whoever pushes against the edges instead.
    var shown = false, hideTimer = 0;
    function show(on) {
      if (on === shown) return;
      shown = on;
      pad.style.opacity = on ? '.85' : '0';
      pad.style.pointerEvents = on ? 'auto' : 'none';
    }
    window.addEventListener('mousemove', function (e) {
      var near = e.clientX > window.innerWidth - 300 &&
        e.clientY > window.innerHeight - 300;
      clearTimeout(hideTimer);
      if (near) {
        show(true);
      } else if (shown) {
        hideTimer = setTimeout(function () { show(false); }, 800);
      }
    }, true);
    window.addEventListener('keydown', function (e) {
      if (!sending && e.key && e.key.indexOf('Arrow') === 0) show(false);
    }, true);
  }

  function setUp() {
    setUpScrollProxy();
    setUpPad();
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setUp);
  } else {
    setUp();
  }

  // Samsung Tizen: 10009. LG webOS: 461.
  var BACK_CODES = [10009, 461];
  var KNOWN_BACK = ['Escape', 'GoBack', 'BrowserBack', 'Backspace'];

  function relay(type, original) {
    original.preventDefault();
    original.stopImmediatePropagation();
    if (type !== 'keydown') return;
    if (typeof window.vjodTvKey === 'function') {
      try { window.vjodTvKey('back'); } catch (e) {}
    } else {
      history.back();
    }
  }

  ['keydown', 'keyup'].forEach(function (type) {
    window.addEventListener(type, function (e) {
      if (BACK_CODES.indexOf(e.keyCode) === -1) return;
      if (KNOWN_BACK.indexOf(e.key) !== -1) return;
      relay(type, e);
    }, true);
  });
})();
