import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/channel_search.dart';

void main() {
  test('ignores case, spaces, punctuation and accents', () {
    expect(channelMatchesQuery('tf 1', name: 'TF1 HD'), isTrue);
    expect(channelMatchesQuery('TF-1', name: 'FR: TF1'), isTrue);
    expect(channelMatchesQuery('equipe', name: "L'Équipe"), isTrue);
    expect(channelMatchesQuery('m6', name: 'France 2'), isFalse);
  });

  test('a number matches the channel number exactly', () {
    expect(channelMatchesQuery('6', name: 'M6', number: '6'), isTrue);
    expect(channelMatchesQuery('6', name: 'France 2', number: '16'), isFalse);
  });

  test('finds a channel by what it airs', () {
    expect(
      channelMatchesQuery('psg',
          name: 'Canal+ Sport', programTitles: ['Ligue 1 : PSG - OM']),
      isTrue,
    );
  });

  test('an empty query matches everything', () {
    expect(channelMatchesQuery('  ', name: 'Arte'), isTrue);
  });

  test('VJOD 5.13 : la normalisation garde exactement le même résultat', () {
    expect(normalizeChannelQuery("L'Équipe 21"), 'lequipe21');
    expect(normalizeChannelQuery('Œuvre Ç Ñ ÿ Æ'), 'oeuvrecnyae');
    expect(normalizeChannelQuery('FR | TF1 HD ★'), 'frtf1hd');
    expect(normalizeChannelQuery(''), '');
    // Deux fois la même chaîne : la même réponse.
    expect(normalizeChannelQuery('Ça marche'), normalizeChannelQuery('Ça marche'));
  });
}
