import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/services/row_data_source.dart';
import '../../../data/services/vjod/vjod_collections.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/top_toolbar.dart';
import '../../widgets/vjod/vjod_widgets.dart';

/// The SmartLists collections that VJOD now draws itself from the whole
/// catalogue. Until they are deleted from the server, Explorer leaves them
/// out so nothing shows twice.
const _replacedSmartLists = {
  'feel good',
  'mode pop-corn',
  'mouchoirs obligatoires',
  'ça retourne le cerveau',
  'nuit blanche',
  'grand spectacle',
  'petit film, grosse claque',
  'soirée en famille',
  'pépites jamais vues',
  'casses & braquages',
  'voyages dans le temps',
  "perdus dans l'espace",
  'fin du monde',
  "dans la tête d'un tueur",
  'mafia & gangsters',
  'évasions',
  'machines & ia',
  "inspiré d'une histoire vraie",
  'à binger ce week-end',
  'épisodes de 30 min',
  'toujours en cours',
  'le meilleur du cinéma français',
  'cinéma russe & soviétique',
  'cinéma coréen & japonais',
};

/// Names that make a server collection a palmarès: awards, top lists,
/// classics.
bool _isPalmares(String name) {
  final n = name.toLowerCase();
  return n.contains('top 250') ||
      n.contains('oscar') ||
      n.contains('cannes') ||
      n.contains('césar') ||
      n.contains('cesar') ||
      n.contains('palmarès') ||
      n.contains('grands classiques');
}

/// Each family's tint, so the tiles read at a glance from the sofa.
Color _familyColor(VjodFamily family) => switch (family) {
  VjodFamily.ready => const Color(0xFF1F7A4D),
  VjodFamily.ambiances => const Color(0xFF8E3B46),
  VjodFamily.themes => const Color(0xFF3D4E8C),
  VjodFamily.series => const Color(0xFF7A5A1F),
  VjodFamily.studios => const Color(0xFF5B3D8C),
  VjodFamily.world => const Color(0xFF1F6A7A),
};

IconData _familyIcon(VjodFamily family) => switch (family) {
  VjodFamily.ready => Icons.play_circle_outline_rounded,
  VjodFamily.ambiances => Icons.local_fire_department_outlined,
  VjodFamily.themes => Icons.style_outlined,
  VjodFamily.series => Icons.tv_rounded,
  VjodFamily.studios => Icons.movie_filter_outlined,
  VjodFamily.world => Icons.public_rounded,
};

/// Explorer: every VJOD collection, family by family, each one the whole
/// catalogue (what the server holds first, the rest a press away from being
/// asked for), then the server's own palmarès and sagas.
class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key});

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  List<AggregatedItem> _palmares = const [];
  List<AggregatedItem> _sagas = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadServerCollections());
  }

  Future<void> _loadServerCollections() async {
    try {
      final client = GetIt.instance<MediaServerClient>();
      final all = await RowDataSource(client).loadBoxSets(client.baseUrl);
      final palmares = <AggregatedItem>[];
      final sagas = <AggregatedItem>[];
      for (final item in all) {
        final name = item.name;
        if (_replacedSmartLists.contains(name.toLowerCase().trim())) continue;
        (_isPalmares(name) ? palmares : sagas).add(item);
      }
      if (!mounted) return;
      setState(() {
        _palmares = palmares;
        _sagas = sagas;
      });
    } catch (e) {
      debugPrint('[Explorer] Server collections failed: $e');
    }
  }

  void _openCollection(VjodCollection c, bool french) {
    context.push(
      Destinations.seerrBrowseWith(
        filterId: c.id,
        filterName: c.title(french),
        mediaType: c.query.mediaType,
        filterType: vjodFilterType,
      ),
    );
  }

  void _openServerCollection(AggregatedItem item) {
    context.push(Destinations.item(item.id, serverId: item.serverId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: Destinations.explorer,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final french = l10n.localeName.startsWith('fr');
    final prefs = GetIt.instance<UserPreferences>();
    final isMobile = PlatformDetection.useMobileUi;
    final width = MediaQuery.sizeOf(context).width;
    final s = isMobile ? 0.8 : (width / 1280).clamp(0.6, 1.2);
    final navbarIsTop =
        prefs.get(UserPreferences.navbarPosition) == NavbarPosition.top;
    final navbarHeight = navbarIsTop
        ? (PlatformDetection.isTV ? 95.0 : (isMobile ? 60.0 : 80.0))
        : 0.0;
    final left = isMobile ? 16.0 : 64 * s;
    final top = MediaQuery.paddingOf(context).top + navbarHeight + 12;
    final narrow = TopToolbar.vjodNarrow(context);
    final now = DateTime.now();

    // Two tiles a row on a phone, a fixed width elsewhere.
    final tileW = isMobile
        ? ((width - 2 * left - 12) / 2).floorToDouble()
        : 250 * s;
    final tileH = isMobile ? 104.0 : 118 * s;
    final gap = isMobile ? 12.0 : 15 * s;

    var first = true;
    bool takeFirst() {
      final was = first;
      first = false;
      return was && PlatformDetection.isTV;
    }

    Widget sectionTitle(String text) => Padding(
      padding: EdgeInsets.only(top: 26 * s, bottom: 12 * s),
      child: Text(text.toUpperCase(), style: vjodDisplay(26 * s)),
    );

    final children = <Widget>[];

    if (narrow) {
      // Bientôt has no tab of its own on a phone: it starts Explorer.
      children.add(
        Padding(
          padding: EdgeInsets.only(top: 6 * s),
          child: _ExplorerTile(
            width: width - 2 * left,
            height: tileH * 0.8,
            scale: s,
            color: vjodRed,
            icon: Icons.calendar_month_outlined,
            title: l10n.vjodTabSoon,
            subtitle: l10n.vjodSoonHint,
            autofocus: takeFirst(),
            onTap: () => context.push(Destinations.bientot),
          ),
        ),
      );
    }

    for (final family in VjodFamily.values) {
      final collections = [
        for (final c in vjodCollections)
          if (c.family == family && c.inSeason(now)) c,
      ];
      if (collections.isEmpty) continue;
      children
        ..add(sectionTitle(vjodFamilyTitle(family, french)))
        ..add(
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final c in collections)
                _ExplorerTile(
                  width: tileW,
                  height: tileH,
                  scale: s,
                  color: _familyColor(family),
                  icon: c.query.mediaType == 'tv'
                      ? Icons.tv_rounded
                      : _familyIcon(family),
                  title: c.title(french),
                  subtitle: c.subtitle(french),
                  autofocus: takeFirst(),
                  onTap: () => _openCollection(c, french),
                ),
            ],
          ),
        );
    }

    void serverSection(String title, List<AggregatedItem> items, Color color,
        IconData icon) {
      if (items.isEmpty) return;
      children
        ..add(sectionTitle(title))
        ..add(
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final item in items)
                _ExplorerTile(
                  width: tileW,
                  height: tileH * 0.75,
                  scale: s,
                  color: color,
                  icon: icon,
                  title: item.name,
                  subtitle: '',
                  autofocus: takeFirst(),
                  onTap: () => _openServerCollection(item),
                ),
            ],
          ),
        );
    }

    serverSection(
      french ? 'Palmarès' : 'Awards & top lists',
      _palmares,
      const Color(0xFF8C6A1F),
      Icons.emoji_events_outlined,
    );
    serverSection(
      french ? 'Sagas & collections' : 'Sagas & collections',
      _sagas,
      const Color(0xFF3A3A44),
      Icons.collections_bookmark_outlined,
    );

    final header = Padding(
      padding: EdgeInsets.fromLTRB(left, top, left, 4 * s),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20 * s,
        runSpacing: 6,
        children: [
          Text('EXPLORER', style: vjodDisplay(48 * s)),
          Text(
            french
                ? 'Tout le catalogue : ce que vous avez, et le reste à demander'
                : 'The whole catalogue: what you have, and the rest to request',
            style: TextStyle(
              color: vjodInk.withValues(alpha: 0.55),
              fontSize: 17 * s,
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(left, 0, left, 48),
            children: children,
          ),
        ),
      ],
    );
  }
}

class _ExplorerTile extends StatelessWidget {
  final double width;
  final double height;
  final double scale;
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool autofocus;
  final VoidCallback onTap;

  const _ExplorerTile({
    required this.width,
    required this.height,
    required this.scale,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.autofocus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return VjodFocusable(
      autofocus: autofocus,
      onTap: onTap,
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: width,
        height: height,
        padding: EdgeInsets.all(14 * s),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, Color.lerp(color, Colors.black, 0.55)!],
          ),
          boxShadow: vjodFocusRing(s, on: focused),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -6 * s,
              bottom: -10 * s,
              child: Icon(
                icon,
                size: height * 0.62,
                color: Colors.white.withValues(alpha: 0.13),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19 * s,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  SizedBox(height: 4 * s),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13.5 * s,
                      height: 1.15,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
