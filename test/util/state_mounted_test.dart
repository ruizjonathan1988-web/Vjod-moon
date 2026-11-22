import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/state_mounted.dart';

/// A tiny screen whose button runs [setStateIfMounted] after an await, so the
/// test can unmount it mid-await and check nothing throws.
class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.gate});
  final Future<void> gate;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int value = 0;

  Future<void> bump() async {
    await widget.gate;
    setStateIfMounted(() => value++);
  }

  @override
  Widget build(BuildContext context) => Text('$value', textDirection: TextDirection.ltr);
}

void main() {
  testWidgets('setStateIfMounted met à jour l\'écran encore ouvert', (tester) async {
    final gate = Future<void>.value();
    final key = GlobalKey<_ProbeState>();
    await tester.pumpWidget(_Probe(key: key, gate: gate));
    await key.currentState!.bump();
    await tester.pump();
    expect(key.currentState!.value, 1);
  });

  testWidgets('setStateIfMounted ne plante pas après la fermeture de l\'écran', (tester) async {
    final gate = Completer<void>();
    final key = GlobalKey<_ProbeState>();
    await tester.pumpWidget(_Probe(key: key, gate: gate.future));
    final state = key.currentState!;
    final pending = state.bump(); // attend sur la barrière
    // L'utilisateur quitte l'écran avant la fin de l'attente.
    await tester.pumpWidget(const SizedBox());
    expect(state.mounted, isFalse);
    gate.complete(); // l'attente se termine : setState serait lancé sur un écran fermé
    await pending; // ne doit rien lever
    expect(state.value, 0);
  });
}
