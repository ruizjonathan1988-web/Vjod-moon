import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/ui/widgets/focusable_dialog_row.dart';
import 'package:moonfin/ui/widgets/seerr/seerr_for_you_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _film = AggregatedItem(
  id: '603',
  serverId: 'seerr',
  rawData: {'Name': 'Matrix', 'Type': 'Movie', 'SeerrMediaType': 'movie'},
);

Future<void> _open(WidgetTester tester, {required bool detailsFirst, required VoidCallback onDetails}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showSeerrForYouSheet(
              context: context,
              item: _film,
              because: null,
              openDetails: onDetails,
              detailsFirst: detailsFirst,
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

List<String> _labels(WidgetTester tester) =>
    tester.widgetList<FocusableDialogRow>(find.byType(FocusableDialogRow)).map((r) => r.label).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
  });

  tearDown(() => GetIt.instance.reset());

  testWidgets('appui long sur une affiche : « Voir la fiche » en premier, une seule fois', (tester) async {
    var opened = false;
    await _open(tester, detailsFirst: true, onDetails: () => opened = true);
    final labels = _labels(tester);
    expect(labels.first, 'Voir la fiche');
    expect(labels.where((l) => l == 'Voir la fiche'), hasLength(1));
    expect(tester.widget<FocusableDialogRow>(find.byType(FocusableDialogRow).first).autofocus, isTrue);
    await tester.tap(find.text('Voir la fiche'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('sans l\'option : l\'ordre d\'avant (demande d\'abord, fiche plus bas)', (tester) async {
    await _open(tester, detailsFirst: false, onDetails: () {});
    final labels = _labels(tester);
    expect(labels.first, isNot('Voir la fiche'));
    expect(labels, contains('Voir la fiche'));
  });
}
