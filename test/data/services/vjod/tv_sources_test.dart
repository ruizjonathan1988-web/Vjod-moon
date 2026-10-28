import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/tv_sources.dart';

void main() {
  // What IPTV Checker writes into the "VJOD – TV" collection (_vjod_overview).
  const overview =
      'Réglages de la TV en direct pour VJOD (IPTV Checker). Ne pas modifier ni supprimer : '
      'IPTV Checker la met à jour.\n\n'
      'VJOD-TV:eyJ2IjoxLCJ1cmwiOiJodHRwczovL2F2YTg4Lnplbi51c2J4Lm1lL2lwdHYtY2hlY2tlciIsImtleSI6ImFiY19ERUYtMTIzIn0';

  test('reads the Ma TV address IPTV Checker left in Jellyfin', () {
    final server = tvServerFromOverview(overview)!;
    expect(server.url, 'https://ava88.zen.usbx.me/iptv-checker');
    expect(server.key, 'abc_DEF-123');
    final uri = server.endpoint('/tv/api/channel', {'num': '1'});
    expect(uri.toString(),
        'https://ava88.zen.usbx.me/iptv-checker/tv/api/channel?num=1&k=abc_DEF-123');
  });

  test('a pasted code and anything else', () {
    final server = TvSourcesServer.fromCode('https://h.example/iptv-checker/#KEY')!;
    expect(server.url, 'https://h.example/iptv-checker');
    expect(server.key, 'KEY');
    expect(TvSourcesServer.fromCode('pas un code'), isNull);
    expect(tvServerFromOverview('VJOD-CONFIG:abc'), isNull);
    expect(tvServerFromOverview(null), isNull);
  });

  test('channel numbers as Jellyfin gives them', () {
    expect(lineupNumber('1'), 1);
    expect(lineupNumber('01'), 1);
    expect(lineupNumber('60.0'), 60);
    expect(lineupNumber(null), isNull);
    expect(lineupNumber(''), isNull);
  });

  test('sources read from the relay, with their measured details', () {
    final channel = TvChannelSources.fromJson({
      'id': 'tf1',
      'num': 1,
      'name': 'TF1',
      'sources': [
        {'k': '1:10', 'n': 1, 'provider': 'a.example', 'name': 'FR| TF1 FHD', 'quality': 'FHD',
         'h': 1080, 'fps': 50.0, 'kbps': 6200, 'ms': 800, 'ok': true, 'tested': 1, 'playing': false},
        {'k': '2:70', 'n': 2, 'provider': 'b.example', 'name': 'TF1 SD', 'quality': 'SD',
         'ok': null, 'pref': true, 'sticky': true, 'playing': true},
      ],
    });
    expect(channel.sources, hasLength(2));
    expect(channel.current!.key, '2:70');
    expect(channel.hasChoice, isTrue);
    expect(channel.sources.first.details(), '1080p · 50 i/s · 6,2 Mb/s · 0,8 s');
    expect(channel.sources.first.details(french: false), '1080p · 50 fps · 6.2 Mb/s · 0.8 s');
    expect(channel.sources.last.details(), 'SD');
    expect(channel.sources.last.ok, isNull);
  });
}
