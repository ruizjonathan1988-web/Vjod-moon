/// Which VJOD build this is: when it was built and from which commit, set by
/// the build (perso-apk.yml). Empty in a build made by hand.
library;

class VjodBuild {
  const VjodBuild._();

  static const _built = String.fromEnvironment('VJOD_BUILD');
  static const commit = String.fromEnvironment('VJOD_COMMIT');

  /// When the build was made (Paris time), or null when unknown.
  static DateTime? get builtAt => _built.isEmpty ? null : DateTime.tryParse(_built);
}
