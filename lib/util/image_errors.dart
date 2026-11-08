import 'package:flutter/foundation.dart';

/// An image that could not be fetched or decoded (a missing poster): drawn as
/// a blank, not a crash, so it stays out of the Ma TV reports.
bool isImageLoadError(FlutterErrorDetails details) {
  if (details.library == 'image resource service') return true;
  final type = details.exception.runtimeType.toString();
  return type.contains('NetworkImageLoadException') ||
      details.exception.toString().contains('ImageCodecException');
}

/// « RenderBox was not laid out » while Flutter picks a button to focus as
/// the browser window gets focus back: harmless, Flutter goes on.
bool isViewFocusMeasureError(FlutterErrorDetails details) {
  final during = details.context?.toDescription() ?? '';
  return during.contains('didChangeViewFocus') &&
      details.exception.toString().contains('RenderBox was not laid out');
}
