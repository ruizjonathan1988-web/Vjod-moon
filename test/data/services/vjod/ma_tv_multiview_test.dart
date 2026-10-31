// VJOD 4.7: Multiview only where it can't slow the device down.
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/ma_tv_multiview.dart';

int _tiles({bool web = false, bool android = false, bool desktop = false, bool apple = false, bool reduced = false, String maker = ''}) =>
    multiviewTilesFor(web: web, android: android, desktop: desktop, apple: apple, reduced: reduced, manufacturer: maker);

void main() {
  test('deux chaînes sur Android et dans le navigateur, quatre sur ordinateur', () {
    expect(_tiles(android: true, maker: 'NVIDIA'), 2);
    expect(_tiles(web: true), 2);
    expect(_tiles(desktop: true), 4);
  });

  test('jamais sur Fire TV, en mode léger, sur Mac ou iPad', () {
    expect(_tiles(android: true, maker: 'Amazon'), 0);
    expect(_tiles(android: true, maker: 'amazon '), 0);
    expect(_tiles(android: true, reduced: true), 0);
    expect(_tiles(desktop: true, reduced: true), 0);
    expect(_tiles(apple: true), 0);
  });
}
