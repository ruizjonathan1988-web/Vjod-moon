import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/ma_tv_recordings.dart';

void main() {
  final start = DateTime(2026, 10, 30, 20, 50);
  final end = DateTime(2026, 10, 30, 22, 30);
  int s(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  test('a recording reads from Ma TV', () {
    final r = MaTvRecording.fromJson({
      'id': 'ab12',
      'chan': 'tf1',
      'chan_name': 'TF1',
      'num': 1,
      'title': 'Le film',
      'sub': 'Partie 1',
      'start': s(start),
      'end': s(end),
      'status': 'done',
      'keep': true,
      'size': 3 << 30,
    })!;
    expect(r.number, 1);
    expect(r.start, start);
    expect(r.keep, isTrue);
    expect(r.playable, isTrue);
    expect(MaTvRecording.fromJson({'title': 'sans numéro'}), isNull);
  });

  test('the guide finds what is scheduled for a programme', () {
    MaTvRecording rec(String id, String status, {String chan = 'tf1'}) => MaTvRecording.fromJson({
      'id': id,
      'chan': chan,
      'start': s(start),
      'end': s(end),
      'status': status,
    })!;
    final all = MaTvRecordings(items: [rec('a', 'done'), rec('b', 'scheduled', chan: 'm6')]);
    expect(all.of('tf1', start), isNull, reason: 'already recorded, not to come');
    expect(all.of('m6', start)?.id, 'b');
    expect(all.of('m6', start.add(const Duration(minutes: 30)))?.id, 'b', reason: 'inside the range');
    expect(all.of('m6', end), isNull);
    expect(rec('c', 'failed').playable, isFalse);
  });
}
