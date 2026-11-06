// VJOD 4.28 : « Nouvel épisode » des émissions suivies, et le replay du mode enfant.
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/ma_tv_replay.dart';
import 'package:moonfin/data/services/vjod/replay_alerts.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReplayItem _e(String id, String show, {bool fresh = true, String title = ''}) =>
    ReplayItem(id: id, kind: 'ftv', chan: 'france-2', show: show, title: title, isNew: fresh);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('le texte de l’alerte', () {
    expect(replayAlertText([]), isNull);
    expect(replayAlertText([_e('1', 'Envoyé spécial', title: 'La une')])!.title, 'Nouvel épisode : Envoyé spécial');
    final many = replayAlertText([_e('1', 'A'), _e('2', 'B'), _e('3', 'C'), _e('4', 'D'), _e('5', 'E')])!;
    expect(many.title, '5 nouveaux épisodes');
    expect(many.body, 'A, B, C et 2 autres');
  });

  test('la première fois rien, puis chaque épisode une seule fois', () async {
    final home1 = ReplayHome(channels: const [], mine: [_e('1', 'Envoyé spécial'), _e('2', 'Capital', fresh: false)]);
    expect(await ReplayAlerts.note(home1, notify: false), isEmpty);
    final home2 = ReplayHome(channels: const [], mine: [_e('1', 'Envoyé spécial'), _e('3', 'Cash Investigation')]);
    expect((await ReplayAlerts.note(home2, notify: false)).map((e) => e.id), ['3']);
    expect(await ReplayAlerts.note(home2, notify: false), isEmpty);
  });

  test('les chaînes du mode enfant', () {
    for (final n in ['France 4', 'Okoo', 'Gulli', 'TIJI', 'Canal J', 'Piwi+', 'Disney Channel', 'Nickelodeon Junior']) {
      expect(replayIsKidsChannel(n), isTrue, reason: n);
    }
    for (final n in ['France 2', 'TF1', 'M6', 'Arte', 'Canal+']) {
      expect(replayIsKidsChannel(n), isFalse, reason: n);
    }
  });
}
