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
}
