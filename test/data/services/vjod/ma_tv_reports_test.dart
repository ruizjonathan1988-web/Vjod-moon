// VJOD 4.11: crashes and failed playbacks go to Ma TV, secrets taken out,
// kept on the device until Ma TV answers.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moonfin/data/services/vjod/ma_tv_reports.dart';
import 'package:moonfin/data/services/vjod/tv_sources.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> received;
  late int status;
  final reports = MaTvReports.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    received = [];
    status = 200;
    reports.debounce = const Duration(hours: 1); // sent by hand in the tests
    reports.serverOf = () => TvSourcesServer.fromJson({'url': 'https://seedbox.example.com/iptv', 'key': 'SECRETKEY'});
    reports.httpClient = MockClient((req) async {
      expect(req.url.path, '/iptv/tv/api/report');
      expect(req.url.queryParameters['k'], 'SECRETKEY');
      received.addAll([
        for (final r in (jsonDecode(req.body)['reports'] as List)) Map<String, dynamic>.from(r as Map),
      ]);
      return http.Response('{"ok":1}', status);
    });
  });

  test('un plantage part vers Ma TV, sans la clé ni le compte du fournisseur', () async {
    reports.crash(
      StateError('Échec sur https://seedbox.example.com/iptv/tv/xc/movie/vjod/SECRETKEY/42.mkv?k=SECRETKEY'),
      StackTrace.current,
    );
    reports.play('Lecture impossible', where: 'iptv', title: 'Dune',
        source: 'http://fournisseur.tv/movie/jean/motdepasse/77.mkv');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await reports.flush(), 2);
    expect(received.map((r) => r['kind']), ['crash', 'play']);
    final all = jsonEncode(received);
    expect(all.contains('SECRETKEY'), isFalse);
    expect(all.contains('motdepasse'), isFalse);
    expect(received.first['app'], isNotEmpty);
    expect(received.first['device'], isNotEmpty);
    expect(received.last['title'], 'Dune');
    // envoyés : plus rien n'attend
    expect(await reports.pending(), isEmpty);
  });

  test('Ma TV injoignable : le signalement attend sur l\'appareil', () async {
    status = 503;
    reports.play('La chaîne ne répond pas', channel: '1 TF1 ${DateTime.now().microsecond}');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await reports.flush(), 0);
    expect(await reports.pending(), hasLength(1));
    status = 200;
    expect(await reports.flush(), 1);
    expect(await reports.pending(), isEmpty);
  });

  test('le même problème une seule fois par lancement', () async {
    final err = ArgumentError('toujours la même ${DateTime.now().microsecondsSinceEpoch}');
    for (var i = 0; i < 5; i++) {
      reports.crash(err, null);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await reports.pending(), hasLength(1));
  });

  test('au plus 30 en attente, les plus anciens partent', () async {
    status = 503;
    for (var i = 0; i < 40; i++) {
      reports.play('erreur $i ${DateTime.now().microsecondsSinceEpoch}');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final left = await reports.pending();
    expect(left, hasLength(MaTvReports.maxStored));
    expect(left.last.message, startsWith('erreur 39'));
  });
}
