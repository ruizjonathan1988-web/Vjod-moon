// Multiview (VJOD 4.7): two live channels side by side, four on a computer.
//
// Only where it can't slow the device down: never on a Fire TV, never in the
// light mode (reduced tier), never on the Mac or the iPad (Moonfin's Apple
// player plays one video at a time). Each extra channel takes one connection
// at the provider, which is why it stays at two outside a computer.
import 'package:device_info_plus/device_info_plus.dart';
import 'package:get_it/get_it.dart';

import '../../../preference/user_preferences.dart';
import '../../../util/device_performance.dart';
import '../../../util/platform_detection.dart';

/// How many tiles this device may show; 0 hides Multiview.
int multiviewTilesFor({
  required bool web,
  required bool android,
  required bool desktop,
  required bool apple,
  required bool reduced,
  String manufacturer = '',
}) {
  if (reduced || apple) return 0;
  if (manufacturer.trim().toLowerCase() == 'amazon') return 0;
  if (web) return 2;
  if (desktop) return 4;
  if (android) return 2;
  return 0;
}

class MaTvMultiview {
  static int? _tiles;

  /// The answer for this device, once [resolve] has run (0 before).
  static int get tiles => _tiles ?? 0;

  /// Reads what's needed (the maker, on Android) once per launch.
  static Future<int> resolve() async {
    final known = _tiles;
    if (known != null) return known;
    var maker = '';
    if (PlatformDetection.isAndroid) {
      try {
        maker = (await DeviceInfoPlugin().androidInfo).manufacturer;
      } catch (_) {
        // Unknown maker: treated as not a Fire TV; the tier still applies.
      }
    }
    final getIt = GetIt.instance;
    final reduced = getIt.isRegistered<UserPreferences>() &&
        getIt<UserPreferences>().resolveDevicePerformanceTier() == DevicePerformanceTier.reduced;
    return _tiles = multiviewTilesFor(
      web: PlatformDetection.isWeb,
      android: PlatformDetection.isAndroid,
      desktop: PlatformDetection.isWindows || PlatformDetection.isLinux,
      apple: PlatformDetection.isApple,
      reduced: reduced,
      manufacturer: maker,
    );
  }
}
