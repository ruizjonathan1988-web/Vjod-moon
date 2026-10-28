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
import 'package:moonfin/data/services/vjod/ma_tv.dart';
import 'package:moonfin/ui/screens/vjod_tv/ma_tv_guide.dart';
import 'package:moonfin/ui/screens/vjod_tv/ma_tv_screen.dart';
import 'package:moonfin/ui/screens/vjod_tv/ma_tv_widgets.dart';
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

// Ma TV, VJOD's own live TV: sample lineup drawn without a seedbox.
final _maNow = DateTime(2026, 10, 28, 20, 47);

MaTvProgram _prog(String t, int startMin, int len, {String d = '', String c = ''}) {
  final s = DateTime(2026, 10, 28, 20).add(Duration(minutes: startMin));
  return MaTvProgram(title: t, start: s, end: s.add(Duration(minutes: len)), description: d, category: c);
}

final _maCats = [
  const MaTvCategory(id: 'fav', label: 'Favoris', kind: 'fav', count: 6),
  const MaTvCategory(id: 'recent', label: 'Récentes', kind: 'recent', count: 12),
  const MaTvCategory(id: 'all', label: 'Toutes les chaînes', kind: 'all', count: 4128),
  const MaTvCategory(id: 'replay', label: 'Avec replay', kind: 'replay', count: 64),
  const MaTvCategory(id: 't:Généraliste', label: 'Généraliste', kind: 'theme', count: 212),
  const MaTvCategory(id: 't:Info', label: 'Info', kind: 'theme', count: 96),
  const MaTvCategory(id: 't:Sport', label: 'Sport', kind: 'theme', count: 341),
  const MaTvCategory(id: 't:Cinéma', label: 'Cinéma', kind: 'theme', count: 180),
  const MaTvCategory(id: 't:Jeunesse', label: 'Jeunesse', kind: 'theme', count: 75),
  const MaTvCategory(id: 'c:FR', label: 'France', kind: 'country', count: 1019),
  const MaTvCategory(id: 'c:BE', label: 'Belgique', kind: 'country', count: 72),
];

final _maChans = [
  MaTvChannel(id: 'tf1', number: 1, name: 'TF1', quality: '1080p', replayDays: 7,
      now: _prog('Koh-Lanta, la tribu maudite', -10, 110, d: "Les aventuriers affrontent l'épreuve des poteaux, la plus redoutée de l'aventure. Qui tiendra le plus longtemps sous le soleil ?", c: 'Jeu'),
      next: _prog('Vendredi, tout est permis', 100, 95)),
  MaTvChannel(id: 'france2', number: 2, name: 'France 2', quality: '1080p', replayDays: 7,
      now: _prog('Envoyé spécial', 10, 115), next: _prog('Complément d’enquête', 125, 70)),
  MaTvChannel(id: 'france3', number: 3, name: 'France 3', quality: '720p',
      now: _prog('Meurtres à Collioure', 5, 95), next: _prog('Soir/3', 100, 30)),
  MaTvChannel(id: 'canalplus', number: 4, name: 'Canal+', quality: '1080p',
      now: _prog('Ligue des champions : PSG - Arsenal', 0, 120), next: _prog('Canal Champions Club', 120, 45)),
  MaTvChannel(id: 'france5', number: 5, name: 'France 5', quality: '720p',
      now: _prog('La grande librairie', 0, 90)),
  MaTvChannel(id: 'm6', number: 6, name: 'M6', quality: '1080p', replayDays: 2,
      now: _prog('Top Chef', -30, 140), next: _prog('Top Chef, les grands duels', 110, 60)),
  MaTvChannel(id: 'arte', number: 7, name: 'Arte', quality: '1080p',
      now: _prog('Le dessous des cartes', 40, 15)),
  const MaTvChannel(id: 'c8', number: 8, name: 'C8', quality: '720p'),
  MaTvChannel(id: 'w9', number: 9, name: 'W9', quality: '720p', now: _prog('Les Marseillais', 0, 60)),
];

Widget _maBrowser({bool narrow = false}) => MaTvBrowserView(
  categories: _maCats,
  category: 9,
  channels: _maChans,
  channel: 3,
  column: 1,
  now: _maNow,
  favorites: const {'tf1', 'canalplus'},
  details: [_maChans[3].now!, _maChans[3].next!, _prog('Le journal du foot', 165, 30)],
  showDetails: !narrow,
  narrow: narrow,
);

Widget _maPlayer() => Stack(
  children: [
    const Positioned.fill(child: ColoredBox(color: Color(0xFF1B2A1E))),
    Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: MaTvBanner(
        channel: _maChans[3],
        now: _maNow,
        sourceLine: 'Source 1/4 · 1080p · 50 i/s · 7,8 Mb/s',
        categoryLabel: 'France',
        favorite: true,
      ),
    ),
    Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: MaTvMiniGuide(
        channel: _maChans[0],
        programs: [_maChans[0].now!, _maChans[0].next!, _prog('Les experts', 195, 50)],
        now: _maNow,
        actions: const [
          (icon: Icons.restart_alt_rounded, label: 'Revoir depuis le début'),
          (icon: Icons.history_rounded, label: 'Replay de la chaîne'),
          (icon: Icons.star_rounded, label: 'Retirer des favoris'),
          (icon: Icons.tune_rounded, label: 'Sources'),
        ],
        selectedAction: 0,
      ),
    ),
  ],
);

Widget _maReplay() => Padding(
  padding: const EdgeInsets.all(24),
  child: MaTvReplayList(
    channel: _maChans[0],
    now: _maNow,
    selected: 1,
    programs: [
      _prog('Le 20h', -47, 40),
      _prog('Koh-Lanta, la tribu maudite', -1450, 110, c: 'Jeu'),
      _prog('Le 13h', -1860, 45),
      _prog('Grey’s Anatomy', -2900, 50, c: 'Série'),
    ],
  ),
);

Widget _maGrid() {
  final progs = <String, List<MaTvProgram>>{};
  for (final ch in _maChans) {
    final list = <MaTvProgram>[];
    if (ch.now != null) {
      list.add(_prog('Le journal', ch.now!.start.difference(DateTime(2026, 10, 28, 20)).inMinutes - 40, 40));
      list.add(ch.now!);
    }
    if (ch.next != null) list.add(ch.next!);
    progs[ch.id] = list;
  }
  return MaTvGuideView(
    channels: _maChans,
    programs: progs,
    row: 0,
    cursor: _maNow,
    windowStart: DateTime(2026, 10, 28, 20, 30),
    now: _maNow,
    categoryLabel: 'France',
    favorites: const {'tf1'},
  );
}

Widget _maKids() => MaTvBrowserView(
  categories: const [MaTvCategory(id: 't:Jeunesse', label: 'Dessins animés et jeunesse', kind: 'theme', count: 4)],
  category: 0,
  channels: [
    MaTvChannel(id: 'gulli', number: 18, name: 'Gulli', now: _prog('Les Lapins crétins', 30, 25)),
    MaTvChannel(id: 'tiji', number: 201, name: 'TiJi', now: _prog('Peppa Pig', 40, 10)),
    MaTvChannel(id: 'canalj', number: 202, name: 'Canal J', now: _prog('Grizzy et les Lemmings', 35, 20)),
    MaTvChannel(id: 'disneyjr', number: 203, name: 'Disney Junior', now: _prog('Bluey', 42, 8)),
  ],
  channel: 1,
  column: 1,
  now: _maNow,
  showDetails: false,
  title: 'TV des enfants',
);

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

  testWidgets('Ma TV browser', (tester) async {
    await shoot(tester, _maBrowser(), const Size(1280, 720), 'matv_browser');
  });

  testWidgets('Ma TV player', (tester) async {
    await shoot(tester, _maPlayer(), const Size(1280, 720), 'matv_player');
  });

  testWidgets('Ma TV replay', (tester) async {
    await shoot(tester, _maReplay(), const Size(720, 420), 'matv_replay');
  });

  testWidgets('Ma TV grid', (tester) async {
    await shoot(tester, _maGrid(), const Size(1280, 720), 'matv_grid');
  });

  testWidgets('Ma TV kids', (tester) async {
    await shoot(tester, _maKids(), const Size(1280, 720), 'matv_kids');
  });

  testWidgets('Ma TV Fold', (tester) async {
    await shoot(tester, _maBrowser(narrow: true), const Size(412, 900), 'matv_fold');
  });
}
