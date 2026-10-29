import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/iptv_progress.dart';

void main() {
  test('what is playing travels through the player route and back', () {
    const w = IptvWatch(
      kind: 'series',
      id: '7',
      name: 'Lupin',
      tmdb: '96677',
      poster: 'https://img/p.jpg',
      ep: '3-9001',
      ext: 'mkv',
      season: 1,
      episode: 2,
      epName: 'Chapitre 2',
    );
    final back = IptvWatch.fromQuery({'url': 'x', ...w.toQuery()})!;
    expect(back.isSeries, isTrue);
    expect(back.id, '7');
    expect(back.ep, '3-9001');
    expect(back.season, 1);
    expect(back.episode, 2);
    expect(back.tmdb, '96677');
    expect(IptvWatch.fromQuery({'url': 'x'}), isNull, reason: 'a playback that keeps nothing');
  });

  test('a saved place reads from Ma TV', () {
    final p = IptvProgress.fromJson({
      'kind': 'movie',
      'id': 42,
      'name': 'Dune',
      'tmdb': '438631',
      'pos': 2700,
      'dur': 9000,
      'done': false,
      'at': 1793289000.5,
      'ext': 'mkv',
    })!;
    expect(p.id, '42');
    expect(p.position, const Duration(minutes: 45));
    expect(p.fraction, closeTo(0.3, 0.001));
    expect(p.resumable, isTrue);
    expect(p.ext, 'mkv');
    final done = IptvProgress.fromJson({'kind': 'movie', 'id': 1, 'pos': 30, 'dur': 9000})!;
    expect(done.resumable, isFalse, reason: 'less than a minute in');
    expect(IptvProgress.fromJson('nope'), isNull);
  });
}
