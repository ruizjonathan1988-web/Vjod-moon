import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/iptv_next.dart';
import 'package:moonfin/data/services/vjod/xtream_catalog.dart';

XtreamEpisode _ep(String id, int s, int n) => XtreamEpisode(id: id, season: s, number: n, title: '', extension: 'mkv');

void main() {
  final info = XtreamSeriesInfo(plot: '', cover: '', seasons: {
    2: [_ep('c', 2, 1)],
    1: [_ep('a', 1, 1), _ep('b', 1, 2)],
  });

  test('épisode suivant dans la saison, puis au début de la suivante', () {
    expect(episodeAfter(info, season: 1, number: 1)?.id, 'b');
    expect(episodeAfter(info, season: 1, number: 2)?.id, 'c');
    expect(episodeAfter(info, season: 2, number: 1), isNull);
  });

  test("l'identifiant de l'épisode prime sur le numéro", () {
    expect(episodeAfter(info, season: 9, number: 9, id: 'a')?.id, 'b');
    expect(episodeAfter(info, season: 9, number: 9), isNull);
  });

  test('générique : correction gardée seulement si elle a du sens', () {
    const from = Duration(seconds: 30);
    expect(IptvIntroSkip.corrected(from, const Duration(seconds: 125)), const Duration(seconds: 95));
    expect(IptvIntroSkip.corrected(from, const Duration(seconds: 35)), isNull);
    expect(IptvIntroSkip.corrected(from, const Duration(minutes: 10)), isNull);
  });
}
