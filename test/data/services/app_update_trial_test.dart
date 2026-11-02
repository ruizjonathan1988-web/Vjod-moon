// VJOD 4.14: a device set to trial versions takes each new build first; the
// setting stays on the device and makes the next check happen at once.
import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/services/app_update_service.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('versions d’essai : réglage de l’appareil, vérification refaite tout de suite', () async {
    SharedPreferences.setMockInitialValues({'app_update_last_check_ms': 123456});
    final store = PreferenceStore();
    await store.init();
    final updates = AppUpdateService(store, UserPreferences(store));
    expect(updates.betaChannel, isFalse);
    await updates.setBetaChannel(true);
    expect(updates.betaChannel, isTrue);
    expect(store.getBool(AppUpdateService.betaChannelKey), isTrue);
    expect(store.getInt('app_update_last_check_ms'), 0);
    await updates.setBetaChannel(false);
    expect(updates.betaChannel, isFalse);
  });
}
