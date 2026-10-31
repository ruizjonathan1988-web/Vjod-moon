/// Which VJOD build this is: when it was built and from which commit, set by
/// the build (perso-apk.yml). Empty in a build made by hand.
library;

class VjodBuild {
  const VjodBuild._();

  /// VJOD's own version number, shown in « À propos ». The Android version
  /// (pubspec) stays the Moonfin one it is based on: Jellyfin and the
  /// updates go by it.
  static const version = '4.4'; // the first entry of vjodReleases (vjod_changes.dart)

  static const _built = String.fromEnvironment('VJOD_BUILD');
  static const commit = String.fromEnvironment('VJOD_COMMIT');

  /// When the build was made (Paris time), or null when unknown.
  static DateTime? get builtAt => _built.isEmpty ? null : DateTime.tryParse(_built);
}
