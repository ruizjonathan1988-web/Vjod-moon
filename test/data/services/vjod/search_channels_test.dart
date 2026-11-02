// VJOD 4.15: the home search finds Ma TV's channels too: by name or number
// first, then by the programme they air.
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/ma_tv.dart';

MaTvChannel _c(int n, String name, [String? show]) => MaTvChannel.fromJson({
  'id': 'c$n',
  'num': n,
  'name': name,
  if (show != null) 'now': {'t': show, 's': 1700000000, 'e': 1700003600},
});

void main() {
  final all = [
    _c(1, 'TF1', 'Le 20 h'),
    _c(14, 'TF1 Séries Films'),
    _c(2, 'France 2', 'Journal'),
    _c(487, 'Canal Sport', 'Ligue 1 : OL – PSG'),
    _c(9, 'Équipe', 'PSG – Brest, le résumé'),
  ];

  test('le nom exact d’abord, puis les autres chaînes au même nom', () {
    expect(searchChannelHits(all, 'tf1').map((c) => c.number), [1, 14]);
  });

  test('un numéro trouve sa chaîne', () {
    expect(searchChannelHits(all, '487').map((c) => c.name), ['Canal Sport']);
  });

  test('un programme trouve la chaîne qui le passe, après les noms', () {
    expect(searchChannelHits(all, 'psg').map((c) => c.number), [487, 9]);
    expect(searchChannelHits(all, 'equipe').map((c) => c.number).first, 9);
  });

  test('une seule lettre ne remplit pas la rangée', () {
    expect(searchChannelHits(all, 't'), isEmpty);
    expect(searchChannelHits(all, ''), isEmpty);
  });
}
