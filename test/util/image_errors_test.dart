import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/image_errors.dart';

void main() {
  test('une affiche qui ne charge pas n\'est pas un plantage', () {
    expect(
      isImageLoadError(FlutterErrorDetails(exception: Exception('x'), library: 'image resource service')),
      isTrue,
    );
    expect(
      isImageLoadError(FlutterErrorDetails(exception: Exception('ImageCodecException: Failed to load network image.'))),
      isTrue,
    );
    expect(
      isImageLoadError(FlutterErrorDetails(exception: StateError('RenderBox was not laid out'), library: 'rendering library')),
      isFalse,
    );
  });

  test('le retour du focus dans la fenêtre du navigateur n\'est pas un plantage', () {
    expect(
      isViewFocusMeasureError(FlutterErrorDetails(
        exception: StateError('RenderBox was not laid out: Class5095#34728'),
        context: ErrorDescription('while dispatching notifications for WidgetsBindingObserver.didChangeViewFocus'),
      )),
      isTrue,
    );
    expect(
      isViewFocusMeasureError(FlutterErrorDetails(
        exception: StateError('RenderBox was not laid out'),
        context: ErrorDescription('during performLayout()'),
      )),
      isFalse,
    );
  });
}
