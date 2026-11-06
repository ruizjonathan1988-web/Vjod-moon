import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moonfin/data/services/vjod/aura/aura.dart';
import 'package:moonfin/data/services/vjod/aura/aura_cloud.dart';
import 'package:server_core/server_core.dart';

AuraProposal _p(String id,
        {String from = 'srv:jon', String to = 'srv:lea', String film = 'tmdb:1', bool seen = false, bool liked = false, int? rating, String name = 'Jon'}) =>
    AuraProposal(
      id: id,
      from: 'joueur-$from',
      fromPerson: from,
      fromName: name,
      toPerson: to,
      toName: 'Léa',
      filmKey: film,
      title: 'Film $id',
      seenAt: seen ? DateTime(2026, 11, 6) : null,
      liked: liked,
      rating: rating,
      createdAt: DateTime(2026, 11, 6),
    );

void main() {
  group('le réglage, profil par profil', () {
    test('coupé par défaut, bouton Pop quand le profil l\'a choisi', () {
      expect(auraModeFromPrefs(const {}), AuraMode.off);
      expect(auraModeFromPrefs(const {'auraMode': 'button'}), AuraMode.button);
      expect(auraModeFromPrefs(const {'auraMode': 'inconnu'}), AuraMode.off);
    });

    test('écrit à côté du mode simple sans y toucher', () {
      const before = DisplayPreferences(id: 'vjod', sortBy: 'Name', customPrefs: {'simpleMode': 'true'});
      final after = withAuraMode(before, AuraMode.button, defaultId: 'vjod');
      expect(after.customPrefs, {'simpleMode': 'true', 'auraMode': 'button'});
      expect(after.sortBy, 'Name');
      expect(withAuraMode(const DisplayPreferences(id: ''), AuraMode.off, defaultId: 'vjod').id, 'vjod');
    });
  });

  group('le pont avec l\'appli Aura', () {
    final etat = jsonEncode({
      'v': 1,
      'maj': '2026-11-06T18:00:00Z',
      'position': 12,
      'pop': 9,
      'niveau': 4,
      'cartes': {
        '2026-11-06': [
          {
            'type': 'Rétro',
            'defi': 'Un classique pour rire, avant 1980',
            'cases': 3,
            'niveau': 4,
            'film': {'id': 'abc', 'titre': 'Les Temps modernes', 'annee': 1936, 'tmdb': 3082, 'jellyfin': true},
          },
          {'type': 'Pépite', 'cases': 2, 'film': {'id': 'tmdb-1', 'titre': 'Parasite', 'tmdb': 496243, 'jellyfin': false}},
          {'film': {'titre': 'sans identifiant'}},
        ],
      },
      'seance': {'film': 'abc', 'titre': 'Les Temps modernes', 'cases': 3},
    });

    test('Aura publie la course et les cartes du soir', () {
      final s = AuraState.fromPrefs({'etat': etat, 'autre': 'x'})!;
      expect((s.position, s.pop, s.level), (12, 9, 4));
      expect(s.raceLine, 'Tu as 3 cases d’avance sur Pop.');
      final cartes = s.cardsFor(DateTime(2026, 11, 6, 21));
      expect(cartes, hasLength(2), reason: 'une carte illisible est laissée de côté');
      expect(cartes.first.challenge, 'Un classique pour rire, avant 1980');
      expect(cartes.first.onServer, isTrue);
      expect(cartes.last.onServer, isFalse);
      expect(cartes.last.tmdbId, 496243);
      expect(s.cardsFor(DateTime(2026, 11, 7)), isEmpty);
      expect(s.playingTitle, 'Les Temps modernes');
    });

    test('rien de publié, ou une version inconnue : pas d\'état', () {
      expect(AuraState.fromPrefs(const {}), isNull);
      expect(AuraState.fromPrefs(const {'etat': 'pas du json'}), isNull);
      expect(AuraState.fromPrefs({'etat': jsonEncode({'v': 2})}), isNull);
    });

    test('la carte jouée part au format qu\'Aura lit, sans effacer son état', () {
      final value = AuraBridge.played(day: '2026-11-06', index: 1, at: DateTime.utc(2026, 11, 6, 20, 30));
      expect(jsonDecode(value), {'jour': '2026-11-06', 'index': 1, 'quand': '2026-11-06T20:30:00.000Z'});
      final prefs = AuraBridge.withPlayed(DisplayPreferences(id: '', customPrefs: {'etat': etat}), value);
      expect(prefs.id, 'aura');
      expect(prefs.customPrefs['etat'], etat);
      expect(prefs.customPrefs['joue'], value);
    });

    test('égalité et retard sur Pop', () {
      expect(const AuraState(position: 5, pop: 5).raceLine, 'Tu es à égalité avec Pop.');
      expect(const AuraState(position: 4, pop: 5).raceLine, 'Pop a 1 case d’avance sur toi.');
    });
  });

  group('l\'aura, comme dans Aura', () {
    test('+1 vu, +2 aimé (cœur ou 4 et 5), +3 quand plusieurs aiment le même film', () {
      final s = AuraScore.scores([
        _p('1', seen: true),
        _p('2', seen: true, liked: true),
        _p('3', to: 'srv:max', film: 'tmdb:2', rating: 5, seen: true),
        _p('4', to: 'srv:zoe', film: 'tmdb:2', liked: true, seen: true),
        _p('5', from: 'srv:lea', to: 'srv:jon', name: 'Léa', rating: 3, seen: true),
        _p('6', from: 'srv:lea', to: 'srv:jon', name: 'Léa', film: 'tmdb:9'),
      ]);
      expect(s['srv:jon'], 1 + 3 + 3 + 3 + 3);
      expect(s['srv:lea'], 1);
    });

    test('le classement, de la plus forte aura à la plus faible', () {
      final r = AuraScore.ranking([
        _p('1', seen: true),
        _p('2', from: 'srv:lea', name: 'Léa', to: 'srv:jon', seen: true, liked: true),
      ]);
      expect(r.map((e) => (e.name, e.aura)), [('Léa', 3), ('Jon', 1)]);
    });

    test('la clé d\'un film est la même que dans Aura', () {
      expect(auraFilmKey(tmdb: 603), 'tmdb:603');
      expect(auraFilmKey(jellyfin: 'abc'), 'jf:abc');
      expect(auraPerson('srv', 'u1'), 'srv:u1');
    });

    test('une proposition dans la maison, telle que le serveur l\'attend', () {
      final b = AuraProposal.newInHouse(
        fromPerson: 'srv:jon',
        fromName: 'Jon',
        toPerson: 'srv:lea',
        toName: 'Léa',
        house: 'srv',
        title: 'Matrix',
        year: 1999,
        tmdbId: 603,
        jellyfinId: 'abc',
        note: '  Tu vas adorer.  ',
      );
      expect(b['film_cle'], 'tmdb:603');
      expect(b['maison'], 'srv');
      expect(b['mot'], 'Tu vas adorer.');
      expect(b['film'], {'titre': 'Matrix', 'annee': 1999, 'tmdb': 603, 'jellyfin': 'abc', 'type': 'movie'});
      final lue = AuraProposal.fromJson({...b, 'id': 'p1', 'de': 'u1', 'aime': false, 'note': 5, 'vu_le': '2026-11-06T21:00:00Z'})!;
      expect((lue.title, lue.author, lue.recipient, lue.seen, lue.loved), ('Matrix', 'srv:jon', 'srv:lea', true, true));
      expect(AuraProposal.fromJson({'id': 'x'}), isNull);
    });

    test('noms et pseudos aux longueurs que le serveur accepte', () {
      expect(auraPseudo('J'), 'J.');
      expect(auraPseudo(''), 'VJOD');
      expect(auraPseudo('x' * 30).length, 24);
      expect(auraName('  '), '?');
    });
  });

  group('vu et aimé, d\'après Jellyfin', () {
    final now = DateTime.utc(2026, 11, 6, 22);

    test('un film vu et en favori : vu et aimé', () {
      final w = AuraWatch.fromUserData({'Played': true, 'IsFavorite': true});
      expect(w.patchFor(_p('1'), now), {'vu_le': '2026-11-06T22:00:00.000Z', 'aime': true});
    });

    test('une série commencée compte comme vue ; un pouce levé ou 8 sur 10, comme aimé', () {
      expect(AuraWatch.fromUserData({'UnplayedItemCount': 7, 'PlayedPercentage': 12.5}).played, isTrue);
      expect(AuraWatch.fromUserData({'Likes': true}).loved, isTrue);
      expect(AuraWatch.fromUserData({'Rating': 8.0}).loved, isTrue);
      expect(AuraWatch.fromUserData({'Rating': 6.0}).loved, isFalse);
    });

    test('rien de neuf : rien à écrire ; on n\'enlève jamais', () {
      expect(AuraWatch.fromUserData(null).patchFor(_p('1'), now), isNull);
      expect(AuraWatch.fromUserData({'Played': true}).patchFor(_p('1', seen: true), now), isNull);
      expect(AuraWatch.fromUserData({'Played': false}).patchFor(_p('1', seen: true, liked: true), now), isNull);
    });
  });

  group('le serveur d\'Aura', () {
    test('un compte anonyme la première fois, gardé ensuite, rafraîchi quand il expire', () async {
      String? saved;
      final calls = <String>[];
      var now = DateTime.utc(2026, 11, 6, 20);
      final client = MockClient((r) async {
        calls.add('${r.method} ${r.url.path}${r.url.query.isEmpty ? '' : '?${r.url.query}'}');
        expect(r.headers['apikey'], 'cle');
        if (r.url.path == '/auth/v1/signup' || r.url.path == '/auth/v1/token') {
          return http.Response(jsonEncode({'access_token': 'a${calls.length}', 'refresh_token': 'r', 'expires_in': 3600, 'user': {'id': 'u1'}}), 200);
        }
        return http.Response('[]', 200);
      });
      AuraCloud cloud() => AuraCloud(load: () async => saved, save: (v) async => saved = v, client: client, clock: () => now, url: 'https://x.test', anonKey: 'cle');
      final c = cloud();
      expect((await c.session()).userId, 'u1');
      expect((await cloud().session()).accessToken, 'a1', reason: 'gardé sur l\'appareil');
      now = now.add(const Duration(hours: 2));
      expect((await cloud().session()).accessToken, 'a2');
      expect(calls, ['POST /auth/v1/signup', 'POST /auth/v1/token?grant_type=refresh_token']);
    });

    test('inscription, maison, proposition et « vu » : les bonnes requêtes', () async {
      final requests = <http.Request>[];
      final client = MockClient((r) async {
        requests.add(r);
        if (r.url.path == '/rest/v1/joueurs' && r.method == 'GET') {
          return http.Response(jsonEncode([
            {'pseudo': 'Zoé', 'personne': 'srv:zoe'},
            {'pseudo': 'Jon', 'personne': 'srv:jon'},
            {'pseudo': 'Léa', 'personne': 'srv:lea'},
            {'pseudo': 'Léa tablette', 'personne': 'srv:lea'},
          ]), 200);
        }
        if (r.url.path == '/rest/v1/propositions' && r.method == 'POST') return http.Response('', 409);
        return http.Response('', 201);
      });
      final session = jsonEncode(AuraSession(userId: 'u1', accessToken: 'tok', refreshToken: 'r', expiresAt: DateTime.utc(2030)).toJson());
      final c = AuraCloud(load: () async => session, save: (_) async {}, client: client, url: 'https://x.test', anonKey: 'cle');

      await c.register(pseudo: 'J', house: 'srv', person: 'srv:jon');
      final reg = requests.last;
      expect(reg.url.queryParameters['on_conflict'], 'id');
      expect(reg.headers['Prefer'], contains('merge-duplicates'));
      expect(reg.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(reg.body), {'id': 'u1', 'pseudo': 'J.', 'maison': 'srv', 'personne': 'srv:jon'});

      final mates = await c.housemates(house: 'srv', me: 'srv:jon');
      expect(mates.map((m) => m.name), ['Léa', 'Zoé'], reason: 'un par personne, sans soi, par ordre alphabétique');
      expect(requests.last.url.queryParameters['maison'], 'eq.srv');

      await expectLater(c.propose({'film_cle': 'tmdb:1'}), throwsA(isA<AuraCloudException>().having((e) => e.message, 'message', 'Déjà proposé.')));

      await c.mark('p1', {'aime': true});
      expect(requests.last.method, 'PATCH');
      expect(requests.last.url.queryParameters['id'], 'eq.p1');
      expect(jsonDecode(requests.last.body), {'aime': true});
    });
  });
}
