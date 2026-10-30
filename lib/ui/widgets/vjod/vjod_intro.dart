// VJOD's opening, once per launch, with its own sound (made for VJOD, in
// assets/sounds/). Seven to choose from in Réglages → Apparence → Ouverture
// de VJOD, or none; « Les lignes de commande » by default. Any key or a tap
// skips it. Everything is drawn in one painter from the logo picture, so it
// stays sharp on a 4K screen and weighs nothing.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../util/platform_detection.dart';
import '../../../util/startup_timeline.dart';

enum VjodIntroStyle {
  terminal('Les lignes de commande', 'Un terminal se connecte à la seedbox, vérifie les 30 sources, imprime le logo en caractères, « ./vjod --play » et Entrée.', 4.4),
  hacker('Le hacker', 'Pluie de code, le logo se déchiffre caractère par caractère, « accès autorisé », glitchs, puis la télé s\'éteint.', 3.35),
  plateforme('La plateforme', 'Des milliers de caractères forment VJOD, gros impact de bande-annonce, puis le logo se dissout en pixels.', 3.0),
  signal('Le signal', 'Une vieille télé s\'allume dans la neige, le signal se cale sur VJOD avec des glitchs, puis s\'éteint en un point.', 3.25),
  lame('La lame', 'Une lame de lumière dessine le logo, le bouton lecture frappe, plongée dedans.', 3.25),
  ruban('Le ruban', 'Un ruban rouge ondule et se noue en VJOD, un reflet passe, puis il repart en trait de lumière.', 3.3),
  battement('Le battement', 'Le bouton lecture bat deux fois, se range dans le D, puis V, J, O, D tombent un par un.', 3.4);

  final String label;
  final String description;
  final double seconds;

  const VjodIntroStyle(this.label, this.description, this.seconds);

  String get sound => 'assets/sounds/intro_$name.ogg';

  static const _key = 'vjod_intro_style';
  static const fallback = VjodIntroStyle.terminal;

  /// The opening chosen on this device; null for « Aucune ».
  static Future<VjodIntroStyle?> current() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_key);
      if (v == 'none') return null;
      return VjodIntroStyle.values.where((s) => s.name == v).firstOrNull ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> choose(VjodIntroStyle? style) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, style?.name ?? 'none');
    } catch (_) {}
  }
}

class VjodIntro extends StatefulWidget {
  final VoidCallback onDone;

  /// The opening to play; null plays the one chosen in the settings.
  final VjodIntroStyle? style;

  const VjodIntro({super.key, required this.onDone, this.style});

  /// Shown once per launch only (not on a change of profile).
  static bool played = false;

  /// No sound (tests).
  static bool muted = false;

  /// Prepares the drawing (logo, glyphs, snow) ahead of time.
  static Future<void> preload() => _Kit.load();

  @override
  State<VjodIntro> createState() => _VjodIntroState();
}

class _VjodIntroState extends State<VjodIntro> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  final _focus = FocusNode(debugLabel: 'vjod_intro');
  Player? _player;
  _Kit? _kit;
  VjodIntroStyle? _style;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    VjodIntro.played = true;
    unawaited(_start());
  }

  Future<void> _start() async {
    final style = widget.style ?? await VjodIntroStyle.current();
    if (style == null) return _finish();
    _Kit kit;
    try {
      kit = await _Kit.load().timeout(const Duration(seconds: 4));
    } catch (_) {
      return _finish();
    }
    if (!mounted || _done) return;
    final c = AnimationController(vsync: this, duration: Duration(milliseconds: (style.seconds * 1000).round()));
    setState(() {
      _style = style;
      _kit = kit;
      _c = c;
    });
    StartupTimeline.mark("Ouverture : début de l'animation");
    unawaited(_playSound(style));
    c.forward().whenComplete(_finish);
  }

  Future<void> _playSound(VjodIntroStyle style) async {
    // media_kit isn't set up on Apple devices, and a browser blocks a sound
    // the viewer didn't ask for: silent there.
    if (VjodIntro.muted || kIsWeb || PlatformDetection.isIOS || PlatformDetection.isMacOS || PlatformDetection.isAppleTV) return;
    try {
      final p = Player();
      _player = p;
      await p.open(Media('asset:///${style.sound}'));
    } catch (_) {}
  }

  void _finish() {
    if (_done) return;
    _done = true;
    StartupTimeline.mark("Ouverture : fin de l'animation");
    widget.onDone();
  }

  void _skip() {
    if (_done) return;
    _c?.stop();
    unawaited(_player?.stop());
    _finish();
  }

  @override
  void dispose() {
    _c?.dispose();
    _focus.dispose();
    final p = _player;
    // The sound's tail goes on over the home screen, then is freed.
    if (p != null) Timer(const Duration(seconds: 4), () => unawaited(p.dispose()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c, kit = _kit, style = _style;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent) _skip();
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: ColoredBox(
          color: _black,
          child: c == null || kit == null || style == null
              ? const SizedBox.expand()
              : AnimatedBuilder(
                  animation: c,
                  builder: (context, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _IntroPainter(kit, style, c.value * style.seconds),
                  ),
                ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// What the painter needs, made once: the logo, its outline as a grid of cells,
// the glyphs of the terminal in one picture, and a few frames of TV snow.

const _black = Color(0xFF040404);
const _red = Color(0xFFE50914);
const _aspect = 1024 / 572;
const _tri = Offset(0.786, 0.511); // the play button in the logo picture
const _glyphs = '01ABCDEF23456789#\$%&*+=<>/\\|{}[]VJOD';
const _mono = 'monospace';
const _monoFallback = ['Roboto Mono', 'Droid Sans Mono', 'Courier New', 'Courier'];

class _Cell {
  final int q, r;
  final double a, rnd, sx, sy, delay;
  final int seed;
  const _Cell(this.q, this.r, this.a, this.rnd, this.sx, this.sy, this.delay, this.seed);
}

class _Kit {
  final ui.Image logo;
  final ui.Image atlas;
  final double glyphW, glyphH;
  final List<ui.Image> snow;
  final int cols, rows;
  final List<_Cell> cells;
  final int asciiCols, asciiRows;
  final List<double> ascii; // level 0..1 per cell
  final List<({double x, double s, double o})> rain;

  _Kit(this.logo, this.atlas, this.glyphW, this.glyphH, this.snow, this.cols, this.rows, this.cells, this.asciiCols,
      this.asciiRows, this.ascii, this.rain);

  static _Kit? _cache;

  static Future<_Kit> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final bytes = (await rootBundle.load('assets/images/vjod_intro_logo.png')).buffer.asUint8List();
    final logo = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;

    Future<Uint8List> alphaGrid(int w, int h) async {
      final img = (await (await ui.instantiateImageCodec(bytes, targetWidth: w, targetHeight: h)).getNextFrame()).image;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    }

    final rnd = math.Random(4);
    const cols = 110;
    final rows = (cols / _aspect * 1.8).round();
    final grid = await alphaGrid(cols, rows);
    final cells = <_Cell>[];
    for (var r = 0; r < rows; r++) {
      for (var q = 0; q < cols; q++) {
        final a = grid[(r * cols + q) * 4 + 3];
        if (a > 110) {
          final ang = rnd.nextDouble() * math.pi * 2, dist = .7 + rnd.nextDouble() * .8;
          cells.add(_Cell(q, r, a / 255, rnd.nextDouble(), math.cos(ang) * dist, math.sin(ang) * dist * .7,
              rnd.nextDouble() * .45, cells.length));
        }
      }
    }
    const aCols = 64;
    final aRows = (aCols / _aspect * .55).round();
    final ag = await alphaGrid(aCols, aRows);
    final ascii = [
      for (var i = 0; i < aCols * aRows; i++)
        () {
          final a = ag[i * 4 + 3] / 255;
          return a > .75 ? 1.0 : a > .5 ? .75 : a > .28 ? .5 : a > .1 ? .25 : 0.0;
        }(),
    ];

    // The glyphs, white, side by side: drawn tinted with drawAtlas.
    const gs = 48.0;
    final painters = [
      for (final ch in _glyphs.split(''))
        TextPainter(
          text: TextSpan(
            text: ch,
            style: const TextStyle(
              fontFamily: _mono,
              fontFamilyFallback: _monoFallback,
              fontSize: gs,
              color: Colors.white,
              height: 1.0,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    final gw = painters.map((p) => p.width).reduce(math.max).ceilToDouble();
    final gh = painters.map((p) => p.height).reduce(math.max).ceilToDouble();
    final rec = ui.PictureRecorder();
    final cv = Canvas(rec);
    for (var i = 0; i < painters.length; i++) {
      painters[i].paint(cv, Offset(i * gw + (gw - painters[i].width) / 2, 0));
    }
    final atlas = await rec.endRecording().toImage((gw * painters.length).ceil(), gh.ceil());

    Future<ui.Image> snowFrame() {
      const w = 320, h = 180;
      final px = Uint8List(w * h * 4);
      for (var i = 0; i < w * h; i++) {
        final v = rnd.nextInt(256);
        px[i * 4] = v;
        px[i * 4 + 1] = v;
        px[i * 4 + 2] = v;
        px[i * 4 + 3] = 255;
      }
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
      return done.future;
    }

    final snow = [for (var i = 0; i < 4; i++) await snowFrame()];
    final rain = [
      for (var i = 0; i < 70; i++) (x: rnd.nextDouble(), s: .25 + rnd.nextDouble() * .6, o: rnd.nextDouble()),
    ];
    return _cache = _Kit(logo, atlas, gw, gh, snow, cols, rows, cells, aCols, aRows, ascii, rain);
  }
}

// ---------------------------------------------------------------------------

double _clamp(double x) => x < 0 ? 0 : (x > 1 ? 1 : x);

double _seg(double t, double a, double b, [Curve c = Curves.linear]) => c.transform(_clamp((t - a) / (b - a)));

const _ioc = Curves.easeInOutCubic, _oc = Curves.easeOutCubic, _ic = Curves.easeInCubic;
const _io = Curves.easeInOutQuad, _ei = Curves.easeInQuad, _back = Curves.easeOutBack;

enum _Tint { none, cyan, gold }

class _IntroPainter extends CustomPainter {
  final _Kit k;
  final VjodIntroStyle style;
  final double t;
  final _rnd = math.Random();

  _IntroPainter(this.k, this.style, this.t);

  late double W, H, w, h, cx, cy, u;

  @override
  void paint(Canvas c, Size size) {
    W = size.width;
    H = size.height;
    w = W * .78;
    if (w / _aspect > H * .58) w = H * .58 * _aspect;
    h = w / _aspect;
    cx = W / 2;
    cy = H / 2;
    // the scale of what was drawn for a 1920 × 1080 screen (text, offsets),
    // narrower on a phone held upright so the terminal lines fit
    u = math.min(H / 1080, W / 1110);
    c.drawRect(Offset.zero & size, Paint()..color = _black);
    switch (style) {
      case VjodIntroStyle.lame:
        _lame(c);
      case VjodIntroStyle.ruban:
        _ruban(c);
      case VjodIntroStyle.battement:
        _battement(c);
      case VjodIntroStyle.signal:
        _signal(c);
      case VjodIntroStyle.hacker:
        _hacker(c);
      case VjodIntroStyle.plateforme:
        _plateforme(c);
      case VjodIntroStyle.terminal:
        _terminal(c);
    }
  }

  @override
  bool shouldRepaint(_IntroPainter old) => old.t != t || old.style != style;

  // ----------------------------------------------------------------- helpers
  void halo(Canvas c, Offset at, double r, double s) {
    if (r <= 0 || s <= 0) return;
    c.drawCircle(
      at,
      r,
      Paint()
        ..shader = ui.Gradient.radial(at, r, [
          _red.withValues(alpha: _clamp(s)),
          _red.withValues(alpha: _clamp(s * .35)),
          _red.withValues(alpha: 0),
        ], const [0, .35, 1]),
    );
  }

  List<double> _matrix(double bright, double alpha, _Tint tint) => switch (tint) {
    _Tint.none => [bright, 0, 0, 0, 0, 0, bright, 0, 0, 0, 0, 0, bright, 0, 0, 0, 0, 0, alpha, 0],
    _Tint.cyan => [0, 0, 0, 0, 0, bright, 0, 0, 0, 0, bright, 0, 0, 0, 0, 0, 0, 0, alpha, 0],
    _Tint.gold => [bright, 0, 0, 0, 0, bright * .6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, alpha, 0],
  };

  /// The logo centred on (x, y), or a vertical slice of it (x0..x1 of the picture).
  void logo(Canvas c, double x, double y,
      {double scale = 1, double sx = 1, double sy = 1, double alpha = 1, double x0 = 0, double x1 = 1,
      double bright = 1, _Tint tint = _Tint.none, bool plus = false, Rect? band}) {
    if (alpha <= 0) return;
    c.save();
    c.translate(x, y);
    c.scale(scale * sx, scale * sy);
    c.clipRect(Rect.fromLTWH(-w / 2.0 + x0 * w, -h / 2, (x1 - x0) * w, h));
    if (band != null) c.clipRect(band.shift(Offset(-x, -y)));
    final img = k.logo;
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(-w / 2, -h / 2, w, h),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..blendMode = plus ? BlendMode.plus : BlendMode.srcOver
        ..colorFilter = ColorFilter.matrix(_matrix(bright, _clamp(alpha), tint)),
    );
    c.restore();
  }

  /// A horizontal glitch: one band of the logo drawn again, shifted.
  void glitchBand(Canvas c, double bandH, double shift) {
    final y = cy - h * .25 + _rnd.nextDouble() * h * .5;
    final band = Rect.fromLTWH(0, y, W, bandH);
    c.save();
    c.clipRect(band);
    c.drawRect(band, Paint()..color = _black);
    c.restore();
    logo(c, cx + shift, cy, band: band);
  }

  int pick(num seed) => ((math.sin(seed) * 9973).abs().floor()) % _glyphs.length;

  /// Many glyphs at once, each with its colour (centre, size in pixels).
  void glyphs(Canvas c, List<(int, Offset, double, Color)> list) {
    if (list.isEmpty) return;
    final xf = <RSTransform>[], rects = <Rect>[], colors = <Color>[];
    for (final (g, at, size, color) in list) {
      final s = size / k.glyphH;
      xf.add(RSTransform.fromComponents(
          rotation: 0, scale: s, anchorX: k.glyphW / 2, anchorY: k.glyphH / 2, translateX: at.dx, translateY: at.dy));
      rects.add(Rect.fromLTWH(g * k.glyphW, 0, k.glyphW, k.glyphH));
      colors.add(color);
    }
    c.drawAtlas(k.atlas, xf, rects, colors, BlendMode.modulate, null, Paint()..filterQuality = FilterQuality.medium);
  }

  /// One line of terminal text; returns its width.
  double text(Canvas c, String s, Offset at, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontFamily: _mono, fontFamilyFallback: _monoFallback, fontSize: size, color: color, height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at);
    return tp.width;
  }

  double textWidth(String s, double size) => (TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontFamily: _mono, fontFamilyFallback: _monoFallback, fontSize: size, height: 1.0),
    ),
    textDirection: TextDirection.ltr,
  )..layout()).width;

  void snow(Canvas c, double a) {
    if (a <= 0) return;
    final img = k.snow[_rnd.nextInt(k.snow.length)];
    c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), Offset.zero & Size(W, H),
        Paint()
          ..filterQuality = FilterQuality.none
          ..color = Color.fromRGBO(0, 0, 0, _clamp(a)));
  }

  void scan(Canvas c, double a) {
    final p = Paint()..color = Color.fromRGBO(0, 0, 0, _clamp(a));
    final step = math.max(4.0, u * 6);
    for (var y = 0.0; y < H; y += step) {
      c.drawRect(Rect.fromLTWH(0, y, W, step / 2), p);
    }
  }

  void flash(Canvas c, double a, [Color color = Colors.white]) {
    if (a > 0) c.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()..color = color.withValues(alpha: _clamp(a)));
  }

  /// The old TV turning off: the picture squashed to a line, then to a point.
  void crt(Canvas c, double offY, double offX) {
    c.translate(cx, cy);
    c.scale(math.max(.002, 1.0 - .995 * offX), math.max(.004, 1.0 - offY));
    c.translate(-cx, -cy);
  }

  // ----------------------------------------------------------------- A, la lame
  void _lame(Canvas c) {
    const hit = 1.05, dive = 2.45;
    final front = .09 + _seg(t, .22, hit, _ioc) * .82;
    final bladeOn = t < hit + .12 ? 1.0 - _seg(t, hit - .05, hit + .12) : 0.0;
    final strike = t >= hit ? 1.0 - _seg(t, hit, hit + .65, _oc) : 0.0;
    final jolt = t >= hit ? math.sin(math.pi * _seg(t, hit, hit + .28)) : 0.0;
    final glow = t >= hit ? (.35 + .65 * strike) * (1.0 - _seg(t, dive, dive + .3)) : 0.0;
    final intro = .93 + .07 * _seg(t, .22, hit, _oc), push = 1.0 + .07 * _seg(t, hit, dive, _io);
    final d = _seg(t, dive, 3.05, _ic);
    final scale = intro * push * (1.0 + .045 * jolt) * math.pow(55, d);
    final tf = Offset((_tri.dx - .5) * w, (_tri.dy - .5) * h);
    final shift = -tf * d;
    if (bladeOn > 0) halo(c, Offset(cx + (front - .5) * w * intro, cy), w * .45, .22 * bladeOn);
    final tp = Offset(cx, cy) + tf * intro * push + shift;
    if (glow > 0) halo(c, tp, w * (.35 + .5 * (1.0 - strike)), .5 * glow);

    c.save();
    c.translate(cx + shift.dx, cy + shift.dy);
    c.translate(tf.dx, tf.dy);
    c.scale(scale.toDouble());
    c.translate(-tf.dx, -tf.dy);
    final box = Rect.fromLTWH(-w / 2, -h / 2, w, h);
    c.saveLayer(box.inflate(40), Paint());
    logo(c, 0, 0, bright: t < hit ? .8 : 1.0 + .55 * strike);
    c.drawRect(
      box,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.linear(box.centerLeft, box.centerRight, const [
          Colors.white,
          Colors.white,
          Color(0x00FFFFFF),
          Color(0x00FFFFFF),
        ], [
          0,
          math.max(0, front - .035),
          math.min(1, front),
          1,
        ]),
    );
    c.restore();
    if (bladeOn > 0) {
      final bx = -w / 2.0 + front * w;
      final r = Rect.fromLTWH(bx - u * 14, -h / 2.0 + h * .18, u * 28, h * .64);
      c.drawRect(r.inflate(u * 6),
          Paint()
            ..color = _red.withValues(alpha: .7 * bladeOn)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 18));
      c.drawRect(
        r,
        Paint()
          ..shader = ui.Gradient.linear(r.centerLeft, r.centerRight, [
            _red.withValues(alpha: 0),
            _red.withValues(alpha: .67 * bladeOn),
            Colors.white.withValues(alpha: bladeOn),
            _red.withValues(alpha: .67 * bladeOn),
            _red.withValues(alpha: 0),
          ], const [0, .3, .5, .7, 1]),
      );
    }
    c.restore();
    if (strike > 0) {
      final p = _clamp(tp.dx / W);
      c.drawRect(
        Rect.fromLTWH(0, tp.dy - 1.5 - 6 * strike, W, 3.0 + 12 * strike),
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(W, 0), [
            _red.withValues(alpha: 0),
            _red.withValues(alpha: .6 * .9 * strike),
            Colors.white.withValues(alpha: .9 * strike),
            _red.withValues(alpha: .6 * .9 * strike),
            _red.withValues(alpha: 0),
          ], [0, _clamp(p - .3), p, _clamp(p + .3), 1]),
      );
    }
    flash(c, _seg(t, 2.95, 3.25, _ei), _black);
  }

  // ----------------------------------------------------------------- B, le ruban
  void _ruban(Canvas c) {
    const knot = 1.2;
    final fly = _seg(t, 0, knot, _io);
    if (t < knot + .05) {
      final amp = H * .28 * (1.0 - fly) + h * .02, len = W * (1.4 - .75 * fly), thick = h * (.16 + .1 * fly);
      final head = _clamp(t / .7), alpha = 1.0 - _seg(t, knot - .08, knot + .05);
      final x0 = cx - (1.0 - fly) * W * .25;
      halo(c, Offset(cx, cy), W * .4, .12 * fly);
      const n = 160;
      final phase = t * 6;
      for (var i = 0; i < n; i++) {
        final a = i / n, b = (i + 1) / n;
        if (a > head) break;
        final xa = x0 - len / 2.0 + a * len, xb = x0 - len / 2.0 + b * len;
        final ya = cy + amp * math.sin(a * math.pi * 3.0 + phase), yb = cy + amp * math.sin(b * math.pi * 3.0 + phase);
        final tw = math.cos(a * math.pi * 3.0 + phase * 1.3).abs();
        final th = thick * (.25 + .75 * tw);
        final path = Path()
          ..moveTo(xa, ya - th / 2)
          ..lineTo(xb + .5, yb - th / 2)
          ..lineTo(xb + .5, yb + th / 2)
          ..lineTo(xa, ya + th / 2)
          ..close();
        c.drawPath(path, Paint()..color = HSLColor.fromAHSL(_clamp(alpha), 357, .92, (40 + 30 * tw) / 100).toColor());
      }
    }
    if (t >= knot - .06) {
      final f = t >= knot ? 1.0 - _seg(t, knot, knot + .5, _oc) : 0.0;
      final pop = _seg(t, knot - .06, knot + .35, _back), out = _seg(t, 2.65, 3.0, _ic);
      halo(c, Offset(cx, cy), w * (.6 + .3 * (1.0 - f)), .25 + .35 * f);
      final base = 1.15 - .15 * pop + .04 * _seg(t, knot + .35, 2.65, _io);
      final sx = base + .5 * out, sy = base * (1.0 - .985 * out);
      logo(c, cx, cy, sx: sx, sy: sy, alpha: _seg(t, knot - .06, knot + .1), bright: 1.0 + .8 * f + 2 * out);
      final s = _seg(t, 1.65, 2.25, _io);
      if (s > 0 && s < 1) {
        // a reflection crossing the letters
        final box = Rect.fromCenter(center: Offset(cx, cy), width: w * sx, height: h * sy);
        c.saveLayer(box, Paint()..blendMode = BlendMode.plus);
        logo(c, cx, cy, sx: sx, sy: sy);
        final gx = box.left + s * box.width * 1.3 - box.width * .15;
        c.save();
        c.translate(gx, cy);
        c.skew(-.4, 0);
        c.drawRect(
          Rect.fromLTWH(-u * 60, -box.height, u * 120, box.height * 2),
          Paint()
            ..blendMode = BlendMode.srcIn
            ..shader = ui.Gradient.linear(Offset(-u * 60, 0), Offset(u * 60, 0), const [
              Color(0x00FFFFFF),
              Color(0x59FFDCDC),
              Color(0x00FFFFFF),
            ], const [0.0, 0.5, 1.0]),
        );
        c.restore();
        c.restore();
      }
      if (out > 0) {
        final a = .9 * out * (1.0 - _seg(t, 3.0, 3.25));
        c.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: w * 1.5 * (1.0 + out), height: u * 4),
            Paint()..color = Colors.white.withValues(alpha: _clamp(a)));
      }
    }
    flash(c, _seg(t, 3.0, 3.3, _ei), _black);
  }

  // ----------------------------------------------------------------- C, le battement
  static const _slices = [(0.0, .27), (.27, .44), (.44, .685), (.685, 1.0)];
  static const _beats = [1.0, 1.18, 1.36, 1.54];

  void _battement(Canvas c) {
    const full = 1.75;
    final tp = Offset(cx + (_tri.dx - .5) * w, cy + (_tri.dy - .5) * h);
    if (t < 1.0) {
      final beat = math.max(math.exp(-math.pow((t - .25) / .05, 2)), math.exp(-math.pow((t - .55) / .05, 2)) * 1.2);
      final move = _seg(t, .75, 1.0, _ioc);
      final at = Offset(cx + (tp.dx - cx) * move, cy + (tp.dy - cy) * move);
      final sz = h * (.9 - .62 * move) * (1.0 + .18 * beat) * _seg(t, 0, .18, _oc);
      halo(c, at, sz * 2.2, .35 + .4 * beat);
      final tri = Path()
        ..moveTo(at.dx - sz * .38, at.dy - sz * .5)
        ..lineTo(at.dx + sz * .55, at.dy)
        ..lineTo(at.dx - sz * .38, at.dy + sz * .5)
        ..close();
      c.drawPath(tri,
          Paint()
            ..color = _red.withValues(alpha: .9)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 26 * (.5 + beat)));
      c.drawPath(tri, Paint()..color = _red);
    }
    final f = t >= full ? 1.0 - _seg(t, full, full + .6, _oc) : 0.0;
    final shake = t >= full ? (1.0 - _seg(t, full, full + .3)) * u * 8 : 0.0;
    final push = 1.0 + .06 * _seg(t, full, 2.9, _io), out = _seg(t, 2.85, 3.3, _ei);
    if (t >= full) halo(c, Offset(cx, cy), w * (.55 + .3 * (1.0 - f)), .18 + .4 * f);
    final ox = shake * math.sin(t * 90), oy = shake * math.cos(t * 77);
    for (var i = 0; i < 4; i++) {
      final b = _beats[i];
      if (t < b - .02) continue;
      final kk = _seg(t, b - .02, b + .12, _oc);
      logo(c, cx + ox, cy + oy,
          scale: (1.7 - .7 * kk) * push * (1.0 + .25 * out),
          alpha: kk * (1.0 - out),
          x0: _slices[i].$1,
          x1: _slices[i].$2,
          bright: 1.0 + .9 * (1.0 - _seg(t, b, b + .25)) + .6 * f);
    }
    if (t >= full && t < full + .1) flash(c, .25 * (1.0 - _seg(t, full, full + .1)));
  }

  // ----------------------------------------------------------------- D, le signal
  void _signal(Canvas c) {
    const lock = .98, off = 2.75;
    if (t < .05 || t > 3.12) {
      if (t > 3.0 && t < 3.12) halo(c, Offset(cx, cy), u * 30, 1);
      return;
    }
    final openX = _seg(t, .05, .18, _oc), openY = _seg(t, .15, .32, _oc);
    final offY = _seg(t, off, 2.92, _ic), offX = _seg(t, 2.9, 3.08, _ic);
    c.save();
    c.translate(cx, cy);
    c.scale(math.max(.002, openX * (1.0 - .995 * offX)), math.max(.004, openY * (1.0 - offY)));
    c.translate(-cx, -cy);
    if (t < lock) {
      snow(c, .85);
      final kk = _seg(t, .35, lock);
      final gl = [.55, .72, .8].any((a) => t >= a && t < a + .05);
      logo(c, cx + (gl ? u * 40 : 0), cy, alpha: .25 + .5 * kk);
      if (gl) logo(c, cx - u * 30, cy, alpha: .5, tint: _Tint.cyan);
      flash(c, .08);
    } else {
      final hk = 1.0 - _seg(t, lock, lock + .6, _oc);
      halo(c, Offset(cx, cy), w * (.55 + .3 * (1.0 - hk)), .2 + .4 * hk);
      final gl = [1.6, 1.95, 2.05].any((a) => t >= a && t < a + .05);
      final split = u * (24 * hk + (gl ? 30 : 0));
      logo(c, cx - split, cy, alpha: .55, tint: _Tint.cyan, plus: true);
      logo(c, cx + split * .6, cy + (gl ? u * 6 : 0), alpha: .4, tint: _Tint.gold, plus: true);
      logo(c, cx, cy, scale: 1.0 + .03 * hk, bright: 1.0 + .8 * hk);
      if (gl) glitchBand(c, u * 40, u * 30);
      snow(c, .06 + .25 * hk);
      scan(c, .18);
    }
    flash(c, offY);
    c.restore();
  }

  // ----------------------------------------------------------------- E, le hacker
  static const _eLines = [
    (.05, '> vjod --connect seedbox'),
    (.22, '  liaison chiffrée ........ OK'),
    (.46, '  sources trouvées : 30'),
    (.68, '> decrypt --signal vjod.4.0'),
    (.88, '  clé acceptée · déchiffrement…'),
  ];

  void rain(Canvas c, double a) {
    if (a <= 0) return;
    final list = <(int, Offset, double, Color)>[];
    for (var i = 0; i < k.rain.length; i++) {
      final col = k.rain[i];
      final y = ((t * col.s * u * 900.0 + col.o * H) % (H + u * 400)) - u * 200;
      for (var j = 0; j < 9; j++) {
        list.add((pick(i * 31.0 + j + (t * 14).floor()), Offset(col.x * W, y - j * u * 26), u * 22,
            _red.withValues(alpha: _clamp(a * (1.0 - j / 9)))));
      }
    }
    glyphs(c, list);
  }

  void _hacker(Canvas c) {
    const drop = 1.6, off = 2.95;
    if (t > 3.3) return;
    final offY = _seg(t, off, 3.12, _ic), offX = _seg(t, 3.1, 3.28, _ic);
    c.save();
    crt(c, offY, offX);
    rain(c, t < drop ? .35 * _seg(t, 0, .4) : .12 * (1.0 - _seg(t, drop, drop + .5)) + .06);
    final termA = t < drop ? 1.0 : 1.0 - _seg(t, drop, drop + .25);
    if (termA > 0) {
      final fs = u * 40;
      var y = H * .08;
      for (final (at, txt) in _eLines) {
        if (t < at) continue;
        final n = (_clamp((t - at) / .16) * txt.length).floor();
        final col = txt.startsWith('>') ? Colors.white.withValues(alpha: .9 * termA) : _red.withValues(alpha: .95 * termA);
        final wd = text(c, txt.substring(0, n), Offset(W * .06, y), fs, col);
        if (n < txt.length && (t * 10).floor().isEven) {
          c.drawRect(Rect.fromLTWH(W * .06 + wd + u * 4, y, u * 20, fs), Paint()..color = col);
        }
        y += u * 58;
      }
    }
    if (t >= .95 && t < drop + .05) {
      // the logo decrypting, cell by cell
      final cw = w / k.cols, ch = h / k.rows;
      final prog = _seg(t, 1.0, drop - .05);
      final list = <(int, Offset, double, Color)>[];
      final solid = Paint();
      for (final p in k.cells) {
        final x = cx - w / 2.0 + (p.q + .5) * cw, y = cy - h / 2.0 + (p.r + .5) * ch;
        if (p.rnd < prog * 1.05) {
          solid.color = _red.withValues(alpha: .95 * p.a);
          c.drawRect(Rect.fromCenter(center: Offset(x, y), width: cw * .8, height: ch * .9), solid);
        } else if (_rnd.nextBool()) {
          list.add((pick(p.q * 7.0 + p.r * 13.0 + (t * 30).floor()), Offset(x, y), ch * 1.15,
              Colors.white.withValues(alpha: .55 * p.a)));
        }
      }
      glyphs(c, list);
    }
    if (t >= drop) {
      final hk = 1.0 - _seg(t, drop, drop + .6, _oc);
      halo(c, Offset(cx, cy), w * (.55 + .3 * (1.0 - hk)), .18 + .4 * hk);
      final gl = [2.1, 2.18, 2.4].any((a) => t >= a && t < a + .045);
      final split = u * (26 * hk + (gl ? 34 : 0));
      logo(c, cx - split, cy, alpha: .5, tint: _Tint.cyan, plus: true);
      logo(c, cx + split * .6, cy + (gl ? u * 6 : 0), alpha: .35, tint: _Tint.gold, plus: true);
      logo(c, cx, cy, scale: 1.0 + .03 * hk, bright: 1.0 + .8 * hk);
      if (gl) glitchBand(c, u * 46, u * 40);
      if (t >= drop + .15 && ((((t - drop) * 6).floor().isEven) || t > drop + .8)) {
        const s = '[ ACCÈS AUTORISÉ ]';
        final n = (_seg(t, drop + .15, drop + .4) * s.length).floor();
        final fs = u * 30;
        final str = s.substring(0, n);
        text(c, str, Offset(cx - textWidth(s, fs) / 2, cy + h * .62 - fs / 2), fs, _red.withValues(alpha: .95));
      }
      scan(c, .2);
      snow(c, .04 + .2 * hk);
    }
    if (t >= drop && t < drop + .08) flash(c, .3 * (1.0 - _seg(t, drop, drop + .08)));
    flash(c, offY);
    c.restore();
  }

  // ----------------------------------------------------------------- F, la plateforme
  void _plateforme(Canvas c) {
    const hit = 1.25, dis = 2.4;
    final cw = w / k.cols, ch = h / k.rows;
    if (t < hit + .2) {
      halo(c, Offset(cx, cy), w * .7, .25 * _seg(t, .3, hit));
      final list = <(int, Offset, double, Color)>[];
      final solid = Paint();
      for (final p in k.cells) {
        final kk = _seg(t, .15 + p.delay, hit - .05, _oc);
        if (kk <= 0) continue;
        final tx = cx - w / 2.0 + (p.q + .5) * cw, ty = cy - h / 2.0 + (p.r + .5) * ch;
        final x = tx + p.sx * W * (1.0 - kk), y = ty + p.sy * H * (1.0 - kk);
        if (kk > .97) {
          solid.color = _red.withValues(alpha: p.a);
          c.drawRect(Rect.fromCenter(center: Offset(x, y), width: cw * .8, height: ch * .9), solid);
        } else {
          final v = (90 + 120 * (1.0 - kk)).round();
          list.add((pick(p.seed + (t * 24).floor()), Offset(x, y), ch * 1.2,
              Color.fromRGBO(255, v, v, _clamp(.35 + .6 * kk))));
        }
      }
      glyphs(c, list);
    }
    if (t >= hit) {
      final hk = 1.0 - _seg(t, hit, hit + .7, _oc), vis = _seg(t, hit, hit + .18);
      final d = _seg(t, dis, 2.95, _ic);
      halo(c, Offset(cx, cy), w * (.6 + .3 * (1.0 - hk)), (.2 + .45 * hk) * (1.0 - d));
      if (d <= 0) {
        logo(c, cx - 18 * hk * u, cy, alpha: .45 * vis, tint: _Tint.cyan, plus: true);
        final sc = 1.04 - .04 * _seg(t, hit, hit + .4, _oc) + .035 * _seg(t, hit + .4, dis, _io);
        logo(c, cx, cy, alpha: vis, scale: sc, bright: 1.0 + .9 * hk);
        final sl = _seg(t, 1.7, 2.25, _io);
        if (sl > 0 && sl < 1) {
          // the reading line sweeping the logo
          final y = cy - h * .55 + sl * h * 1.1;
          final r = Rect.fromLTWH(cx - w * .55, y - u * 30, w * 1.1, u * 60);
          c.drawRect(r,
              Paint()
                ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, const [
                  Color(0x00FFFFFF),
                  Color(0x80FFE6E6),
                  Color(0x00FFFFFF),
                ], const [0.0, 0.5, 1.0]));
          glyphs(c, [
            for (var i = 0; i < 24; i++)
              (pick(i + (t * 30).floor()), Offset(cx - w * .5 + i * w / 23, y - u * 22), ch * 1.2,
                  Colors.white.withValues(alpha: .8)),
          ]);
        }
        if (t >= hit + .3) {
          const s = 'STREAM · LIVE · ON DEMAND';
          final n = (_seg(t, hit + .3, hit + .75) * s.length).floor();
          final fs = u * 34;
          text(c, s.substring(0, n), Offset(cx - textWidth(s, fs) / 2, cy + h * .62 - fs / 2), fs,
              _red.withValues(alpha: .9 * _seg(t, hit + .3, hit + .6)));
        }
      } else {
        // the logo dissolving into blocks
        final sc = 1.035 + .25 * d;
        final solid = Paint();
        final list = <(int, Offset, double, Color)>[];
        for (final p in k.cells) {
          final x = cx + (-w / 2.0 + (p.q + .5) * cw) * sc, y = cy + (-h / 2.0 + (p.r + .5) * ch) * sc;
          if (p.rnd < d * 1.1) {
            if (p.rnd > d * 1.1 - .12) {
              list.add((pick(p.seed + (t * 30).floor()), Offset(x + p.sx * W * .3 * d, y + p.sy * H * .3 * d),
                  ch * 1.2, Colors.white.withValues(alpha: _clamp(.7 * (1.0 - d)))));
            }
            continue;
          }
          solid.color = _red.withValues(alpha: p.a);
          c.drawRect(Rect.fromCenter(center: Offset(x, y), width: cw * sc + 1, height: ch * sc + 1), solid);
        }
        glyphs(c, list);
      }
      scan(c, .14 * (1.0 - d));
    }
    if (t >= hit && t < hit + .07) flash(c, .35 * (1.0 - _seg(t, hit, hit + .07)));
  }

  // ----------------------------------------------------------------- G, les lignes de commande
  static const _gTerm = [
    (0.02, .22, 'root@vjod:~# ', 'ssh seedbox.vjod', 'cmd'),
    (0.26, 0.0, 'Connexion établie · chiffrement AES-256 · clé 4096 bits', '', 'out'),
    (0.30, 0.0, 'Bienvenue sur la seedbox de VJOD.', '', 'dim'),
    (0.48, .70, 'root@seedbox:~# ', './ma_tv --sources 30 --check', 'cmd'),
    (0.74, .98, '', '', 'bar'),
    (1.02, 1.18, 'root@seedbox:~# ', 'cat /dev/vjod | decrypt --ascii', 'cmd'),
    (1.22, 0.0, '', '', 'hex'),
  ];

  String hexLine(int seed) {
    final b = StringBuffer();
    for (var i = 0; i < 16; i++) {
      b.write((((math.sin(seed * 13.0 + i) * 255).abs().floor()) & 255).toRadixString(16).padLeft(2, '0'));
      b.write(' ');
    }
    return b.toString();
  }

  void _terminal(Canvas c) {
    const play = 2.02, off = 2.92;
    if (t > 3.26) return;
    final offY = _seg(t, off, 3.08, _ic), offX = _seg(t, 3.06, 3.24, _ic);
    c.save();
    crt(c, offY, offX);
    final fs = u * 30, lh = u * 40, x0 = W * .05;
    final termA = t < play ? 1.0 : 1.0 - _seg(t, play, play + .3);
    var y = H * .06;
    final white = Colors.white.withValues(alpha: termA);
    if (termA > 0) {
      for (final (at, end, a, b, kind) in _gTerm) {
        if (t < at) continue;
        switch (kind) {
          case 'cmd':
            final n = (_seg(t, at, end) * b.length).floor();
            final w0 = text(c, a, Offset(x0, y), fs, _red.withValues(alpha: termA));
            final w1 = text(c, b.substring(0, n), Offset(x0 + w0, y), fs, white);
            if (t < end + .05 && (t * 12).floor().isEven) {
              c.drawRect(Rect.fromLTWH(x0 + w0 + w1 + u * 4, y, u * 18, fs), Paint()..color = white);
            }
          case 'out':
            text(c, a, Offset(x0, y), fs, Colors.white.withValues(alpha: .85 * termA));
          case 'dim':
            text(c, a, Offset(x0, y), fs, Colors.white.withValues(alpha: .45 * termA));
          case 'bar':
            final kk = _seg(t, at, end);
            const n = 30;
            final f = (kk * n).round();
            final cell = fs * .6;
            final red = Paint()..color = _red.withValues(alpha: termA);
            final dim = Paint()..color = _red.withValues(alpha: .3 * termA);
            final w0 = text(c, '[', Offset(x0, y), fs, _red.withValues(alpha: termA));
            for (var i = 0; i < n; i++) {
              c.drawRect(Rect.fromLTWH(x0 + w0 + i * cell, y + fs * .1, cell * .9, fs * .8), i < f ? red : dim);
            }
            final ok = (kk * 30).round();
            text(c, ']${'${(kk * 100).round()}'.padLeft(4)}%  $ok/30 sources${kk >= 1 ? '  OK' : ''}',
                Offset(x0 + w0 + n * cell, y), fs, _red.withValues(alpha: termA));
          case 'hex':
            final lines = (_seg(t, at, 1.36) * 2.99).floor();
            for (var i = 0; i < lines; i++) {
              text(c, '0x${(0x7f3a00 + i * 16).toRadixString(16)}  ${hexLine(i + (t * 20).floor())}', Offset(x0, y), fs,
                  Colors.white.withValues(alpha: .35 * termA));
              if (i < lines - 1) y += lh;
            }
        }
        y += lh;
      }
    }
    // the logo printed in characters, row by row
    if (t >= 1.36 && t < play + .12) {
      final rows = k.asciiRows, cols = k.asciiCols;
      final prog = _seg(t, 1.36, 1.86) * rows;
      final shown = prog.floor();
      final cwid = w / cols, rh = h * .62 / rows;
      final top = cy - h * .18;
      final fade = t >= play ? 1.0 - _seg(t, play, play + .12) : 1.0;
      final p = Paint();
      for (var r = 0; r < math.min(shown + 1, rows); r++) {
        final upto = r == shown ? ((prog - r) * cols).floor() : cols;
        for (var q = 0; q < upto; q++) {
          final lv = k.ascii[r * cols + q];
          if (lv <= 0) continue;
          p.color = _red.withValues(alpha: .95 * fade * lv);
          c.drawRect(Rect.fromLTWH(cx - w / 2.0 + q * cwid, top + r * rh, cwid * .92, rh * .9), p);
        }
      }
    }
    final py = H * .86;
    if (t >= 1.88 && t < play) {
      const a = 'root@seedbox:~# ', b = './vjod --play';
      final n = (_seg(t, 1.88, 2.0) * b.length).floor();
      final w0 = text(c, a, Offset(x0, py), fs, _red);
      text(c, b.substring(0, n), Offset(x0 + w0, py), fs, Colors.white);
    }
    if (t >= play) {
      final hk = 1.0 - _seg(t, play, play + .6, _oc);
      halo(c, Offset(cx, cy), w * (.55 + .3 * (1.0 - hk)), .2 + .45 * hk);
      final gl = [2.45, 2.52].any((a) => t >= a && t < a + .04);
      final split = u * (24 * hk + (gl ? 30 : 0));
      logo(c, cx - split, cy, alpha: .5, tint: _Tint.cyan, plus: true);
      logo(c, cx, cy,
          scale: 1.05 - .05 * _seg(t, play, play + .35, _oc) + .03 * _seg(t, play + .35, off, _io), bright: 1.0 + .9 * hk);
      if (gl) glitchBand(c, u * 44, u * 36);
      final w0 = text(c, '▶ lecture ', Offset(x0, py), fs, _red);
      if ((t * 4).floor().isEven) c.drawRect(Rect.fromLTWH(x0 + w0, py, u * 18, fs), Paint()..color = _red);
      scan(c, .16);
    }
    if (t >= play && t < play + .07) flash(c, .35 * (1.0 - _seg(t, play, play + .07)));
    flash(c, offY);
    c.restore();
  }
}
