// VJOD 4.20 : les listes déjà vues reviennent tout de suite, même après un
// redémarrage ; les chaînes dont le programme est fini ne le montrent plus.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moonfin/data/services/vjod/ma_tv.dart';
import 'package:moonfin/data/services/vjod/tv_sources.dart';
import 'package:moonfin/data/services/vjod/vjod_snapshots.dart';

const _server = TvSourcesServer(url: 'https://seedbox.example.com/iptv', key: 'K');

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('vjod_lists');
    VjodSnapshots.directoryForTests = dir;
    MaTvClient.forgetCache();
  });
  tearDown(() {
    VjodSnapshots.webForTests = null;
    VjodSnapshots.directoryForTests = null;
    dir.deleteSync(recursive: true);
  });

  test('une liste lue est gardée sur l’appareil', () async {
    await VjodSnapshots.write('k', {'a': 1});
    VjodSnapshots.clearMemory();
    expect(await VjodSnapshots.read('k'), {'a': 1});
    expect(await VjodSnapshots.read('autre'), isNull);
  });

  test('navigateur : pas de fichier, la liste reste en mémoire et rien ne plante (VJOD 4.35)', () async {
    VjodSnapshots.webForTests = true;
    await VjodSnapshots.write('w', {'a': 2});
    expect(await VjodSnapshots.read('w'), {'a': 2});
    expect(await VjodSnapshots.read('jamais vue'), isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('dossier inaccessible : la lecture répond « rien » au lieu de planter', () async {
    final f = File('${dir.path}/fichier')..writeAsStringSync('x');
    VjodSnapshots.directoryForTests = Directory('${f.path}/sous');
    await VjodSnapshots.write('z', {'a': 3});
    VjodSnapshots.clearMemory();
    expect(await VjodSnapshots.read('z'), isNull);
  });

  test('chaînes : la dernière liste revient aussitôt, sans le programme fini', () async {
    final now = DateTime.now();
    int t(Duration d) => now.add(d).millisecondsSinceEpoch ~/ 1000;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/tv/api/cats')) {
        return http.Response(jsonEncode({'cats': [{'id': 'all', 'name': 'Toutes'}]}), 200);
      }
      return http.Response(
        jsonEncode({
          'chans': [
            {
              'id': '1',
              'num': 1,
              'name': 'TF1',
              'now': {'t': 'Fini', 's': t(const Duration(hours: -2)), 'e': t(const Duration(minutes: -1))},
              'next': {'t': 'En cours', 's': t(const Duration(minutes: -1)), 'e': t(const Duration(hours: 1))},
            },
          ],
        }),
        200,
      );
    });
    final c = MaTvClient(httpClient: client, server: _server);
    await c.categories();
    await c.channels('all');
    // l'appli redémarre : plus rien en mémoire
    MaTvClient.forgetCache();
    VjodSnapshots.clearMemory();
    expect((await c.categoriesSaved())?.single.id, 'all');
    final saved = await c.channelsSaved('all');
    expect(saved?.single.name, 'TF1');
    expect(saved?.single.now?.title, 'En cours');
  });
}
