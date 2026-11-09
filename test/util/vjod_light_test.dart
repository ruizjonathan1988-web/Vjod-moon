import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/util/vjod_light.dart';

void main() {
  const gb = 1073741824;
  Map<String, dynamic> mem(num total, {String maker = 'SDMC', int sdk = 30}) =>
      {'totalMem': total, 'lowRam': false, 'manufacturer': maker, 'sdk': sdk};

  bool auto(Map<String, dynamic> m, {bool web = false, bool tv = false}) =>
      vjodLightFor(mode: DevicePerformanceMode.auto, memory: m, isWeb: web, isTv: tv);

  test('box SFR, ADT-3, projecteur, Fire TV (2 Go au plus) : marche allégée', () {
    expect(auto(mem(2 * gb), tv: true), isTrue);
    expect(auto(mem(1.5 * gb, maker: 'Amazon'), tv: true), isTrue);
  });

  test('box dont la mémoire n’a pas pu être lue : allégée par prudence', () {
    expect(auto(const {}, tv: true), isTrue);
  });

  test('navigateur : allégé', () {
    expect(auto(const {}, web: true), isTrue);
  });

  test('téléphone (le Fold) et grosse box : tout reste', () {
    expect(auto(mem(12 * gb)), isFalse);
    expect(auto(mem(2 * gb)), isFalse, reason: 'un téléphone n’est pas concerné par le seuil des box');
    expect(auto(mem(4 * gb), tv: true), isFalse);
  });

  test('le réglage Performance l’emporte', () {
    expect(vjodLightFor(mode: DevicePerformanceMode.standard, memory: mem(1 * gb), isWeb: true, isTv: true), isFalse);
    expect(vjodLightFor(mode: DevicePerformanceMode.reduced, memory: mem(12 * gb), isWeb: false, isTv: false), isTrue);
  });

  test('pastille En route : 5 min en marche allégée, 45 s sinon', () {
    expect(VjodLight.enRouteBadgeInterval(true), const Duration(minutes: 5));
    expect(VjodLight.enRouteBadgeInterval(false), const Duration(seconds: 45));
  });
}
