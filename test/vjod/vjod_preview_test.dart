// Draws VJOD's screens from their pieces, with placeholder colours where the
// posters go, the way the mock-up does, so the two can be laid side by side.
// CI runs it with --update-goldens and keeps the pictures on the captures
// branch; it checks nothing by itself.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/l10n/app_localizations.dart';
import 'package:moonfin/ui/widgets/seerr/seerr_status_dot.dart';
import 'package:moonfin/ui/widgets/vjod/vjod_widgets.dart';
import 'package:moonfin_design/moonfin_design.dart';

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  var any = false;
  for (final p in paths) {
    final f = File(p);
    if (!f.existsSync()) continue;
    any = true;
    final bytes = f.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  if (any) await loader.load();
}

Future<void> _loadFonts() async {
  await _font('Roboto', [
    'assets/fonts/Roboto-Regular.ttf',
    'assets/fonts/Roboto-Medium.ttf',
    'assets/fonts/Roboto-Bold.ttf',
  ]);
  await _font('Anton', ['assets/fonts/Anton-Regular.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    await _font('MaterialIcons', [
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ]);
  }
}

const _hues = [
  Color(0xFF3B2A17),
  Color(0xFF4A1A24),
  Color(0xFF1F2A33),
  Color(0xFF202020),
  Color(0xFF2C2C3A),
  Color(0xFF33301A),
  Color(0xFF2D3328),
  Color(0xFF33262A),
];

Widget _app(Widget child, Size size) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('fr'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Roboto'),
  home: Scaffold(
    backgroundColor: AppColorScheme.background,
    body: SizedBox(width: size.width, height: size.height, child: child),
  ),
);

Widget _poster(int i, {int? status, bool requestable = false, String? title}) =>
    Container(
      width: 137,
      height: 205,
      decoration: BoxDecoration(
        color: _hues[i % _hues.length],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          if (SeerrStatusTag.shows(status, requestable: requestable))
            Positioned(
              left: 6,
              top: 6,
              child: SeerrStatusTag(status: status, requestable: requestable),
            ),
          if (title != null)
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(title.toUpperCase(), style: vjodDisplay(20)),
            ),
        ],
      ),
    );

Widget _tvHome() {
  const s = 1.0;
  return Stack(
    children: [
      Positioned(
        left: 0,
        top: 0,
        right: 0,
        height: 480,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF3A3226), AppColorScheme.background],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      Positioned(
        left: 64,
        right: 64,
        top: 30,
        child: VjodNavBar(
          scale: s,
          avatarInitial: 'J',
          onSearch: () {},
          onAvatar: () {},
          tabs: [
            VjodNavItem(label: 'Accueil', selected: true, onTap: () {}),
            VjodNavItem(label: 'Films', onTap: () {}),
            VjodNavItem(label: 'Séries', onTap: () {}),
            VjodNavItem(label: 'Bientôt', onTap: () {}),
            VjodNavItem(label: 'En route', badge: 2, onTap: () {}),
          ],
        ),
      ),
      Positioned(
        left: 64,
        top: 112,
        width: 760,
        child: VjodHeroContent(
          tonightLabel: 'Ce soir',
          answers: const ['Entre amis', '1 h 45 max', 'Rire'],
          changeLabel: 'Changer',
          onChange: () {},
          kicker: 'Le bon film pour vous trois',
          title: 'Le Grand Chemin',
          statusLabel: 'Prêt',
          meta: const ['Comédie', '1 h 47'],
          endsAt: 'Fin à 22:30',
          activeAction: 0,
          actions: [
            VjodHeroAction(label: 'Lecture', icon: Icons.play_arrow_rounded, onTap: () {}),
            VjodHeroAction(label: 'Autre idée', onTap: () {}),
            VjodHeroAction(label: 'Infos', onTap: () {}),
          ],
        ),
      ),
      Positioned(
        left: 64,
        top: 430,
        child: Row(
          children: [
            const VjodPickCard(
              label: 'Reprendre',
              title: 'Shōgun',
              subtitle: 'Épisode 4 · reste 32 min',
              progress: 0.55,
              placeholder: Color(0xFF2B2F3A),
            ),
            const SizedBox(width: 24),
            const VjodPickCard(
              label: 'Le bon film pour vous trois',
              title: 'Le Grand Chemin',
              subtitle: 'Prêt · Fin à 22:30',
              selected: true,
              placeholder: Color(0xFF3A3226),
            ),
            const SizedBox(width: 24),
            const VjodPickCard(
              label: 'Pas encore chez vous',
              title: 'The Holdovers',
              subtitle: 'Une pression pour le demander',
              placeholder: Color(0xFF232C33),
            ),
          ],
        ),
      ),
      Positioned(
        left: 64,
        right: 64,
        top: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VjodRowHeader(title: 'Continuer'),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  SizedBox(
                    width: 283,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 159,
                          decoration: BoxDecoration(
                            color: _hues[(i + 2) % _hues.length],
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          ['The Pitt', 'Les Simpson', 'Gen V', 'Solar Opposites'][i],
                          style: TextStyle(color: vjodInk, fontSize: 21, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'S1:E1 · reste 38 min',
                          style: TextStyle(color: vjodInk.withValues(alpha: 0.6), fontSize: 17),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 19),
                ],
              ],
            ),
            const SizedBox(height: 40),
            VjodRowHeader(
              title: 'Top 10 en France aujourd\'hui',
              trailing: VjodSegmented(
                options: const ['Films', 'Séries'],
                selected: 0,
                onSelect: (_) {},
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < 6; i++)
                  SizedBox(
                    width: 192,
                    height: 190,
                    child: Stack(
                      children: [
                        Positioned(left: 0, bottom: -10, child: VjodRankNumeral(rank: i + 1, height: 180)),
                        Positioned(
                          left: 50,
                          top: 0,
                          child: Transform.scale(
                            scale: 0.88,
                            alignment: Alignment.topLeft,
                            child: _poster(
                              i,
                              status: [SeerrMediaStatus.available, null, SeerrMediaStatus.pending, SeerrMediaStatus.processing, SeerrMediaStatus.available, null][i],
                              requestable: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 40),
            const VjodRowHeader(
              title: 'Pour vous',
              subtitle: 'Vos goûts, Trakt et BetaSeries réunis',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < 8; i++) ...[
                  _poster(
                    i + 3,
                    status: [SeerrMediaStatus.available, SeerrMediaStatus.processing, null, SeerrMediaStatus.pending][i % 4],
                    requestable: true,
                  ),
                  const SizedBox(width: 15),
                ],
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _tvMenu() => Stack(
  children: [
    Positioned.fill(child: Container(color: const Color(0xFF3A3226))),
    Positioned.fill(child: Container(color: const Color(0xB80B0B0D))),
    Positioned(
      right: 64,
      top: 104,
      child: VjodMenuPanel(
        name: 'Jon',
        initial: 'J',
        nowWatching: 'Shōgun en cours',
        changeLabel: 'Changer',
        onChange: () {},
        sectionLabel: 'Aussi dans VJOD',
        entries: [
          VjodMenuEntry(icon: Icons.shuffle_rounded, label: 'Aléatoire', subtitle: 'Un titre au hasard', onTap: () {}),
          VjodMenuEntry(icon: Icons.theater_comedy_outlined, label: 'Genres', onTap: () {}),
          VjodMenuEntry(icon: Icons.favorite_border_rounded, label: 'Mes favoris', onTap: () {}),
          VjodMenuEntry(icon: Icons.explore_outlined, label: 'Découvrir', subtitle: 'Tout le catalogue, à demander', onTap: () {}),
          VjodMenuEntry(icon: Icons.live_tv_rounded, label: 'TV en direct', onTap: () {}),
          VjodMenuEntry(icon: Icons.rule_rounded, label: 'Demandes à valider', badge: 2, onTap: () {}),
        ],
        settings: VjodMenuEntry(icon: Icons.settings_outlined, label: 'Réglages', onTap: () {}),
      ),
    ),
  ],
);

Widget _foldHome() {
  const s = 0.62;
  return Stack(
    children: [
      Positioned(
        left: 0,
        top: 0,
        right: 0,
        height: 400,
        child: Container(color: const Color(0xFF3A3226)),
      ),
      Positioned(
        left: 16,
        right: 16,
        top: 12,
        child: VjodNavBar(
          scale: s,
          avatarInitial: 'J',
          onSearch: () {},
          onAvatar: () {},
          tabs: const [],
        ),
      ),
      Positioned(
        left: 16,
        right: 16,
        top: 220,
        child: VjodHeroContent(
          scale: 0.9,
          compact: true,
          tonightLabel: 'Ce soir',
          answers: const ['Entre amis', '1 h 45 max', 'Rire'],
          changeLabel: 'Changer',
          onChange: () {},
          title: 'Le Grand Chemin',
          statusLabel: 'Prêt',
          meta: const ['Comédie', '1 h 47'],
          endsAt: 'Fin à 22:30',
          actions: [
            VjodHeroAction(label: 'Lecture', icon: Icons.play_arrow_rounded, onTap: () {}),
            VjodHeroAction(label: 'Autre idée', onTap: () {}),
            VjodHeroAction(label: 'Infos', onTap: () {}),
          ],
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: VjodBottomBar(
          tabs: [
            VjodNavItem(label: 'Accueil', icon: Icons.home_rounded, selected: true, onTap: () {}),
            VjodNavItem(label: 'Films', icon: Icons.movie_outlined, onTap: () {}),
            VjodNavItem(label: 'Séries', icon: Icons.tv_rounded, onTap: () {}),
            VjodNavItem(label: 'Bientôt', icon: Icons.calendar_month_outlined, onTap: () {}),
            VjodNavItem(label: 'En route', icon: Icons.downloading_rounded, badge: 2, onTap: () {}),
          ],
        ),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
    ThemeRegistry.setActiveById('vjod');
  });

  Future<void> shoot(
    WidgetTester tester,
    Widget child,
    Size size,
    String name,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(child, size));
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = element.widget as Image;
        await precacheImage(image.image, element);
      }
    });
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('captures/$name.png'));
  }

  testWidgets('VJOD TV home', (tester) async {
    await shoot(tester, _tvHome(), const Size(1280, 1500), 'tv_home');
  });

  testWidgets('VJOD TV avatar menu', (tester) async {
    await shoot(tester, _tvMenu(), const Size(1280, 720), 'tv_menu');
  });

  testWidgets('VJOD Fold home', (tester) async {
    await shoot(tester, _foldHome(), const Size(412, 900), 'fold_home');
  });
}
