// VJOD 4.17: while a VJOD player is open with background playback on,
// Moonfin's lifecycle handler leaves the player alone; switched off on the
// device, the player is released as before.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/services/vjod/background_playback.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<PreferenceStore>(store);
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('le lecteur ouvert garde la lecture, seul son propriétaire l’arrête', () async {
    final player = Object();
    await VjodBackgroundPlayback.start(player, title: '1  TF1', onCommand: (_) {});
    expect(VjodBackgroundPlayback.keepsPlaying, isTrue);
    await VjodBackgroundPlayback.stop(Object());
    expect(VjodBackgroundPlayback.keepsPlaying, isTrue);
    await VjodBackgroundPlayback.stop(player);
    expect(VjodBackgroundPlayback.keepsPlaying, isFalse);
  });

  test('coupé sur l’appareil : comme avant', () async {
    await VjodBackgroundPlayback.setEnabled(false);
    expect(VjodBackgroundPlayback.enabled, isFalse);
    await VjodBackgroundPlayback.start(Object(), title: 'Dune', onCommand: (_) {});
    expect(VjodBackgroundPlayback.keepsPlaying, isFalse);
  });
}
