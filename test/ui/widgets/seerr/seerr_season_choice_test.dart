import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/seerr/seerr_request_dialog.dart';

void main() {
  test('une série ne part pas sans choix de saisons', () {
    expect(seerrSeasonChoiceMade(isTv: true, allSeasons: false, selected: 0), isFalse);
  });

  test('une saison choisie, ou « Toutes » coché exprès, suffit', () {
    expect(seerrSeasonChoiceMade(isTv: true, allSeasons: false, selected: 1), isTrue);
    expect(seerrSeasonChoiceMade(isTv: true, allSeasons: true, selected: 0), isTrue);
  });

  test('un film part toujours', () {
    expect(seerrSeasonChoiceMade(isTv: false, allSeasons: false, selected: 0), isTrue);
  });
}
