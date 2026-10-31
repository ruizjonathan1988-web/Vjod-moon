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
  VjodRelease('4.8', [
    'Sports : tous les sports proposés, sports de combat compris (boxe, MMA/UFC, judo…).',
    'Sur chaque match, un vrai bouton : « Regarder » sur la chaîne, « Me prévenir » avant le match, ou « Chercher la chaîne ».',
    'Réglages Sports : « Ajouter une équipe ou un sportif », à choisir dans la liste ou à taper.',
    'La chaîne du match est trouvée plus souvent dans le guide.',
  ]),
  VjodRelease('4.7', [
    'Nouveau : Multiview. Deux chaînes côte à côte (quatre sur ordinateur), depuis le menu du lecteur ; le son suit la case choisie.',
    'Multiview n\u2019apparaît que sur les appareils assez puissants : jamais sur Fire TV, en mode léger, sur Mac ou sur iPad.',
  ]),
  VjodRelease('4.6', [
    'Nouveau : Sports dans la TV. Les matchs du jour pour tous les sports, le score en direct, les cotes et la chaîne qui diffuse le match.',
    'Pendant un match, le score s\u2019affiche en haut de l\u2019image, avec un mot à chaque but.',
    'Chaque profil choisit ses sports, suit ses équipes, demande à être prévenu au coup d\u2019envoi, et peut masquer les cotes (jamais affichées en mode enfants).',
  ]),
  VjodRelease('4.5', [
    'VJOD sur iPad : une vraie appli, installée avec AltStore (guide fourni), qui se met à jour dans AltStore.',
    'Dans Safari (iPad, iPhone) : les films et séries IPTV et la TV en direct se lisent, Ma TV prépare une version lisible.',
    'Sur ordinateur aussi : un film que le navigateur ne lisait pas passe maintenant par Ma TV au lieu d\u2019afficher une erreur.',
    'VJOD ajouté à l\u2019écran d\u2019accueil de l\u2019iPad garde son nom et son icône, et tourne dans les deux sens.',
  ]),
  VjodRelease('4.4', [
    'Les rangées de l\u2019Accueil ne disparaissent plus quand un service met trop de temps à répondre : elles restent, et VJOD réessaie tout seul.',
    'Réglages : « L\u2019essentiel » en haut (langue, sous-titres, qualité vidéo, contrôle parental).',
    'Le menu du profil ne montre « Demandes à valider » qu\u2019à l\u2019administrateur.',
  ]),
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
