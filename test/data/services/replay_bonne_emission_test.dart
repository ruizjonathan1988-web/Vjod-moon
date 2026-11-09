import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/ma_tv_replay.dart';

void main() {
  ReplayItem item(String kind) => ReplayItem(
        id: 'x',
        kind: kind,
        chan: kind == 'iptv' ? '42' : 'france-5',
        show: 'La Fabrique du mensonge',
        aired: DateTime(2026, 11, 8, 6),
      );

  test('France TV et Arte : jamais la diffusion IPTV à l’heure de mise en ligne', () async {
    expect(replayHasBroadcastTime(item('ftv')), isFalse);
    expect(replayHasBroadcastTime(item('arte')), isFalse);
    expect(await ReplaySources.iptv(item('ftv')), isNull);
    expect(await ReplaySources.iptv(item('arte')), isNull);
  });

  test('rattrapage IPTV : l’heure est celle de la diffusion', () {
    expect(replayHasBroadcastTime(item('iptv')), isTrue);
  });

  test('rattrapage IPTV : l’enregistrement d’abord, la VOD du fournisseur ensuite', () {
    expect(replayIptvOrder, ['iptv', 'vod']);
  });
}
