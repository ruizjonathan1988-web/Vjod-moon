import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/overlay_sheet.dart';

/// Root cause of the « Null check operator used on a null value » crash when
/// tapping the cast mini-player: showFocusRestoringModalBottomSheet goes
/// through Navigator.of, so a context with no Navigator above it throws. The
/// mini-player sits outside the app's navigator, so it must open the sheet on
/// the root navigator context (VJOD 5.19).
void main() {
  testWidgets('un contexte sans Navigator fait échouer l\'ouverture de la feuille', (tester) async {
    late BuildContext noNavigator;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            noNavigator = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      () => showFocusRestoringModalBottomSheet<void>(
        context: noNavigator,
        builder: (_) => const SizedBox(),
      ),
      throwsA(anything),
    );
  });

  testWidgets('un contexte avec Navigator ouvre bien la feuille', (tester) async {
    late BuildContext withNavigator;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            withNavigator = context;
            return const Scaffold();
          },
        ),
      ),
    );
    showFocusRestoringModalBottomSheet<void>(
      context: withNavigator,
      builder: (_) => const Material(child: Text('feuille')),
    );
    await tester.pumpAndSettle();
    expect(find.text('feuille'), findsOneWidget);
  });
}
