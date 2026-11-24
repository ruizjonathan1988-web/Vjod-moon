import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/my_requests.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/services/seerr/seerr_download_progress.dart';
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

  group('downloadProgress (VJOD 5.20 : cohérent avec SeerrDownloadSummary)', () {
    test('ignore les releases sans downloadId', () {
      final items = [
        const SeerrDownloadingItem(size: 100, sizeLeft: 50, downloadId: null),
      ];
      expect(downloadProgress(items), isNull);
      expect(SeerrDownloadSummary.fromItems(items), isNull);
    });

    test('dédoublonne par downloadId (pack de saison)', () {
      final items = [
        const SeerrDownloadingItem(size: 100, sizeLeft: 0, downloadId: 'a'),
        const SeerrDownloadingItem(size: 100, sizeLeft: 0, downloadId: 'a'),
      ];
      expect(downloadProgress(items), 1.0);
    });

    test('même fraction que la pastille et la fiche, releases retenues écartées', () {
      final items = [
        const SeerrDownloadingItem(size: 100, sizeLeft: 25, downloadId: 'a'),
        const SeerrDownloadingItem(size: 100, sizeLeft: 100, downloadId: null),
      ];
      final badge = downloadProgress(items);
      final card = SeerrDownloadSummary.fromItems(items);
      expect(badge, 0.75);
      expect(card, isNotNull);
      expect(card!.fraction, 0.75);
      expect(badge, card.fraction);
    });
  });
}
