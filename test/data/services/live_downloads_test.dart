import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/my_requests.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/services/vjod/ma_tv.dart';
import 'package:moonfin/ui/screens/seerr/en_route_screen.dart';

MyRequestEntry _entry(int tmdb, {String type = 'movie', MyRequestState state = MyRequestState.approved}) =>
    MyRequestEntry(
      request: SeerrRequest(
        id: tmdb,
        status: SeerrRequest.statusApproved,
        type: type,
        media: SeerrMedia(id: tmdb, tmdbId: tmdb, title: 'T$tmdb'),
      ),
      state: state,
    );

void main() {
  test('Ma TV lit la file de Radarr et de Sonarr', () {
    final d = parseMaTvDownloads({
      'items': [
        {'type': 'movie', 'tmdb': 603, 'progress': 0.75, 'eta': '2026-11-08T20:40:00Z'},
        {'type': 'tv', 'tmdb': 1399, 'season': 2, 'progress': 0.5, 'stalled': true},
        {'type': 'movie'},
      ],
    });
    expect(d.length, 2);
    expect(d.first.progress, 0.75);
    expect(d.first.eta, isNotNull);
    expect(d.last.isTv && d.last.stalled, isTrue);
  });

  test('une demande « approuvée » qui se télécharge déjà passe en téléchargement, avec sa progression', () {
    final out = applyLiveDownloads(
      [_entry(603), _entry(7)],
      const [MaTvDownload(isTv: false, tmdbId: 603, progress: 0.4)],
    );
    expect(out.first.state, MyRequestState.downloading);
    expect(out.first.progress, 0.4);
    expect(out.last.state, MyRequestState.approved);
  });

  test('un titre déjà prêt ne repart pas en téléchargement, et un film ne prend pas la file d’une série', () {
    final out = applyLiveDownloads(
      [_entry(603, state: MyRequestState.ready), _entry(5)],
      const [
        MaTvDownload(isTv: false, tmdbId: 603, progress: 0.4),
        MaTvDownload(isTv: true, tmdbId: 5, progress: 0.4),
      ],
    );
    expect(out.first.state, MyRequestState.ready);
    expect(out.last.state, MyRequestState.approved);
  });

  test('le temps restant se dit simplement', () {
    final now = DateTime(2026, 11, 8, 20);
    expect(enRouteEtaLabel(now.add(const Duration(minutes: 4)), now), 'fini dans 4 min');
    expect(enRouteEtaLabel(DateTime(2026, 11, 8, 21, 40), now), 'fin vers 21:40');
    expect(enRouteEtaLabel(DateTime(2026, 11, 9, 1, 5), now), 'fin demain vers 01:05');
    expect(enRouteEtaLabel(now.subtract(const Duration(minutes: 1)), now), '');
  });
}
