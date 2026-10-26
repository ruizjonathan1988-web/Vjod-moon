import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/viewmodels/seerr_discover_view_model.dart';
import '../../widgets/offline_aware_image.dart';
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

/// The mock-up's muted tile colours, picked by name so a tile keeps its
/// colour from one visit to the next.
const _tileHues = [
  Color(0xFF3A2A2A),
  Color(0xFF26313B),
  Color(0xFF2F3A2C),
  Color(0xFF3B3326),
  Color(0xFF2D2A3A),
  Color(0xFF3A2632),
  Color(0xFF243534),
  Color(0xFF33302A),
  Color(0xFF2A3240),
  Color(0xFF3D2B23),
];

Color _tileHue(String key) {
  var h = 0;
  for (final unit in key.codeUnits) {
    h = (h * 31 + unit) & 0xFFFFFFFF;
  }
  return _tileHues[h % _tileHues.length];
}

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

  /// The studio's or the service's logo, from Seerr's own lists.
  static String? _logoFor(VjodCollection c) {
    final studio = c.query.studio;
    if (studio != null) {
      for (final st in SeerrDiscoverViewModel.popularStudios) {
        if (st.id == studio) return st.logoPath;
      }
    }
    final network = c.query.network;
    if (network != null) {
      for (final n in SeerrDiscoverViewModel.popularNetworks) {
        if (n.id == network) return n.logoPath;
      }
    }
    return null;
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
    final now = DateTime.now();

    // Two tiles a row on a phone, five on a TV, as in the mock-up.
    final gap = isMobile ? 12.0 : 16 * s;
    final columns = isMobile ? 2 : 5;
    final tileW = ((width - 2 * left - (columns - 1) * gap) / columns)
        .floorToDouble();
    final tileH = isMobile ? 96.0 : 128 * s;

    var first = true;
    bool takeFirst() {
      final was = first;
      first = false;
      return was && PlatformDetection.isTV;
    }

    Widget sectionTitle(String text) => Padding(
      padding: EdgeInsets.only(top: 30 * s, bottom: 14 * s),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: vjodInk.withValues(alpha: 0.7),
          fontSize: 15 * s,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
    );

    final children = <Widget>[];

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
                  color: _logoFor(c) != null
                      ? const Color(0xFF1C1D22)
                      : _tileHue(c.id),
                  chip: family == VjodFamily.ready
                      ? vjodFamilyTitle(family, french)
                      : null,
                  title: c.title(french),
                  logoUrl: _logoFor(c),
                  autofocus: takeFirst(),
                  onTap: () => _openCollection(c, french),
                ),
            ],
          ),
        );
    }

    void serverSection(String title, List<AggregatedItem> items) {
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
                  height: tileH,
                  scale: s,
                  color: _tileHue(item.name),
                  title: item.name,
                  autofocus: takeFirst(),
                  onTap: () => _openServerCollection(item),
                ),
            ],
          ),
        );
    }

    serverSection(french ? 'Palmarès' : 'Awards & top lists', _palmares);
    serverSection('Sagas & collections', _sagas);

    // On a phone Bientôt has no tab of its own: it sits at the end of Explorer.
    if (TopToolbar.vjodNarrow(context)) {
    children
      ..add(sectionTitle(l10n.vjodTabSoon))
      ..add(
        Wrap(
          children: [
            _ExplorerTile(
              width: tileW,
              height: tileH,
              scale: s,
              color: _tileHue('bientot'),
              title: l10n.vjodTabSoon,
              autofocus: takeFirst(),
              onTap: () => context.push(Destinations.bientot),
            ),
          ],
        ),
      );
    }

    final header = Padding(
      padding: EdgeInsets.fromLTRB(left, top, left, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EXPLORER', style: vjodDisplay(56 * s)),
          SizedBox(height: 8 * s),
          Text(
            french
                ? 'Coche verte : disponible. + rouge : à demander, prêt en une dizaine de minutes.'
                : 'Green tick: available. Red +: to request, ready in about ten minutes.',
            style: TextStyle(
              color: vjodInk.withValues(alpha: 0.65),
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
  final String? chip;
  final String title;
  final bool autofocus;
  final VoidCallback onTap;

  /// A studio's or a service's logo, drawn in place of the name.
  final String? logoUrl;

  const _ExplorerTile({
    required this.width,
    required this.height,
    required this.scale,
    required this.color,
    required this.title,
    required this.autofocus,
    required this.onTap,
    this.chip,
    this.logoUrl,
  });

  Widget _nameText(double s) => Text(
    title.toUpperCase(),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: vjodDisplay(24 * s).copyWith(height: 1.05),
  );

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
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: color,
          boxShadow: vjodFocusRing(s, on: focused),
        ),
        child: logoUrl != null
            ? Padding(
                padding: EdgeInsets.all(10 * s),
                child: OfflineAwareImage(
                  imageUrl: logoUrl!,
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) =>
                      Align(alignment: Alignment.bottomLeft, child: _nameText(s)),
                ),
              )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (chip != null)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 9 * s,
                  vertical: 3 * s,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF7FD6A8).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  chip!,
                  style: TextStyle(
                    color: const Color(0xFF7FD6A8),
                    fontSize: 12 * s,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              const SizedBox.shrink(),
            _nameText(s),
          ],
        ),
      ),
    );
  }
}
