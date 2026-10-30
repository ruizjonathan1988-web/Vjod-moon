import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/vjod/vjod_intro.dart';

void main() {
  testWidgets('chaque ouverture se dessine du début à la fin, puis ouvre l\'app', (tester) async {
    VjodIntro.muted = true;
    await tester.runAsync(VjodIntro.preload);
    for (final size in const [Size(1920, 1080), Size(412, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      for (final style in VjodIntroStyle.values) {
        var done = 0;
        await tester.pumpWidget(MaterialApp(home: VjodIntro(key: UniqueKey(), style: style, onDone: () => done++)));
        for (var i = 0; i < 80; i++) {
          await tester.pump(const Duration(milliseconds: 80));
        }
        expect(tester.takeException(), isNull, reason: style.name);
        expect(done, 1, reason: '${style.name} doit se terminer une fois');
      }
    }
    tester.view.reset();
  });

  testWidgets('une touche passe l\'ouverture', (tester) async {
    VjodIntro.muted = true;
    await tester.runAsync(VjodIntro.preload);
    var done = 0;
    await tester.pumpWidget(MaterialApp(home: VjodIntro(style: VjodIntroStyle.terminal, onDone: () => done++)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(done, 1);
    await tester.pump(const Duration(seconds: 6));
    expect(done, 1);
  });
}
