import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/detail/detail_buttons.dart';
import 'package:moonfin/ui/screens/detail/item_detail_screen.dart';

void main() {
  const ordered = [
    DetailButton.restart,
    DetailButton.audio,
    DetailButton.trailer,
    DetailButton.favorite,
    DetailButton.notForMe,
  ];
  const film = [
    DetailButton.restart,
    DetailButton.trailer,
    DetailButton.favorite,
    DetailButton.notForMe,
  ];

  test('la bande-annonce vient juste après le bouton principal, avant les langues IPTV', () {
    final row = vjodFrontRow<String>(
      primary: 'Lecture',
      byButton: {
        DetailButton.restart: 'Depuis le début',
        DetailButton.audio: 'Audio',
        DetailButton.trailer: 'Bande-annonce',
        DetailButton.favorite: '+',
        DetailButton.notForMe: 'Pas pour moi',
      },
      providerExtras: ['En russe · 1080p', 'Choisir le fichier'],
      ordered: ordered,
      keep: film,
    );
    expect(row, [
      'Lecture',
      'Bande-annonce',
      'En russe · 1080p',
      'Choisir le fichier',
      'Depuis le début',
      '+',
      'Pas pour moi',
    ]);
  });

  test('sans bande-annonce : rien ne change d\'ordre', () {
    final row = vjodFrontRow<String>(
      primary: 'Demander',
      byButton: {DetailButton.favorite: '+'},
      providerExtras: const [],
      ordered: ordered,
      keep: film,
    );
    expect(row, ['Demander', '+']);
  });

  test('une seule fois, même quand elle est dans l\'ordre choisi', () {
    final row = vjodFrontRow<String>(
      primary: null,
      byButton: {DetailButton.trailer: 'Bande-annonce'},
      providerExtras: const [],
      ordered: ordered,
      keep: film,
    );
    expect(row, ['Bande-annonce']);
  });
}
