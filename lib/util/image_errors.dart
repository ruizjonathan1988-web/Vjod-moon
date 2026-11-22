import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An image that could not be fetched or decoded (a missing or corrupt
/// poster): drawn as a blank, not a crash, so it stays out of the Ma TV
/// reports. Works on a raw exception, so it also catches the decode failures
/// that surface asynchronously through platformDispatcher.onError, where there
/// is no FlutterErrorDetails and no 'image resource service' library tag —
/// e.g. « Exception: Invalid image data » on a corrupt poster (VJOD 5.17).
bool isImageLoadException(Object exception) {
  final type = exception.runtimeType.toString();
  final text = exception.toString();
  return type.contains('NetworkImageLoadException') ||
      text.contains('ImageCodecException') ||
      text.contains('Invalid image data') ||
      text.contains('Invalid image dimensions') ||
      text.contains('Failed to decode image') ||
      text.contains('Could not instantiate image codec');
}

/// The FlutterError.onError form: the image service also tags its errors with
/// a library name, which catches cases the message alone would miss.
bool isImageLoadError(FlutterErrorDetails details) {
  if (details.library == 'image resource service') return true;
  return isImageLoadException(details.exception);
}

/// « RenderBox was not laid out » while Flutter picks a button to focus as
/// the browser window gets focus back: harmless, Flutter goes on.
bool isViewFocusMeasureError(FlutterErrorDetails details) {
  final during = details.context?.toDescription() ?? '';
  return during.contains('didChangeViewFocus') &&
      details.exception.toString().contains('RenderBox was not laid out');
}

/// A native event channel this box does not have, such as the audio
/// capability one on a box whose build lacks it: the probe simply has no
/// events there, so it is not a crash (15 reports from SFR, Bouygues and Fire
/// TV boxes before VJOD 5.16).
bool isMissingOptionalChannel(FlutterErrorDetails details) {
  if (details.exception is! MissingPluginException) return false;
  final text =
      '${details.exception} ${details.context?.toDescription() ?? ''}';
  return text.contains('audioCapabilitiesEvents');
}
