import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/screens/seerr/en_route_screen.dart';

void main() {
  group('enRouteEtaLabel (VJOD 5.20 : vraie date de fin)', () {
    final now = DateTime(2026, 11, 24, 20, 0);

    test('déjà passé : rien', () {
      expect(enRouteEtaLabel(DateTime(2026, 11, 24, 19, 0), now), '');
    });

    test('moins d\'une heure : minutes', () {
      expect(enRouteEtaLabel(DateTime(2026, 11, 24, 20, 30), now), 'fini dans 30 min');
    });

    test('même jour : heure seule', () {
      expect(enRouteEtaLabel(DateTime(2026, 11, 24, 22, 30), now), 'fin vers 22:30');
    });

    test('lendemain : « demain »', () {
      expect(enRouteEtaLabel(DateTime(2026, 11, 25, 8, 10), now), 'fin demain vers 08:10');
    });

    test('après-demain : la vraie date, pas « demain »', () {
      // Le bug : l'APK affichait « demain » ; on veut « fin le 26/11 vers 08:10 ».
      expect(enRouteEtaLabel(DateTime(2026, 11, 26, 8, 10), now), 'fin le 26/11 vers 08:10');
    });

    test('plusieurs jours plus tard : date réelle', () {
      expect(enRouteEtaLabel(DateTime(2026, 12, 2, 9, 5), now), 'fin le 02/12 vers 09:05');
    });
  });
}
