import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
