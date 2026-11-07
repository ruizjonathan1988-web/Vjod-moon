import 'package:flutter/foundation.dart';

/// An image that could not be fetched or decoded (a missing poster): drawn as
/// a blank, not a crash, so it stays out of the Ma TV reports.
bool isImageLoadError(FlutterErrorDetails details) {
  if (details.library == 'image resource service') return true;
  final type = details.exception.runtimeType.toString();
  return type.contains('NetworkImageLoadException') ||
      details.exception.toString().contains('ImageCodecException');
}
