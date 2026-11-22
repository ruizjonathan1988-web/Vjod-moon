import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  test('une jaquette abimee (« Invalid image data ») n\'est pas un plantage', () {
    // Remonte par platformDispatcher.onError, sans FlutterErrorDetails ni
    // bibliotheque « image resource service » : il faut la reconnaitre au texte.
    expect(isImageLoadException(Exception('Invalid image data')), isTrue);
    expect(isImageLoadException(Exception('Could not instantiate image codec.')), isTrue);
    expect(
      isImageLoadError(FlutterErrorDetails(exception: Exception('Invalid image data'))),
      isTrue,
    );
    // Une vraie erreur applicative reste un plantage.
    expect(isImageLoadException(StateError('Null check operator used on a null value')), isFalse);
    expect(isImageLoadException(Exception('seerr: request failed')), isFalse);
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

  test('une box sans le canal natif du son n\'est pas un plantage', () {
    expect(
      isMissingOptionalChannel(FlutterErrorDetails(
        exception: MissingPluginException(
            'No implementation found for method listen on channel org.moonfin.androidtv/audioCapabilitiesEvents'),
        library: 'services library',
        context: ErrorDescription('while activating platform stream on channel org.moonfin.androidtv/audioCapabilitiesEvents'),
      )),
      isTrue,
    );
    expect(
      isMissingOptionalChannel(FlutterErrorDetails(
        exception: MissingPluginException('No implementation found for method play on channel autre'),
      )),
      isFalse,
    );
  });
}
