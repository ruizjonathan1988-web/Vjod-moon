import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/seerr_http_client.dart';

void main() {
  test('Seerr qui ne répond plus : laissé tranquille 2 minutes après 3 délais dépassés', () {
    final p = SeerrPause();
    final t0 = DateTime(2026, 11, 8, 0, 10);
    expect(p.counts(DioExceptionType.receiveTimeout), isTrue);
    expect(p.counts(DioExceptionType.badResponse), isFalse);
    p.timedOut(t0);
    p.timedOut(t0);
    expect(p.paused(t0), isFalse);
    p.timedOut(t0);
    expect(p.paused(t0.add(const Duration(seconds: 30))), isTrue);
    expect(p.paused(t0.add(const Duration(minutes: 3))), isFalse, reason: 'nouvel essai après la pause');
    p.timedOut(t0.add(const Duration(minutes: 3)));
    expect(p.paused(t0.add(const Duration(minutes: 3, seconds: 1))), isTrue, reason: 'encore muet : nouvelle pause tout de suite');
    p.answered();
    expect(p.paused(t0.add(const Duration(minutes: 3, seconds: 2))), isFalse, reason: 'une réponse lève la pause');
  });
}
