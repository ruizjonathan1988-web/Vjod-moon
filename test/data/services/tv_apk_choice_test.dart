import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/app_update_service.dart';

void main() {
  const names = ['moonfin-fold.apk', 'moonfin-tv.apk', 'moonfin-tv-arm32.apk'];

  test('une vieille Fire TV (32 bits) prend la version allégée', () {
    expect(selectTvApkName(names, arm32: true), 'moonfin-tv-arm32.apk');
  });

  test('les autres boîtiers gardent la version complète', () {
    expect(selectTvApkName(names, arm32: false), 'moonfin-tv.apk');
  });

  test('sans version allégée, tout le monde prend la complète', () {
    expect(selectTvApkName(['moonfin-fold.apk', 'moonfin-tv.apk'], arm32: true), 'moonfin-tv.apk');
  });

  test('jamais l’APK du téléphone', () {
    expect(selectTvApkName(['moonfin-fold.apk'], arm32: false), isNull);
  });
}
