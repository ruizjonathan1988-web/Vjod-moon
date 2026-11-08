import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/repositories/seerr_repository.dart';

void main() {
  final t = DateTime(2026, 11, 8, 20);

  test('Seerr est relancé au plus une fois par minute', () {
    expect(seerrFreshenDue(null, t), isTrue);
    expect(seerrFreshenDue(t, t.add(const Duration(seconds: 30))), isFalse);
    expect(seerrFreshenDue(t, t.add(const Duration(minutes: 1))), isTrue);
  });
}
