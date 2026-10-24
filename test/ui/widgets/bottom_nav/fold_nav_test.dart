import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/layout/screen_form.dart';
import 'package:moonfin/ui/widgets/bottom_nav/bottom_navbar.dart';
import 'package:moonfin/ui/widgets/bottom_nav/fold_nav.dart';

import 'bottom_nav_fakes.dart';

// Window sizes in logical pixels as a Galaxy Z Fold8 reports them.
const _cover = Size(467, 737);
const _openPortrait = Size(734, 974);
const _openLandscape = Size(974, 734);

/// The page under the navigation, reporting the room it is given.
class _Probe extends StatelessWidget {
  final ValueSetter<Size> onSize;

  const _Probe(this.onSize);

  @override
  Widget build(BuildContext context) {
    onSize(MediaQuery.sizeOf(context));
    return const SizedBox.expand();
  }
}

void main() {
  late UserPreferences prefs;
  Size? content;

  setUp(() async {
    prefs = (await setUpBottomNav()).prefs;
    content = null;
  });

  tearDown(() async {
    Tabletop.forced.value = false;
    await tearDownBottomNav();
  });

  Future<void> show(WidgetTester tester, Size size) async {
    usePhoneView(tester, size: size);
    await tester.pumpWidget(bottomNavApp(child: _Probe((s) => content = s)));
    await tester.pump();
  }

  testWidgets('folded, the cover screen keeps the bottom navbar', (
    tester,
  ) async {
    await show(tester, _cover);
    expect(find.byType(BottomNavbar), findsOneWidget);
    expect(find.byType(NavRail), findsNothing);
  });

  testWidgets('opened, the navbar moves to a rail and the page narrows', (
    tester,
  ) async {
    await show(tester, _openPortrait);
    expect(find.byType(NavRail), findsOneWidget);
    expect(find.byType(BottomNavbar), findsNothing);
    expect(content?.width, _openPortrait.width - FoldNavMetrics.railWidth);
    expect(content?.height, _openPortrait.height);
    // A Fold8 stands half folded in portrait.
    expect(find.byIcon(Icons.laptop_rounded), findsOneWidget);
  });

  testWidgets('the rail can be turned off', (tester) async {
    await prefs.set(UserPreferences.unfoldedNavRail, false);
    await show(tester, _openPortrait);
    expect(find.byType(BottomNavbar), findsOneWidget);
    expect(find.byType(NavRail), findsNothing);
  });

  testWidgets('tabletop by hand splits the screen and ends on request', (
    tester,
  ) async {
    await show(tester, _openLandscape);
    await tester.tap(find.byIcon(Icons.laptop_rounded));
    await tester.pump();

    expect(Tabletop.forced.value, isTrue);
    expect(find.byType(TabletopNavPanel), findsOneWidget);
    expect(find.byType(NavRail), findsNothing);
    expect(content?.height, _openLandscape.height / 2);
    expect(content?.width, _openLandscape.width);

    await tester.tap(find.byIcon(Icons.fullscreen_rounded));
    await tester.pump();
    expect(Tabletop.forced.value, isFalse);
    expect(find.byType(NavRail), findsOneWidget);
  });

  testWidgets('folding the phone ends a forced tabletop', (tester) async {
    await show(tester, _openLandscape);
    Tabletop.forced.value = true;
    await tester.pump();
    expect(find.byType(TabletopNavPanel), findsOneWidget);

    tester.view.physicalSize = _cover * tester.view.devicePixelRatio;
    await tester.pump();
    expect(Tabletop.forced.value, isFalse);
    expect(find.byType(BottomNavbar), findsOneWidget);
  });
}
