// VJOD 4.6: Sports (Ma TV 3.55). The plain decisions only.
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/ma_tv_sports.dart';

const _start = 1800000000;

Map<String, dynamic> _json({String state = 'live', Object? score = const ['2', '1'], int? minute = 67}) => {
  'id': '1',
  'sport': 'football',
  'sportName': 'Football',
  'comp': 'Ligue 1',
  'country': 'France',
  'home': 'Paris SG',
  'away': 'Marseille',
  'start': _start,
  'state': state,
  'score': score,
  'minute': minute,
  'odds': {'1': 1.35, 'N': 4.6, '2': 9},
  'last': {'text': 'But de Marseille', 'min': 64, 'at': _start + 3840},
  'chans': [
    {'id': 'canal', 'num': 4, 'name': 'Canal+'},
  ],
};

void main() {
  group('lecture de Ma TV', () {
    test('un match en cours', () {
      final e = SportEvent.fromJson(_json());
      expect(e.live, isTrue);
      expect(e.scoreText, '2 \u2013 1');
      expect(e.clockText, '67\u2019');
      expect(e.odds, {'1': 1.35, 'N': 4.6, '2': 9.0});
      expect(e.last!.label, 'But de Marseille (64\u2019)');
      expect(e.channels.single.name, 'Canal+');
    });

    test('avant le coup d\'envoi : l\'heure, pas de score', () {
      final e = SportEvent.fromJson(_json(state: 'pre', score: null, minute: null));
      expect(e.scoreText, isEmpty);
      expect(e.clockText, matches(RegExp(r'^\d\d:\d\d$')));
    });

    test('tennis : les jeux de chaque set', () {
      final e = SportEvent.fromJson({
        ..._json(),
        'sets': [
          [6, 3],
          [4, 5],
        ],
      });
      expect(e.scoreText, '6-4 3-5');
    });

    test('réponse vide ou abîmée : rien, sans erreur', () {
      final s = MaTvSports.fromJson({'events': 'abîmé', 'sports': null});
      expect(s.events, isEmpty);
      expect(s.source, isNull);
    });
  });

  group('choix du profil', () {
    test('équipe suivie, avec ou sans accents ni majuscules', () {
      final e = SportEvent.fromJson(_json());
      expect(followsTeam(e, 'marseille'), isTrue);
      expect(followsTeam(e, 'Paris SG'), isTrue);
      expect(followsTeam(e, 'Lyon'), isFalse);
      expect(followsTeam(e, ''), isFalse);
    });

    test('jamais de cotes en mode enfants', () {
      expect(showSportOdds(wanted: true, kids: false), isTrue);
      expect(showSportOdds(wanted: true, kids: true), isFalse);
      expect(showSportOdds(wanted: false, kids: false), isFalse);
    });

    test('ajouter puis retirer un sport ou une équipe', () {
      var raw = toggleInList('', 'tennis', ',');
      expect(raw, 'tennis');
      raw = toggleInList(raw, 'football', ',');
      expect(splitList(raw, ','), ['tennis', 'football']);
      expect(toggleInList(raw, 'TENNIS', ','), 'football');
    });
  });

  group('coup d\'envoi', () {
    final live = SportEvent.fromJson(_json());

    test('prévenu une fois, quand le match passe en direct', () {
      expect(kickOffs({'1': 'pre'}, [live], reminders: {'1'}, teams: const []), [live]);
      expect(kickOffs({'1': 'live'}, [live], reminders: {'1'}, teams: const []), isEmpty);
      expect(kickOffs({}, [live], reminders: {'1'}, teams: const []), isEmpty, reason: 'première lecture : rien');
    });

    test('une équipe suivie suffit, sinon rien', () {
      expect(kickOffs({'1': 'pre'}, [live], reminders: const {}, teams: ['Marseille']), [live]);
      expect(kickOffs({'1': 'pre'}, [live], reminders: const {}, teams: ['Lyon']), isEmpty);
    });
  });
}
