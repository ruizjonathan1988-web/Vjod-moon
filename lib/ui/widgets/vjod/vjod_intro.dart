// The opening of VJOD, once per launch: a blade of red light sweeps across
// the black and draws the logo, the play button inside the D strikes (flash,
// glow, a low boom), the logo pushes in slowly, then the camera dives into
// the play button and the app opens. About 3 seconds, with its own sound
// (made for VJOD, assets/sounds/vjod_intro.ogg). Any key or a tap skips it.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../../util/platform_detection.dart';

class VjodIntro extends StatefulWidget {
  final VoidCallback onDone;

  const VjodIntro({super.key, required this.onDone});

  /// Shown once per launch only (not on a change of profile).
  static bool played = false;

  @override
  State<VjodIntro> createState() => _VjodIntroState();
}

class _VjodIntroState extends State<VjodIntro> with SingleTickerProviderStateMixin {
  static const _total = 3.25; // seconds
  static const _hit = 1.05;
  static const _dive = 2.45;
  static const _logo = AssetImage('assets/images/vjod_intro_logo.png');
  static const _black = Color(0xFF040404);
  static const _red = Color(0xFFE50914);

  // Where the play button sits in the logo picture (1024 × 572).
  static const _tri = Offset(0.786, 0.511);
  static const _aspect = 1024 / 572;

  late final AnimationController _c;
  final _focus = FocusNode(debugLabel: 'vjod_intro');
  Player? _player;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    VjodIntro.played = true;
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: (_total * 1000).round()));
    _c.forward().whenComplete(_finish);
    unawaited(_playSound());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(precacheImage(_logo, context));
  }

  Future<void> _playSound() async {
    // media_kit isn't set up on Apple devices, and a browser blocks a sound
    // the viewer didn't ask for: silent there.
    if (kIsWeb || PlatformDetection.isIOS || PlatformDetection.isMacOS || PlatformDetection.isAppleTV) return;
    try {
      final p = Player();
      _player = p;
      await p.open(Media('asset:///assets/sounds/vjod_intro.ogg'));
    } catch (_) {}
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  void _skip() {
    if (_done) return;
    _c.stop();
    unawaited(_player?.stop());
    _finish();
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    final p = _player;
    // Let the sound's tail finish over the home screen, then free it.
    if (p != null) Timer(const Duration(seconds: 3), () => unawaited(p.dispose()));
    super.dispose();
  }

  static double _seg(double t, double a, double b, [Curve curve = Curves.linear]) =>
      curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
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
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => LayoutBuilder(builder: (context, box) => _frame(box.biggest, _c.value * _total)),
          ),
        ),
      ),
    );
  }

  Widget _frame(Size screen, double t) {
    // The logo picture: two thirds of the width, never taller than half the screen.
    var w = screen.width * 0.78;
    if (w / _aspect > screen.height * 0.58) w = screen.height * 0.58 * _aspect;
    final h = w / _aspect;

    // 1. The blade of light draws the logo from left to right.
    final sweep = _seg(t, 0.22, _hit, Curves.easeInOutCubic);
    final front = 0.09 + sweep * 0.82; // the letters span 12 % to 88 % of the picture
    final bladeOn = t < _hit + 0.12 ? 1.0 - _seg(t, _hit - 0.05, _hit + 0.12) : 0.0;

    // 2. The strike: flash, glow from the play button, a jolt.
    final strike = t >= _hit ? 1.0 - _seg(t, _hit, _hit + 0.65, Curves.easeOutCubic) : 0.0;
    final jolt = t >= _hit ? math.sin(math.pi * _seg(t, _hit, _hit + 0.28)) : 0.0;
    final glow = t >= _hit ? (0.35 + 0.65 * strike) * (1.0 - _seg(t, _dive, _dive + 0.3)) : 0.0;

    // 3. Slow push in, then 4. the dive into the play button.
    final intro = 0.93 + 0.07 * _seg(t, 0.22, _hit, Curves.easeOutCubic);
    final push = 1.0 + 0.07 * _seg(t, _hit, _dive, Curves.easeInOut);
    final dive = _seg(t, _dive, 3.05, Curves.easeInCubic);
    final scale = intro * push * (1.0 + 0.045 * jolt) * math.pow(55, dive).toDouble();
    final toBlack = _seg(t, 2.95, _total, Curves.easeIn);

    // The play button, in pixels from the picture's centre: the dive brings it
    // to the middle of the screen while zooming on it.
    final triFromCentre = Offset((_tri.dx - 0.5) * w, (_tri.dy - 0.5) * h);
    final shift = -triFromCentre * dive;

    final picture = Image(
      image: _logo,
      width: w,
      height: h,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );

    // The letters only where the light has passed, a little dim until the strike.
    final revealed = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(
        colors: const [Colors.white, Colors.white, Colors.transparent],
        stops: [0, math.max(0, front - 0.035), front],
      ).createShader(r),
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(_brightness(t < _hit ? 0.8 : 1.0 + 0.55 * strike)),
        child: picture,
      ),
    );

    final logo = SizedBox(
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          revealed,
          // the blade at the front of the drawing
          if (bladeOn > 0)
            Positioned(
              left: front * w - 14,
              top: h * 0.18,
              height: h * 0.64,
              width: 28,
              child: Opacity(opacity: bladeOn, child: const _Blade()),
            ),
        ],
      ),
    );

    final moving = Transform.translate(
      offset: shift,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment(_tri.dx * 2 - 1, _tri.dy * 2 - 1),
        child: logo,
      ),
    );

    final centre = Offset(screen.width / 2, screen.height / 2);
    final tri = centre + triFromCentre * intro * push + shift;
    return Stack(
      fit: StackFit.expand,
      children: [
        // a faint red halo that follows the blade
        if (bladeOn > 0)
          Positioned.fill(
            child: CustomPaint(
              painter: _Halo(
                centre: Offset(centre.dx + (front - 0.5) * w * intro, centre.dy),
                radius: w * 0.45,
                strength: 0.22 * bladeOn,
              ),
            ),
          ),
        // the glow of the play button
        if (glow > 0)
          Positioned.fill(
            child: CustomPaint(painter: _Halo(centre: tri, radius: w * (0.35 + 0.5 * (1 - strike)), strength: 0.5 * glow)),
          ),
        Center(child: moving),
        // the flash: a horizontal streak through the play button
        if (strike > 0)
          Positioned(
            left: 0,
            right: 0,
            top: tri.dy - 1.5 - 6 * strike,
            height: 3 + 12 * strike,
            child: IgnorePointer(
              child: Opacity(
                opacity: strike * 0.9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        _red.withValues(alpha: 0.6),
                        Colors.white,
                        _red.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                      stops: [
                        0,
                        math.max(0.0, tri.dx / screen.width - 0.3),
                        (tri.dx / screen.width).clamp(0.0, 1.0),
                        math.min(1.0, tri.dx / screen.width + 0.3),
                        1,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (toBlack > 0) ColoredBox(color: _black.withValues(alpha: toBlack)),
      ],
    );
  }

  /// Brightness as a colour matrix (1 = as drawn).
  static List<double> _brightness(double k) => [
    k, 0, 0, 0, 0, //
    0, k, 0, 0, 0,
    0, 0, k, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// The blade of light: white core, red glow.
class _Blade extends StatelessWidget {
  const _Blade();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Colors.transparent, Color(0xAAE50914), Colors.white, Color(0xAAE50914), Colors.transparent],
        stops: [0, 0.3, 0.5, 0.7, 1],
      ),
      boxShadow: [BoxShadow(color: const Color(0xFFE50914).withValues(alpha: 0.7), blurRadius: 30, spreadRadius: 4)],
    ),
  );
}

/// A soft red light around a point.
class _Halo extends CustomPainter {
  final Offset centre;
  final double radius;
  final double strength;

  _Halo({required this.centre, required this.radius, required this.strength});

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0 || strength <= 0) return;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFE50914).withValues(alpha: strength),
          const Color(0xFFE50914).withValues(alpha: strength * 0.35),
          Colors.transparent,
        ],
        stops: const [0, 0.35, 1],
      ).createShader(Rect.fromCircle(center: centre, radius: radius));
    canvas.drawCircle(centre, radius, paint);
  }

  @override
  bool shouldRepaint(_Halo old) => old.centre != centre || old.radius != radius || old.strength != strength;
}
