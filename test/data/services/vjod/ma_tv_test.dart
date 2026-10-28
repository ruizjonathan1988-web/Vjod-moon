import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moonfin/data/services/vjod/ma_tv.dart';
import 'package:moonfin/data/services/vjod/tv_sources.dart';

void main() {
  const server = TvSourcesServer(url: 'https://h.example/iptv-checker', key: 'KEY');
  final t0 = DateTime(2026, 10, 28, 20, 0);
  int s(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  test('a channel as Ma TV lists it, with what is on now and next', () {
    final ch = MaTvChannel.fromJson({
      'id': 'tf1',
      'num': 1,
      'name': 'TF1',
      'logo': 'http://logo/tf1.png',
      'theme': 'Généraliste',
      'cc': 'FR',
      'q': '1080p',
      'arc': 7,
      'now': {'t': 'Koh-Lanta', 's': s(t0), 'e': s(t0.add(const Duration(minutes: 110)))},
      'next': {'t': 'Vendredi tout est permis', 's': s(t0.add(const Duration(minutes: 110))), 'e': s(t0.add(const Duration(minutes: 200)))},
    });
    expect(ch.number, 1);
    expect(ch.replayDays, 7);
    final mid = t0.add(const Duration(minutes: 55));
    expect(ch.programAt(mid)!.title, 'Koh-Lanta');
    expect(ch.programAt(mid)!.progressAt(mid), closeTo(0.5, 0.01));
    expect(ch.programAfter(mid)!.title, 'Vendredi tout est permis');
    // Once the first one is over, the next one is "on now".
    final later = t0.add(const Duration(minutes: 130));
    expect(ch.programAt(later)!.title, 'Vendredi tout est permis');
    expect(ch.programAfter(later), isNull);
  });

  test('categories, channels and guide read from the seedbox', () async {
    final asked = <String>[];
    final client = MaTvClient(
      server: server,
      httpClient: MockClient((req) async {
        asked.add(req.url.toString());
        final p = req.url.path;
        Object body;
        if (p.endsWith('/tv/api/cats')) {
          body = {
            'cats': [
              {'id': 'all', 'label': 'Toutes les chaînes', 'kind': 'all', 'n': 3},
              {'id': 't:Sport', 'label': 'Sport', 'kind': 'theme', 'n': 1},
            ],
          };
        } else if (p.endsWith('/tv/api/chans')) {
          body = {
            'chans': [
              {'id': 'bein1', 'num': 60, 'name': 'beIN Sports 1', 'theme': 'Sport'},
            ],
          };
        } else {
          body = {
            'progs': {
              'bein1': [
                {'t': 'Ligue 1', 's': s(t0), 'e': s(t0.add(const Duration(hours: 2))), 'd': 'Match', 'i': 'http://img/1.jpg'},
              ],
            },
          };
        }
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }),
    );
    final cats = await client.categories(fresh: true);
    expect(cats!.map((c) => c.id), ['all', 't:Sport']);
    final chans = await client.channels('t:Sport', fresh: true);
    expect(chans!.single.name, 'beIN Sports 1');
    final progs = await client.programs(['bein1'], t0, t0.add(const Duration(hours: 4)));
    expect(progs!['bein1']!.single.description, 'Match');
    expect(asked.every((u) => u.contains('k=KEY')), isTrue);
    expect(asked[1], contains('cat=t%3ASport'));
  });

  test('an unreachable seedbox answers null, never throws', () async {
    final client = MaTvClient(server: server, httpClient: MockClient((_) async => http.Response('', 503)));
    MaTvClient.forgetCache();
    expect(await client.categories(fresh: true), isNull);
    expect(await client.channels('all', fresh: true), isNull);
  });

  test('live and replay addresses carry the key', () {
    final client = MaTvClient(server: server);
    const ch = MaTvChannel(id: 'tf1', number: 1, name: 'TF1');
    expect(client.liveUri(ch).toString(), startsWith('https://h.example/iptv-checker/tv/play/tf1.ts?'));
    expect(client.liveUri(ch).toString(), contains('k=KEY'));
    final p = MaTvProgram(title: 'JT', start: t0, end: t0.add(const Duration(minutes: 40)));
    final r = client.replayUri(ch, p)!;
    expect(r.path, '/iptv-checker/tv/replay/tf1.ts');
    expect(r.queryParameters['start'], '${s(t0)}');
    expect(r.queryParameters['dur'], '45');
  });
}
