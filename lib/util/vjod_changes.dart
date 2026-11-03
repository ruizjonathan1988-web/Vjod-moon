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
  VjodRelease('4.20', [
    'Recherche plus rapide : les résultats arrivent dès qu\u2019on s\u2019arrête de taper, se filtrent à chaque lettre ajoutée, et une recherche déjà faite revient aussitôt ; la bibliothèque n\u2019attend plus Seerr.',
    'Les listes s\u2019affichent tout de suite, même juste après avoir ouvert l\u2019appli : chaînes et catégories de Ma TV, replay, et première page de Films et Séries. Elles se mettent à jour d\u2019elles-mêmes.',
    'Réglages → À propos → « Temps de réponse » : combien met Jellyfin, Ma TV, Seerr à répondre sur cet appareil. La page Ma TV les montre pour tous les appareils.',
    'Le replay prend les mêmes couleurs que le reste de Ma TV.',
  ]),
  VjodRelease('4.19', [
    'La rangée « Replay » s\u2019affiche aussi quand « Continuer » regroupe les reprises et les épisodes suivants (elle manquait dans ce cas).',
    'Page d\u2019une chaîne comme sur la maquette : « Hier soir » en grand avec son résumé, une rangée par émission, puis « Jour par jour ».',
    '« Mes émissions » : la chaîne et « NOUVEAU » sur chaque épisode, un bouton « Infos » ; au premier jour, « Suis tes émissions en un appui ». Sur la fiche : « Épisode suivant ».',
    'Sur l\u2019Accueil, « Mes émissions » dit combien de nouveaux épisodes et lesquels, et une chaîne épinglée le montre.',
    'Un replay commencé revient dans « Reprendre » et repart où il s\u2019était arrêté, sur tous les appareils.',
    'La meilleure source d\u2019abord : l\u2019épisode de ta bibliothèque s\u2019il y est, sinon le replay de la chaîne, sinon la diffusion enregistrée par ton fournisseur (« Passer la pub » saute 3 min), l\u2019appli de la chaîne en dernier. « Autres sources » sur la fiche pour choisir (dont la VOD du fournisseur et Seerr).',
    '« Mes émissions » propose à suivre ce que tu as regardé en direct ces derniers jours (Ma TV 3.63).',
    'La rangée « Replay » trouve sa place même sans « Continuer » sur l\u2019Accueil.',
  ]),
  VjodRelease('4.18', [
    'Replay des chaînes dans VJOD : une rangée « Replay » sur l\u2019Accueil avec « Mes émissions » et une tuile par chaîne (Arte, France 2, 3, 4, 5), jusqu\u2019à 3 semaines, sans passer par l\u2019IPTV.',
    'Un appui et l\u2019épisode se lance dans VJOD ; appui long : « Suivre », « Pas pour nous » ou l\u2019appli de la chaîne. Météo, journaux et jeux masqués.',
    'Les tuiles des chaînes gardent leur place toute la semaine (les plus regardées en tête), et un appui long en épingle une en premier.',
  ]),
  VjodRelease('4.17', [
    'Sur le téléphone : la chaîne ou le film IPTV continue écran éteint ou appli réduite, avec une notification pour mettre en pause ou arrêter (Réglages → Lecture pour le couper).',
  ]),
  VjodRelease('4.16', [
    'TV sur le téléphone : en quittant l\u2019appli, la chaîne continue dans une petite fenêtre (image dans l\u2019image), les films et séries IPTV aussi.',
    'Grille des programmes au doigt : glisser vers la gauche ou la droite avance ou recule d\u2019une heure, « Maintenant » y revient, et les programmes se chargent là où l\u2019on fait défiler.',
  ]),
  VjodRelease('4.15', [
    'La recherche de l\u2019Accueil trouve aussi les chaînes : par leur nom, leur numéro ou ce qu\u2019elles passent (« PSG » trouve la chaîne du match). Un appui et la chaîne se lance.',
  ]),
  VjodRelease('4.14', [
    'Versions d\u2019essai : chaque nouvelle version arrive d\u2019abord sur les appareils de l\u2019administrateur (Réglages → À propos → Versions d\u2019essai), puis chez tout le monde quand il la valide sur la page Ma TV.',
  ]),
  VjodRelease('4.13', [
    'Chaque profil a maintenant sa propre clé pour Ma TV, demandée toute seule : l\u2019administrateur voit qui regarde quoi et peut couper l\u2019accès d\u2019une seule personne.',
    'Un profil coupé le voit écrit sur l\u2019écran de la TV, au lieu de « Ma TV ne répond pas ».',
  ]),
  VjodRelease('4.12', [
    '« Signaler un problème » aussi dans le menu de la chaîne (TV) et sur l\u2019écran d\u2019un film ou d\u2019un épisode qui ne se lance pas, pas seulement dans les réglages.',
    'Le message WhatsApp dit déjà ce qui était à l\u2019écran, le dernier souci noté par l\u2019appareil et son numéro sur la page Ma TV.',
  ]),
  VjodRelease('4.11', [
    'Quand VJOD plante ou qu\u2019une chaîne, un film ou un épisode ne se lance pas, l\u2019appareil le signale tout seul à Ma TV : l\u2019administrateur le voit sur la page Ma TV (et sur son téléphone pour un plantage), sans avoir besoin d\u2019une photo de l\u2019écran.',
  ]),
  VjodRelease('4.10', [
    'Mise à jour : si la Fire TV n\u2019autorise pas encore VJOD à installer ses mises à jour, VJOD l\u2019explique et ouvre le bon réglage, au lieu de l\u2019écran bloquant « Pour votre sécurité » à chaque ouverture.',
  ]),
  VjodRelease('4.9', [
    'Correctif TV : l\u2019écran des chaînes ne reste plus bloqué sur « Rechercher » à la télécommande ; il s\u2019ouvre sur tes chaînes.',
  ]),
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
