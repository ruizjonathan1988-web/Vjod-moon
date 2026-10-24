import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/layout/screen_form.dart';
import 'package:moonfin/util/platform_detection.dart';

// Window sizes in logical pixels as a Galaxy Z Fold8 and a regular phone
// report them.
const _coverPortrait = Size(467, 737);
const _coverLandscape = Size(737, 467);
const _openPortrait = Size(734, 974);
const _openLandscape = Size(974, 734);
const _phone = Size(412, 915);

void main() {
  // A forced posture watches the window through the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => PlatformDetection.setInterfaceLayout(InterfaceLayout.phone));
  tearDown(() {
    Tabletop.forced.value = false;
    PlatformDetection.setInterfaceLayout(InterfaceLayout.automatic);
  });

  group('ScreenForm.classify', () {
    ScreenForm touch(Size size) => ScreenForm.classify(size, mobileUi: true);

    test('tells a Fold8 cover screen from a regular phone', () {
      expect(touch(_coverPortrait), ScreenForm.cover);
      expect(touch(_coverLandscape), ScreenForm.cover);
      expect(touch(_phone), ScreenForm.phone);
      expect(touch(const Size(915, 412)), ScreenForm.phone);
    });

    test('an opened foldable is unfolded whichever way it is held', () {
      expect(touch(_openPortrait), ScreenForm.unfolded);
      expect(touch(_openLandscape), ScreenForm.unfolded);
    });

    test('the rail leaves an opened Fold8 unfolded', () {
      expect(touch(const Size(734 - 84, 974)), ScreenForm.unfolded);
    });

    test('TV and desktop keep their own layouts', () {
      expect(
        ScreenForm.classify(const Size(960, 540), mobileUi: false),
        ScreenForm.large,
      );
    });

    test('an empty window is a phone', () {
      expect(touch(Size.zero), ScreenForm.phone);
    });
  });

  group('Tabletop', () {
    test('can be forced opened, either way up', () {
      expect(Tabletop.canForce(_openLandscape), isTrue);
      expect(Tabletop.canForce(_openPortrait), isTrue);
      expect(Tabletop.canForce(_coverLandscape), isFalse);
      expect(Tabletop.canForce(_phone), isFalse);
    });

    test('a forced posture folds across the middle', () {
      expect(Tabletop.foldOf(_openLandscape, const []), isNull);
      Tabletop.forced.value = true;
      final fold = Tabletop.foldOf(_openLandscape, const []);
      expect(fold?.top, 367);
      expect(fold?.width, 974);
      expect(Tabletop.foldOf(_openPortrait, const [])?.top, 487);
    });

    test('finds a half-open fold across the screen', () {
      final fold = Tabletop.foldOf(const Size(880, 760), const [
        DisplayFeature(
          bounds: Rect.fromLTWH(0, 380, 880, 0),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ]);
      expect(fold?.top, 380);
    });

    test('ignores a flat phone, a book posture and a cutout', () {
      const size = Size(880, 760);
      expect(
        Tabletop.foldOf(size, const [
          DisplayFeature(
            bounds: Rect.fromLTWH(0, 380, 880, 0),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureFlat,
          ),
        ]),
        isNull,
      );
      expect(
        Tabletop.foldOf(size, const [
          DisplayFeature(
            bounds: Rect.fromLTWH(440, 0, 0, 760),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ]),
        isNull,
      );
      expect(
        Tabletop.foldOf(size, const [
          DisplayFeature(
            bounds: Rect.fromLTWH(400, 0, 80, 30),
            type: DisplayFeatureType.cutout,
            state: DisplayFeatureState.unknown,
          ),
        ]),
        isNull,
      );
    });

    test('reads the hinge posture for the screen information', () {
      expect(Tabletop.hingeOf(const []), HingePosture.none);
      expect(
        Tabletop.hingeOf(const [
          DisplayFeature(
            bounds: Rect.fromLTWH(440, 0, 0, 760),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureFlat,
          ),
        ]),
        HingePosture.flat,
      );
      expect(
        Tabletop.hingeOf(const [
          DisplayFeature(
            bounds: Rect.fromLTWH(0, 380, 880, 0),
            type: DisplayFeatureType.fold,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ]),
        HingePosture.halfOpened,
      );
    });
  });
}
