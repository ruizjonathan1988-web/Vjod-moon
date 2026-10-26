import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/web_tv_remote.dart';

void main() {
  testWidgets('a pressed arrow moves the focus like the remote', (
    tester,
  ) async {
    final top = FocusNode(debugLabel: 'top');
    final bottom = FocusNode(debugLabel: 'bottom');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextButton(focusNode: top, onPressed: () {}, child: const Text('A')),
              const SizedBox(height: 40),
              TextButton(
                focusNode: bottom,
                onPressed: () {},
                child: const Text('B'),
              ),
            ],
          ),
        ),
      ),
    );
    top.requestFocus();
    await tester.pump();
    expect(top.hasPrimaryFocus, isTrue);

    expect(pressRemoteKey('down'), isTrue);
    await tester.pump();
    expect(bottom.hasPrimaryFocus, isTrue);

    expect(pressRemoteKey('up'), isTrue);
    await tester.pump();
    expect(top.hasPrimaryFocus, isTrue);
  });

  testWidgets('a key handler on the way gets the press first', (tester) async {
    final node = FocusNode(debugLabel: 'card');
    LogicalKeyboardKey? seen;
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent) seen = event.logicalKey;
            return KeyEventResult.handled;
          },
          child: Focus(focusNode: node, child: const SizedBox()),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    expect(pressRemoteKey('right'), isTrue);
    expect(seen, LogicalKeyboardKey.arrowRight);
    expect(pressRemoteKey('nonsense'), isFalse);
  });
}
