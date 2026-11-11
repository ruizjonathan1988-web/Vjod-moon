import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/playback/loading_animation_widget.dart';

void main() {
  test('petit appareil (Bbox 4K) : rotation à plat', () {
    expect(vjodFlatLogoTurn(true), isTrue);
    expect(vjodFlatLogoTurn(false), isFalse);
  });

  test('la rotation à plat ne retourne jamais le logo', () {
    for (var i = 0; i <= 100; i++) {
      final w = vjodLogoTurnWidth(math.pi * i / 100);
      expect(w, greaterThan(0));
      expect(w, lessThanOrEqualTo(1));
    }
    expect(vjodLogoTurnWidth(0), 1);
    expect(vjodLogoTurnWidth(math.pi), closeTo(1, 1e-9));
  });
}
