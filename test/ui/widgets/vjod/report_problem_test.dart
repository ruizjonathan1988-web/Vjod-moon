// VJOD 4.12: the WhatsApp message says what was on screen and the last
// problem the device noted, so the admin knows at once what it is about.
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/ma_tv_reports.dart';
import 'package:moonfin/ui/widgets/vjod/report_problem.dart';

void main() {
  final now = DateTime(2026, 11, 2, 21, 30);
  int at(Duration ago) => now.subtract(ago).millisecondsSinceEpoch ~/ 1000;

  test('ce qui est à l’écran et le dernier souci récent', () {
    final text = reportProblemText(
      intro: 'Problème sur VJOD :',
      what: 'Chaîne 1 TF1 · La chaîne ne répond pas',
      last: MaTvReport(kind: 'play', message: 'La chaîne ne répond pas', channel: '1 TF1', at: at(const Duration(minutes: 3))),
      version: '4.12',
      device: 'TV · AFTMM',
      deviceId: 'k3x9a',
      now: now,
    );
    expect(text, startsWith('Problème sur VJOD :\n\n\n'));
    expect(text, contains('— Chaîne 1 TF1 · La chaîne ne répond pas'));
    expect(text, contains('— Dernier souci noté : lecture ratée (1 TF1), il y a 3 min : La chaîne ne répond pas'));
    expect(text, contains('— VJOD 4.12 · TV · AFTMM'));
    expect(text, contains('— Appareil k3x9a (page Ma TV)'));
  });

  test('un souci de plus d’un jour n’est pas rappelé, un long message est coupé', () {
    final old = reportProblemText(
      intro: 'Problème sur VJOD :',
      last: MaTvReport(kind: 'crash', message: 'vieux', at: at(const Duration(days: 2))),
      version: '4.12',
      device: 'Mobile',
      now: now,
    );
    expect(old.contains('Dernier souci'), isFalse);
    final long = reportProblemText(
      intro: 'Problème sur VJOD :',
      last: MaTvReport(kind: 'crash', message: 'x' * 300, at: at(const Duration(hours: 2))),
      version: '4.12',
      device: 'Mobile',
      now: now,
    );
    expect(long, contains('plantage, il y a 2 h : ${'x' * 117}…'));
  });
}
