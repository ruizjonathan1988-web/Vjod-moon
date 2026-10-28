import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/ma_tv.dart';

void main() {
  final now = DateTime(2026, 10, 28, 21, 0, 0);

  test('reads how far back the seedbox buffer goes', () {
    final s = MaTvShift.fromJson({'from': now.millisecondsSinceEpoch / 1000 - 600, 'to': 1, 'live': true, 'max_min': 30});
    expect(s.available, isTrue);
    expect(s.maxMinutes, 30);
    expect(now.difference(s.from!), const Duration(minutes: 10));
    expect(MaTvShift.fromJson({'off': true}).available, isFalse);
    expect(MaTvShift.fromJson(null).available, isFalse);
  });

  test('a delay never goes further back than the buffer, nor below zero', () {
    final s = MaTvShift(from: now.subtract(const Duration(minutes: 2)));
    expect(s.clamp(const Duration(seconds: 30), now), const Duration(seconds: 30));
    // 5 min asked, 2 min kept: as far as it goes, with a little margin
    expect(s.clamp(const Duration(minutes: 5), now), const Duration(minutes: 2) - const Duration(seconds: 3));
    expect(s.clamp(const Duration(seconds: -10), now), Duration.zero);
    expect(const MaTvShift().clamp(const Duration(seconds: 30), now), Duration.zero);
  });

  test('tells whether the start of a programme is still kept', () {
    final s = MaTvShift(from: now.subtract(const Duration(minutes: 20)));
    expect(s.holds(now.subtract(const Duration(minutes: 10))), isTrue);
    expect(s.holds(now.subtract(const Duration(minutes: 25))), isFalse);
  });
}
