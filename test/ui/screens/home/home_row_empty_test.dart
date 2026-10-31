import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/ui/screens/home/home_view_model.dart';

void main() {
  group('une rangée revenue vide', () {
    test('une rangée de découverte affichée reste (source pas à l’heure)', () {
      for (final type in [
        HomeSectionType.seerrForYou,
        HomeSectionType.top10Movies,
        HomeSectionType.seerrTrending,
        HomeSectionType.latestMedia,
      ]) {
        expect(HomeViewModel.keepsRowsOnEmpty(type: type, hasVisibleRow: true), isTrue, reason: '$type');
      }
    });

    test('Reprendre, À suivre, mes demandes et favoris se vident pour de vrai', () {
      for (final type in [
        HomeSectionType.resume,
        HomeSectionType.nextUp,
        HomeSectionType.seerrMyRequests,
        HomeSectionType.favoriteMovies,
        HomeSectionType.liveTv,
      ]) {
        expect(HomeViewModel.keepsRowsOnEmpty(type: type, hasVisibleRow: true), isFalse, reason: '$type');
      }
    });

    test('rien à garder quand rien n’était affiché', () {
      expect(HomeViewModel.keepsRowsOnEmpty(type: HomeSectionType.seerrForYou, hasVisibleRow: false), isFalse);
    });
  });
}
