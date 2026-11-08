import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/home/home_view_model.dart';

void main() {
  final now = DateTime(2026, 11, 8, 16);

  test('au retour dans l’appli, l’Accueil récent n’est pas tout rechargé', () {
    expect(
      HomeViewModel.resumeNeedsFullRefresh(lastFullLoad: now.subtract(const Duration(minutes: 3)), now: now),
      isFalse,
    );
  });

  test('un Accueil ancien, ou jamais chargé, est rechargé en entier', () {
    expect(
      HomeViewModel.resumeNeedsFullRefresh(lastFullLoad: now.subtract(const Duration(minutes: 15)), now: now),
      isTrue,
    );
    expect(HomeViewModel.resumeNeedsFullRefresh(lastFullLoad: null, now: now), isTrue);
  });
}
