/// VJOD's versions and what each brought, newest first. The first entry is
/// the version being built: « À propos » shows it, the app shows it once after
/// updating, and the build (perso-apk.yml) writes it on the GitHub release, so
/// the update window can say « VJOD 4.1 » and what changed.
///
/// Every update adds an entry on top, with the next number (4.2, 4.3…), in
/// French, one line per change, said the way the household would.
library;

class VjodRelease {
  final String version;
  final List<String> changes;

  const VjodRelease(this.version, this.changes);
}

const vjodReleases = <VjodRelease>[
  VjodRelease('4.3', [
    'VJOD sur Mac : une vraie appli, avec les films du serveur, les films et séries IPTV et la TV en direct.',
    'Sur Mac, VJOD propose lui-même ses mises à jour.',
  ]),
  VjodRelease('4.2', [
    'Vieilles Fire TV : une version allégée de l\u2019appli (environ 40 % plus légère), installée toute seule à la prochaine mise à jour.',
    'Moins de place prise par les affiches gardées en mémoire sur les appareils faibles.',
  ]),
  VjodRelease('4.1', [
    'Recherche plus visible : un champ « Film, série, acteur, chaîne… » en haut, et une loupe dans Films et Séries (même par acteur ou réalisateur).',
    'Clavier TV plus lisible et mots de recherche écrits en grand.',
    'Profil simple : 4 onglets, un seul bouton Regarder ou Demander, textes plus grands. L’administrateur l’active pour un profil.',
    'Mode léger automatique sur les vieilles Fire TV.',
    'Écrans de la TV en direct traduits (anglais, russe, chinois).',
    'Le serveur de la maison est reproposé si la première connexion a échoué.',
    'Plus de saccades pendant le chargement de Films et Séries, et corrections diverses.',
  ]),
];

/// The version a GitHub release names in its title (« VJOD 4.1 »), or null.
String? vjodVersionFromTitle(String? title) =>
    RegExp(r'VJOD\s+(\d+(?:\.\d+)+)').firstMatch(title ?? '')?.group(1);

/// The changes a GitHub release lists in its notes (lines starting « - »).
List<String> vjodChangesFromNotes(String? notes) => [
  for (final line in (notes ?? '').split('\n'))
    if (line.trimLeft().startsWith('- ')) line.trimLeft().substring(2).trim(),
];

/// The commit a release was built from, as its notes say it (« commit
/// abc1234 », the Mac release), or null.
String? vjodCommitFromNotes(String? notes) =>
    RegExp(r'commit ([0-9a-f]{7,40})').firstMatch(notes ?? '')?.group(1);
