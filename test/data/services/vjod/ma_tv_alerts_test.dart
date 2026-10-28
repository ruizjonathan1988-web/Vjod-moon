import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/ma_tv_alerts.dart';

void main() {
  test('reads the alerts Ma TV publishes, skipping malformed ones', () {
    final alerts = parseMaTvAlerts({
      'at': 1,
      'alerts': [
        {'id': 'night:1', 'kind': 'night', 'title': 'La nuit de Ma TV a échoué', 'text': 'Erreur'},
        {'id': '', 'title': 'sans id'},
        'junk',
        {'id': 'exp:3:99', 'kind': 'expires', 'title': 'Un compte expire bientôt'},
      ],
    });
    expect(alerts.map((a) => a.id), ['night:1', 'exp:3:99']);
    expect(alerts.last.text, '');
    expect(parseMaTvAlerts(null), isEmpty);
    expect(parseMaTvAlerts({'alerts': 'x'}), isEmpty);
  });

  test('each alert is shown once, and the memory stays small', () {
    const a = MaTvAlert(id: 'a', kind: '', title: 'A', text: '');
    const b = MaTvAlert(id: 'b', kind: '', title: 'B', text: '');
    final first = newMaTvAlerts([a, b], const ['a']);
    expect(first.fresh.map((x) => x.id), ['b']);
    expect(first.shown, ['a', 'b']);
    expect(newMaTvAlerts([a, b], first.shown).fresh, isEmpty);
    final many = newMaTvAlerts([b], [for (var i = 0; i < 70; i++) 'x$i'], keep: 60);
    expect(many.shown.length, 60);
    expect(many.shown.last, 'b');
  });
}
