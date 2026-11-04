// VJOD 4.27 : le mois à la maison, d'après Playback Reporting.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moonfin/data/services/vjod/watch_month.dart';

void main() {
  test('les épisodes se rangent sous leur série', () {
    expect(WatchMonth.seriesOf('Malcolm - s07e20 - Le grand jour'), 'Malcolm');
    expect(WatchMonth.seriesOf('Koh-Lanta - S25E10'), 'Koh-Lanta');
    expect(WatchMonth.hours(0.5), '30 min');
    expect(WatchMonth.hours(12.5), '12 h 30');
  });

  test('heures par personne, séries et films', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/user_usage_stats/submit_custom_query');
      expect(req.headers['X-Emby-Token'], 'T');
      expect((jsonDecode(req.body) as Map)['ReplaceUserId'], isTrue);
      return http.Response(
        jsonEncode({
          'colums': ['UserId', 'ItemType', 'ItemName', 'SUM(PlayDuration)'],
          'results': [
            ['Jon', 'Episode', 'Malcolm - s07e20 - Le grand jour', '1320'],
            ['Jon', 'Episode', 'Malcolm - s07e21 - Suite', '1320'],
            ['Pauline', 'Movie', 'Interstellar', '10140'],
            ['Pauline', 'Episode', 'Malcolm - s01e01 - Pilote', '1260'],
          ],
        }),
        200,
      );
    });
    final (m, e) = await WatchMonth.load(baseUrl: 'https://jf', token: 'T', client: client);
    expect(e, isEmpty);
    expect(m!.people.first.$1, 'Pauline');
    expect(m.series.single.$1, 'Malcolm');
    expect(m.series.single.$2, closeTo(1.083, 0.01));
    expect(m.films.single.$1, 'Interstellar');
    expect(WatchMonth.hours(m.totalHours), '3 h 54');
  });

  test('sans le module ou sans droits', () async {
    final none = MockClient((_) async => http.Response('', 404));
    expect((await WatchMonth.load(baseUrl: 'https://jf', token: 'T', client: none)).$2, contains('Playback Reporting'));
    final refused = MockClient((_) async => http.Response('', 403));
    expect((await WatchMonth.load(baseUrl: 'https://jf', token: 'T', client: refused)).$2, contains('administrateurs'));
  });
}
