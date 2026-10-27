import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/french_channels.dart';

void main() {
  test('normalizeChannelName strips accents, case and punctuation', () {
    expect(normalizeChannelName('Canal+ Sport'), 'canalsport');
    expect(normalizeChannelName("L'Équipe"), 'lequipe');
    expect(normalizeChannelName('France 2'), 'france2');
    expect(normalizeChannelName('  TF1  HD '), 'tf1hd');
  });

  test('frenchChannelRank gives the TNT position of generalists', () {
    expect(frenchChannelRank('TF1'), 1);
    expect(frenchChannelRank('France 2'), 2);
    expect(frenchChannelRank('M6'), 6);
    expect(frenchChannelRank('Arte'), 7);
    expect(frenchChannelRank('Some Random Channel'), isNull);
  });

  test('isFrenchSportsChannel matches numbered variants', () {
    expect(isFrenchSportsChannel('beIN Sports 1'), isTrue);
    expect(isFrenchSportsChannel('RMC Sport 2'), isTrue);
    expect(isFrenchSportsChannel('Eurosport 1'), isTrue);
    expect(isFrenchSportsChannel('Canal+ Sport'), isTrue);
    expect(isFrenchSportsChannel('TF1'), isFalse);
  });

  test('isFrenchFavourite covers generalists and sports', () {
    expect(isFrenchFavourite('TF1'), isTrue);
    expect(isFrenchFavourite('beIN Sports 1'), isTrue);
    expect(isFrenchFavourite('Discovery Channel'), isFalse);
  });

  test('frenchTvOrder: generalists first, then sports, then the rest', () {
    final tf1 = frenchTvOrder('TF1');
    final m6 = frenchTvOrder('M6');
    final bein = frenchTvOrder('beIN Sports 1');
    final other = frenchTvOrder('Random HD');
    expect(tf1 < m6, isTrue);
    expect(m6 < bein, isTrue);
    expect(bein < other, isTrue);
  });
}
