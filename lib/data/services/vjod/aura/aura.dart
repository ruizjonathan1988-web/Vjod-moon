// Aura, le jeu de cinéma, dans VJOD (VJOD 4.37).
//
// Deux choses passent par ici, sans écran ni réseau, pour être testées :
//
//  - le pont avec l'appli Aura, par les préférences d'affichage Jellyfin de
//    l'utilisateur (identifiant « aura », client « aura ») : Aura y dépose son
//    état (la course, les cartes des soirs à venir), VJOD y écrit la carte
//    jouée (« joue ») ;
//  - l'aura : on se propose des films et des séries entre les profils de la
//    maison (les utilisateurs d'un même serveur Jellyfin). Celui qui propose
//    gagne +1 quand l'autre regarde, +2 quand il aime (cœur, ou note de 4 ou
//    5), +3 de plus quand plusieurs aiment le même film. Même règle, au point
//    près, que `lib/services/aura.dart` dans le dépôt Aura.
import 'dart:convert';

import 'package:server_core/server_core.dart';

/// Où le jeu s'affiche dans VJOD, profil par profil.
enum AuraMode {
  /// Par défaut : VJOD comme avant.
  off('off'),

  /// Un bouton Pop en haut, qui ouvre le tiroir d'Aura.
  button('button');

  const AuraMode(this.id);
  final String id;

  static AuraMode from(String? id) =>
      AuraMode.values.where((m) => m.id == id).firstOrNull ?? AuraMode.off;
}

/// Le réglage est rangé avec le mode simple, dans les préférences « vjod » de
/// l'utilisateur : il suit le profil sur tous ses appareils.
const auraModeKey = 'auraMode';

AuraMode auraModeFromPrefs(Map<String, String> customPrefs) =>
    AuraMode.from(customPrefs[auraModeKey]);

DisplayPreferences withAuraMode(DisplayPreferences prefs, AuraMode mode, {required String defaultId}) =>
    DisplayPreferences(
      id: prefs.id.isEmpty ? defaultId : prefs.id,
      sortBy: prefs.sortBy,
      sortOrder: prefs.sortOrder,
      viewType: prefs.viewType,
      customPrefs: {...prefs.customPrefs, auraModeKey: mode.id},
    );

/// Le pont : ce qu'Aura publie, ce que VJOD renvoie.
abstract final class AuraBridge {
  static const prefsId = 'aura';
  static const client = 'aura';
  static const stateKey = 'etat';
  static const playedKey = 'joue';

  static String day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// La carte jouée, au format qu'Aura lit (`PontVjod.lireJoue`).
  static String played({required String day, required int index, required DateTime at}) =>
      jsonEncode({'jour': day, 'index': index, 'quand': at.toUtc().toIso8601String()});

  /// Les préférences avec la carte jouée, le reste gardé (Aura y range son
  /// état, qu'il ne faut pas perdre).
  static DisplayPreferences withPlayed(DisplayPreferences prefs, String value) => DisplayPreferences(
        id: prefs.id.isEmpty ? prefsId : prefs.id,
        sortBy: prefs.sortBy,
        sortOrder: prefs.sortOrder,
        viewType: prefs.viewType,
        customPrefs: {...prefs.customPrefs, playedKey: value},
      );
}

/// Une carte du soir, telle qu'Aura la publie.
class AuraCard {
  final String type;
  final String challenge;
  final int squares;
  final int? level;
  final String filmId;
  final String title;
  final int? year;
  final int? tmdbId;

  /// Sur le serveur (identifiant Jellyfin) ou seulement connue de TMDB.
  final bool onServer;

  const AuraCard({
    required this.type,
    required this.challenge,
    required this.squares,
    this.level,
    required this.filmId,
    required this.title,
    this.year,
    this.tmdbId,
    required this.onServer,
  });

  static AuraCard? fromJson(Object? j) {
    if (j is! Map) return null;
    final f = j['film'];
    if (f is! Map || f['id'] is! String || f['titre'] is! String) return null;
    return AuraCard(
      type: '${j['type'] ?? ''}',
      challenge: '${j['defi'] ?? ''}',
      squares: (j['cases'] as num?)?.toInt() ?? 1,
      level: (j['niveau'] as num?)?.toInt(),
      filmId: f['id'] as String,
      title: f['titre'] as String,
      year: (f['annee'] as num?)?.toInt(),
      tmdbId: (f['tmdb'] as num?)?.toInt(),
      onServer: f['jellyfin'] == true,
    );
  }
}

/// L'état d'Aura : la course du mois et les cartes des soirs à venir.
class AuraState {
  final DateTime? updated;
  final int position;
  final int pop;
  final int? level;
  final Map<String, List<AuraCard>> cards;

  /// La séance en cours (une carte jouée, pas encore vue).
  final String? playingTitle;

  const AuraState({
    this.updated,
    required this.position,
    required this.pop,
    this.level,
    this.cards = const {},
    this.playingTitle,
  });

  static const boardSize = 30;

  /// Lu depuis les préférences « aura » ; nul quand Aura n'a rien publié ou
  /// dans un format qu'on ne connaît pas.
  static AuraState? fromPrefs(Map<String, String> customPrefs) {
    final raw = customPrefs[AuraBridge.stateKey];
    if (raw == null || raw.isEmpty) return null;
    Object? j;
    try {
      j = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (j is! Map || j['v'] != 1) return null;
    final cards = <String, List<AuraCard>>{};
    final c = j['cartes'];
    if (c is Map) {
      for (final e in c.entries) {
        if (e.value is! List) continue;
        cards['${e.key}'] = [
          for (final x in e.value as List)
            if (AuraCard.fromJson(x) case final card?) card,
        ];
      }
    }
    final seance = j['seance'];
    return AuraState(
      updated: DateTime.tryParse('${j['maj']}'),
      position: (j['position'] as num?)?.toInt() ?? 0,
      pop: (j['pop'] as num?)?.toInt() ?? 0,
      level: (j['niveau'] as num?)?.toInt(),
      cards: cards,
      playingTitle: seance is Map ? seance['titre'] as String? : null,
    );
  }

  List<AuraCard> cardsFor(DateTime d) => cards[AuraBridge.day(d)] ?? const [];

  /// « Tu as 3 cases d'avance sur Pop », pour le haut du tiroir.
  String get raceLine {
    final gap = position - pop;
    if (gap > 0) return 'Tu as $gap case${gap > 1 ? 's' : ''} d’avance sur Pop.';
    if (gap < 0) return 'Pop a ${-gap} case${gap < -1 ? 's' : ''} d’avance sur toi.';
    return 'Tu es à égalité avec Pop.';
  }
}

/// La clé d'un film, la même dans VJOD et dans Aura : « tmdb:603 » quand on
/// connaît TMDB, sinon « jf:<id Jellyfin> ».
String auraFilmKey({int? tmdb, String? jellyfin}) => tmdb != null ? 'tmdb:$tmdb' : 'jf:${jellyfin ?? ''}';

/// Qui est qui dans la maison : le serveur, et le serveur avec l'utilisateur.
String auraPerson(String serverId, String userId) => '$serverId:$userId';

/// Une proposition, telle que la garde le serveur d'Aura.
class AuraProposal {
  final String id;
  final String from;
  final String? fromPerson;
  final String fromName;
  final String? toPerson;
  final String? toPlayer;
  final String toName;
  final String filmKey;
  final String title;
  final int? year;
  final int? tmdbId;
  final String? jellyfinId;
  final bool series;
  final String? note;
  final DateTime? seenAt;
  final bool liked;
  final int? rating;
  final DateTime createdAt;

  const AuraProposal({
    required this.id,
    required this.from,
    this.fromPerson,
    required this.fromName,
    this.toPerson,
    this.toPlayer,
    required this.toName,
    required this.filmKey,
    required this.title,
    this.year,
    this.tmdbId,
    this.jellyfinId,
    this.series = false,
    this.note,
    this.seenAt,
    this.liked = false,
    this.rating,
    required this.createdAt,
  });

  /// Qui gagne l'aura : la personne (tous ses appareils), sinon le joueur.
  String get author => fromPerson ?? from;
  String get recipient => toPerson ?? toPlayer ?? '';
  bool get seen => seenAt != null;

  /// Aimée : un cœur, ou une note de 4 ou 5.
  bool get loved => liked || (rating ?? 0) >= 4;

  static AuraProposal? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final film = raw['film'];
    if (raw['id'] is! String || raw['de'] is! String || film is! Map || film['titre'] is! String) return null;
    return AuraProposal(
      id: raw['id'] as String,
      from: raw['de'] as String,
      fromPerson: raw['de_personne'] as String?,
      fromName: (raw['de_nom'] as String?) ?? '?',
      toPerson: raw['pour_personne'] as String?,
      toPlayer: raw['pour_joueur'] as String?,
      toName: (raw['pour_nom'] as String?) ?? '?',
      filmKey: (raw['film_cle'] as String?) ?? '',
      title: film['titre'] as String,
      year: (film['annee'] as num?)?.toInt(),
      tmdbId: (film['tmdb'] as num?)?.toInt(),
      jellyfinId: film['jellyfin'] as String?,
      series: film['type'] == 'series',
      note: raw['mot'] as String?,
      seenAt: raw['vu_le'] == null ? null : DateTime.tryParse('${raw['vu_le']}'),
      liked: raw['aime'] == true,
      rating: (raw['note'] as num?)?.toInt(),
      createdAt: DateTime.tryParse('${raw['cree_le']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Le corps d'une nouvelle proposition entre deux profils de la maison.
  static Map<String, dynamic> newInHouse({
    required String fromPerson,
    required String fromName,
    required String toPerson,
    required String toName,
    required String house,
    required String title,
    int? year,
    int? tmdbId,
    String? jellyfinId,
    bool series = false,
    String? note,
  }) {
    final mot = note?.trim();
    return {
      'de_personne': fromPerson,
      'de_nom': auraName(fromName),
      'pour_personne': toPerson,
      'pour_nom': auraName(toName),
      'maison': house,
      'film_cle': auraFilmKey(tmdb: tmdbId, jellyfin: jellyfinId),
      'film': {
        'titre': title,
        if (year != null) 'annee': year,
        if (tmdbId != null) 'tmdb': tmdbId,
        if (jellyfinId != null) 'jellyfin': jellyfinId,
        'type': series ? 'series' : 'movie',
      },
      if (mot != null && mot.isNotEmpty) 'mot': mot.length > 140 ? mot.substring(0, 140) : mot,
    };
  }
}

/// Un nom accepté par le serveur : de 1 à 40 caractères.
String auraName(String name) {
  final n = name.trim();
  if (n.isEmpty) return '?';
  return n.length > 40 ? n.substring(0, 40) : n;
}

/// Un pseudo de joueur accepté par le serveur : de 2 à 24 caractères.
String auraPseudo(String name) {
  var n = name.trim();
  if (n.length > 24) n = n.substring(0, 24);
  if (n.length < 2) n = n.isEmpty ? 'VJOD' : '$n.';
  return n;
}

/// Les points d'aura.
abstract final class AuraScore {
  static const seen = 1;
  static const loved = 2;
  static const lovedByMany = 3;

  /// L'aura de chaque personne qui propose.
  static Map<String, int> scores(Iterable<AuraProposal> proposals) {
    final points = <String, int>{};
    final lovers = <String, Set<String>>{};
    for (final p in proposals) {
      var n = 0;
      if (p.seen) n += seen;
      if (p.loved) {
        n += loved;
        (lovers['${p.author}|${p.filmKey}'] ??= <String>{}).add(p.recipient);
      }
      points[p.author] = (points[p.author] ?? 0) + n;
    }
    for (final e in lovers.entries) {
      if (e.value.length >= 2) {
        final who = e.key.substring(0, e.key.lastIndexOf('|'));
        points[who] = (points[who] ?? 0) + lovedByMany;
      }
    }
    return points;
  }

  /// De la plus forte aura à la plus faible, puis par nom.
  static List<({String who, String name, int aura})> ranking(Iterable<AuraProposal> proposals) {
    final s = scores(proposals);
    final names = <String, String>{for (final p in proposals) p.author: p.fromName};
    return [for (final e in s.entries) (who: e.key, name: names[e.key] ?? '?', aura: e.value)]
      ..sort((a, b) => b.aura != a.aura ? b.aura.compareTo(a.aura) : a.name.compareTo(b.name));
  }
}

/// Ce que Jellyfin dit d'un titre proposé, pour celui qui l'a reçu.
class AuraWatch {
  final bool played;
  final bool favorite;

  /// La note personnelle sur 10, quand il y en a une.
  final double? rating;

  /// Pouce levé (le style « j'aime » de VJOD).
  final bool? likes;

  const AuraWatch({required this.played, required this.favorite, this.rating, this.likes});

  /// Lu dans le UserData d'un élément Jellyfin. Une série compte comme vue
  /// dès qu'un épisode l'a été.
  static AuraWatch fromUserData(Map<String, dynamic>? u) {
    if (u == null) return const AuraWatch(played: false, favorite: false);
    final count = (u['PlayCount'] as num?)?.toInt() ?? 0;
    final unplayed = (u['UnplayedItemCount'] as num?)?.toInt();
    final percent = (u['PlayedPercentage'] as num?)?.toDouble() ?? 0;
    final played = u['Played'] == true || count > 0 || (unplayed != null && percent > 0);
    return AuraWatch(
      played: played,
      favorite: u['IsFavorite'] == true,
      rating: (u['Rating'] as num?)?.toDouble(),
      likes: u['Likes'] as bool?,
    );
  }

  /// Aimé : en favori, un pouce levé ou une note d'au moins 8 sur 10.
  bool get loved => favorite || likes == true || (rating ?? 0) >= 8;

  /// Ce qu'il faut écrire sur la proposition, ou nul quand rien ne change.
  /// On n'enlève jamais : ce qui a été vu ou aimé le reste.
  Map<String, dynamic>? patchFor(AuraProposal p, DateTime now) {
    final patch = <String, dynamic>{
      if ((played || loved) && !p.seen) 'vu_le': now.toUtc().toIso8601String(),
      if (loved && !p.liked) 'aime': true,
    };
    return patch.isEmpty ? null : patch;
  }
}
