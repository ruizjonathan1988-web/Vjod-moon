/// VJOD 5.11 : les petits appareils (box SFR, Fire TV, projecteurs, ADT-3,
/// navigateur) gardent le même VJOD, sans le travail d'arrière-plan qui ne
/// gêne pas un téléphone récent mais sature leur processeur : fiche préparée
/// d'avance, pages Seerr enregistrées sur l'appareil, pastille En route
/// relue toutes les 45 s, Accueil redessiné à chaque rangée qui arrive.
library;

import 'package:get_it/get_it.dart';

import '../preference/preference_constants.dart';
import '../preference/user_preferences.dart';
import 'device_performance.dart';
import 'platform_detection.dart';

/// Sous cette mémoire, une box ou une télé Android est un petit appareil.
/// 3 Go : la box SFR, les Fire TV, les projecteurs et l'ADT-3 ont 2 Go au plus.
const vjodLightTvMemoryCeilingBytes = 3221225472; // 3 Gio

/// Le choix, sans rien lire de l'appareil (testable).
///
/// « Standard » dans Réglages › Général › Performance garde tout ; « Réduit »
/// allège partout. En « Auto » : le navigateur, et une box ou une télé Android
/// de 3 Go ou moins (ou dont la mémoire n'a pas pu être lue).
bool vjodLightFor({
  required DevicePerformanceMode mode,
  required Map<String, dynamic> memory,
  required bool isWeb,
  required bool isTv,
}) {
  switch (mode) {
    case DevicePerformanceMode.standard:
      return false;
    case DevicePerformanceMode.reduced:
      return true;
    case DevicePerformanceMode.auto:
      if (resolveDevicePerformanceTierFor(mode, memory) == DevicePerformanceTier.reduced) return true;
      if (isWeb) return true;
      if (!isTv) return false;
      final total = memory['totalMem'];
      if (total is! num || total <= 0) return true;
      return total < vjodLightTvMemoryCeilingBytes;
  }
}

/// Ce que doit faire l'appareil en marche allégée.
abstract final class VjodLight {
  /// Pour les tests.
  static bool? debugOverride;

  static bool get on {
    final forced = debugOverride;
    if (forced != null) return forced;
    var mode = DevicePerformanceMode.auto;
    try {
      mode = GetIt.instance<UserPreferences>().get(UserPreferences.performanceMode);
    } catch (_) {}
    return vjodLightFor(
      mode: mode,
      memory: PlatformDetection.deviceMemory,
      isWeb: PlatformDetection.isWeb,
      isTv: PlatformDetection.isTV,
    );
  }

  /// La pastille En route : toutes les 45 s, toutes les 5 min en marche allégée.
  static Duration enRouteBadgeInterval(bool light) =>
      light ? const Duration(minutes: 5) : const Duration(seconds: 45);

  /// L'Accueil se redessine au plus une fois par ce délai pendant que les
  /// rangées arrivent (au lieu d'une fois par rangée).
  static const homeRowsBatch = Duration(milliseconds: 1500);
}
