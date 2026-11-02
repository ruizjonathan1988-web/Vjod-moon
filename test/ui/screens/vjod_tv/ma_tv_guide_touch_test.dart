// VJOD 4.16: on a phone the guide's hours move with the finger; once moved
// away from now, « Maintenant » brings them back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/ma_tv.dart';
import 'package:moonfin/ui/screens/vjod_tv/ma_tv_guide.dart';

void main() {
  final now = DateTime(2026, 11, 3, 20, 47);
  final chans = [
    MaTvChannel(id: 'tf1', number: 1, name: 'TF1'),
    MaTvChannel(id: 'f2', number: 2, name: 'France 2'),
  ];

  Widget grid({VoidCallback? back}) => MaterialApp(
    home: Scaffold(
      body: MaTvGuideView(
        channels: chans,
        programs: const {},
        row: 0,
        cursor: now,
        windowStart: DateTime(2026, 11, 3, 22),
        now: now,
        onBackToNow: back,
      ),
    ),
  );

  testWidgets('« Maintenant » quand les heures ont bougé, et il ramène à maintenant', (tester) async {
    var back = 0;
    await tester.pumpWidget(grid(back: () => back++));
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.schedule_rounded));
    expect(back, 1);
  });

  testWidgets('pas de bouton quand la grille est déjà sur maintenant', (tester) async {
    await tester.pumpWidget(grid());
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
  });
}
