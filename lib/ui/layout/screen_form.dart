import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';

import '../../util/platform_detection.dart';

/// The shape of the window the app draws in, read from its live size so a
/// foldable changes layout the moment it is folded or opened. Nothing here
/// knows device models: a Galaxy Z Fold8 lands on [cover] folded and
/// [unfolded] opened because of its proportions, and a tablet or a phone in
/// split screen lands wherever its window does.
enum ScreenForm {
  /// A regular phone: narrow and tall.
  phone,

  /// Narrow but short for its width, like the 10:16 cover screen of a
  /// Galaxy Z Fold8. Height is what runs out first.
  cover,

  /// A large touch screen: an opened foldable or a tablet.
  unfolded,

  /// TV, desktop and pointer web, which have layouts of their own.
  large;

  /// Below this shortest side a touch screen is a phone. The detail screens
  /// already use the same line.
  static const double compactBreakpoint = 600;

  /// A phone screen is at least about 19.5:9 (2.17). Anything squarer than
  /// this, and still under [compactBreakpoint], is a cover screen.
  static const double coverMaxAspect = 1.85;

  static ScreenForm classify(Size size, {required bool mobileUi}) {
    if (!mobileUi) return large;
    final shortest = size.shortestSide;
    if (shortest <= 0) return phone;
    if (shortest >= compactBreakpoint) return unfolded;
    return size.longestSide / shortest < coverMaxAspect ? cover : phone;
  }

  /// Rebuilds the caller when the window size changes, so folding or
  /// opening the phone lays the screen out again.
  static ScreenForm of(BuildContext context) => classify(
    MediaQuery.sizeOf(context),
    mobileUi: PlatformDetection.useMobileUi,
  );
}

/// Tabletop posture: an opened foldable standing half folded like a small
/// laptop, the picture on the upper half and the controls on the half that
/// rests on the table.
///
/// Phones that report their hinge posture get it on their own. The Galaxy Z
/// Fold8 has no Flex mode and reports nothing, so the viewer can also turn it
/// on by hand with [forced]. Folding the phone switches it off.
abstract final class Tabletop {
  static final ValueNotifier<bool> forced = _ForcedTabletop();

  /// Whether the screen can be split by hand: opened. Either way up, since
  /// without a hinge report only the viewer knows where the fold runs: a
  /// Fold8, wider than tall when opened, stands in portrait, older Folds in
  /// landscape. The split always runs across the screen.
  static bool canForce(Size size) =>
      ScreenForm.classify(size, mobileUi: PlatformDetection.useMobileUi) ==
      ScreenForm.unfolded;

  /// Where the screen folds in tabletop posture, or null when it doesn't.
  /// A forced fold is a line across the middle of the screen.
  static Rect? foldOf(Size size, List<DisplayFeature> features) {
    for (final feature in features) {
      if (feature.type != DisplayFeatureType.fold &&
          feature.type != DisplayFeatureType.hinge) {
        continue;
      }
      if (feature.state != DisplayFeatureState.postureHalfOpened) continue;
      final bounds = feature.bounds;
      final spansWidth = bounds.width >= size.width * 0.9;
      if (spansWidth && bounds.width > bounds.height) return bounds;
    }
    if (forced.value && canForce(size)) {
      return Rect.fromLTWH(0, size.height / 2, size.width, 0);
    }
    return null;
  }

  /// [foldOf] for the screen [context] draws on. Callers rebuild with the
  /// window and with [forced] when they listen to it.
  static Rect? foldIn(BuildContext context) =>
      foldOf(MediaQuery.sizeOf(context), MediaQuery.displayFeaturesOf(context));

  /// What the hinge says about itself, for the screen information in
  /// settings.
  static HingePosture hingeOf(List<DisplayFeature> features) {
    var posture = HingePosture.none;
    for (final feature in features) {
      if (feature.type != DisplayFeatureType.fold &&
          feature.type != DisplayFeatureType.hinge) {
        continue;
      }
      if (feature.state == DisplayFeatureState.postureHalfOpened) {
        return HingePosture.halfOpened;
      }
      posture = HingePosture.flat;
    }
    return posture;
  }
}

/// A hinge's report on itself. The Fold8 reports [none] even opened.
enum HingePosture { none, flat, halfOpened }

/// Watches the window while tabletop is forced and lets go of it as soon as
/// the phone is folded.
class _ForcedTabletop extends ValueNotifier<bool> with WidgetsBindingObserver {
  _ForcedTabletop() : super(false);

  bool _observing = false;

  @override
  set value(bool next) {
    if (next == super.value) return;
    super.value = next;
    if (next && !_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } else if (!next && _observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null || view.devicePixelRatio == 0) return;
    final size = view.physicalSize / view.devicePixelRatio;
    if (!Tabletop.canForce(size)) value = false;
  }
}
