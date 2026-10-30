// Films and Séries, as the whole catalogue: VJOD's tabs used to open the
// server's libraries only, and people took them for everything there is.
// Now they show what is popular, each poster saying how to watch it (on the
// server, at once from the IPTV provider, or to ask for), with a filter on
// top. The server's full library, with its sorting, stays one press away.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/seerr/seerr_api_models.dart';
import '../../../data/services/vjod/catalogue_availability.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../../util/vjod_text.dart';
import '../../navigation/destinations.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/offline_aware_image.dart';
import '../../widgets/vjod/provider_play.dart';
import '../../widgets/vjod/vjod_widgets.dart';

const _tmdbPoster = 'https://image.tmdb.org/t/p/w342';

class CatalogueScreen extends StatefulWidget {
  final bool isTv;

  /// The server's library behind « Toute ma bibliothèque » (null without one).
  final String? libraryRoute;

  const CatalogueScreen({super.key, required this.isTv, this.libraryRoute});

  @override
  State<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends State<CatalogueScreen> {
  final _items = <SeerrDiscoverItem>[];
  final _seen = <int>{};
  int _nextPage = 1;
  bool _loading = false;
  bool _failed = false;
  bool _end = false;
  int _filter = 0;

  static const _firstPages = 3;
  static const _morePages = 2;

  @override
  void initState() {
    super.initState();
    unawaited(_load(_firstPages));
  }

  Future<void> _load(int pages) async {
    if (_loading || _end) return;
    setState(() => _loading = true);
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) throw StateError('Seerr unavailable');
      final from = _nextPage;
      final results = await Future.wait([
        for (var p = from; p < from + pages; p++)
          widget.isTv ? repo.discoverTv(page: p) : repo.discoverMovies(page: p),
      ]);
      if (!mounted) return;
      var added = 0;
      for (final page in results) {
        for (final item in page.results) {
          if (item.adult || item.isBlacklisted || !_seen.add(item.id)) continue;
          _items.add(item);
          added++;
        }
      }
      setState(() {
        _nextPage = from + pages;
        _end = added == 0;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[Catalogue] Failed to load: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = _items.isEmpty;
        });
      }
    }
  }

  String get _mediaType => widget.isTv ? 'tv' : 'movie';

  CatalogueAvailability _availabilityOf(SeerrDiscoverItem item) => catalogueAvailability(
    seerrStatus: item.mediaInfo?.status,
    hasIptv: providerCopyNow(series: widget.isTv, tmdbId: '${item.id}') != null,
  );

  void _open(SeerrDiscoverItem item) {
    context.push(
      Destinations.seerrMedia(
        '${item.id}',
        mediaType: _mediaType,
        title: item.title ?? item.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: NavigationLayout(
        activeRoute: Destinations.catalogue,
        child: ProviderCatalogListener(builder: _buildBody),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = GetIt.instance<UserPreferences>();
    final isMobile = PlatformDetection.useMobileUi;
    final width = MediaQuery.sizeOf(context).width;
    final s = isMobile ? 0.8 : (width / 1280).clamp(0.6, 1.2);
    final navbarIsTop = prefs.get(UserPreferences.navbarPosition) == NavbarPosition.top;
    final navbarHeight = navbarIsTop
        ? (PlatformDetection.isTV ? 95.0 : (isMobile ? 60.0 : 80.0))
        : 0.0;
    final left = isMobile ? 16.0 : 64 * s;
    final top = MediaQuery.paddingOf(context).top + navbarHeight + 12;

    final onServer = vjodText(context, fr: 'Sur le serveur', en: 'On the server', ru: 'На сервере', zh: '服务器上');
    final iptv = vjodText(context, fr: 'À regarder (IPTV)', en: 'Watch now (IPTV)', ru: 'Смотреть (IPTV)', zh: '立即观看（IPTV）');
    final library = widget.libraryRoute;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(left, top, left, 16 * s),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20 * s,
        runSpacing: 10,
        children: [
          Text(
            (widget.isTv ? l10n.vjodTabSeries : l10n.vjodTabMovies).toUpperCase(),
            style: vjodDisplay(48 * s),
          ),
          VjodSegmented(
            scale: s,
            options: [l10n.all, onServer, iptv, l10n.vjodToRequest],
            selected: _filter,
            onSelect: (i) => setState(() => _filter = i),
          ),
          if (library != null)
            VjodFocusable(
              onTap: () => context.push(library),
              builder: (context, focused) => VjodButton(
                label: vjodText(
                  context,
                  fr: 'Toute ma bibliothèque',
                  en: 'My whole library',
                  ru: 'Вся моя библиотека',
                  zh: '我的全部片库',
                ),
                icon: Icons.video_library_outlined,
                compact: true,
                ringed: focused,
                scale: s,
                onTap: () => context.push(library),
              ),
            ),
          Text(
            vjodText(
              context,
              fr: 'Tout le catalogue : ce qu\'on a, ce qu\'on regarde tout de suite, ce qu\'on peut demander.',
              en: 'The whole catalogue: what we have, what plays right now, what you can ask for.',
              ru: 'Весь каталог: что у нас есть, что можно смотреть сразу и что можно запросить.',
              zh: '完整片库：已有的、可立即观看的、可以申请的。',
            ),
            style: TextStyle(color: vjodInk.withValues(alpha: 0.55), fontSize: 17 * s),
          ),
        ],
      ),
    );

    Widget content;
    if (_items.isEmpty) {
      content = _failed
          ? Center(child: Text(l10n.enRouteFailed))
          : const Center(child: CircularProgressIndicator());
    } else {
      final cardW = 165 * s;
      final tagged = [for (final item in _items) (item, _availabilityOf(item))];
      final shown = [for (final t in tagged) if (catalogueFilterKeeps(_filter, t.$2)) t];
      Widget grid(List<(SeerrDiscoverItem, CatalogueAvailability)> list, {bool first = false}) => Wrap(
        spacing: 15 * s,
        runSpacing: 18 * s,
        children: [
          for (final (i, (item, a)) in list.indexed)
            _CatalogueCard(
              item: item,
              availability: a,
              width: cardW,
              scale: s,
              autofocus: first && i == 0 && PlatformDetection.isTV,
              onTap: () => _open(item),
            ),
        ],
      );
      Widget section(String title) => Padding(
        padding: EdgeInsets.only(top: 24 * s, bottom: 10 * s),
        child: Text(title, style: TextStyle(color: vjodInk, fontSize: 22 * s, fontWeight: FontWeight.w700)),
      );
      // « Tout »: what the server has first, then the rest.
      final children = <Widget>[];
      if (_filter == 0) {
        final server = [for (final t in shown) if (t.$2 == CatalogueAvailability.server) t];
        final rest = [for (final t in shown) if (t.$2 != CatalogueAvailability.server) t];
        if (server.isNotEmpty) children..add(section(onServer))..add(grid(server, first: true));
        if (rest.isNotEmpty) {
          children
            ..add(section(vjodText(context, fr: 'À découvrir', en: 'To discover', ru: 'Открыть для себя', zh: '发现更多')))
            ..add(grid(rest, first: server.isEmpty));
        }
      } else if (shown.isEmpty) {
        children.add(Padding(
          padding: EdgeInsets.only(top: 24 * s),
          child: Text(
            vjodText(
              context,
              fr: 'Rien de ce genre parmi les titres chargés. Appuie sur « Voir plus ».',
              en: 'Nothing like that among the titles loaded. Press « See more ».',
              ru: 'Среди загруженных ничего такого нет. Нажми «Показать ещё».',
              zh: '已加载的作品中没有这类。点「查看更多」。',
            ),
            style: TextStyle(color: vjodInk.withValues(alpha: 0.6), fontSize: 16 * s),
          ),
        ));
      } else {
        children.add(grid(shown, first: true));
      }
      if (!_end) {
        children.add(Padding(
          padding: EdgeInsets.only(top: 24 * s),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _loading
                ? const CircularProgressIndicator()
                : VjodFocusable(
                    onTap: () => unawaited(_load(_morePages)),
                    builder: (context, focused) => VjodButton(
                      label: vjodText(context, fr: 'Voir plus', en: 'See more', ru: 'Показать ещё', zh: '查看更多'),
                      icon: Icons.expand_more_rounded,
                      compact: true,
                      ringed: focused,
                      scale: s,
                      onTap: () => unawaited(_load(_morePages)),
                    ),
                  ),
          ),
        ));
      }
      content = ListView(
        padding: EdgeInsets.fromLTRB(left, 0, left, 40),
        children: children,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [header, Expanded(child: content)],
    );
  }
}

class _CatalogueCard extends StatelessWidget {
  final SeerrDiscoverItem item;
  final CatalogueAvailability availability;
  final double width;
  final double scale;
  final bool autofocus;
  final VoidCallback onTap;

  const _CatalogueCard({
    required this.item,
    required this.availability,
    required this.width,
    required this.scale,
    required this.autofocus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = scale;
    final (label, color) = switch (availability) {
      CatalogueAvailability.server => (
        vjodText(context, fr: 'Sur le serveur', en: 'On the server', ru: 'На сервере', zh: '服务器上'),
        AppColorScheme.statusAvailable,
      ),
      CatalogueAvailability.iptv => ('IPTV', const Color(0xFF5BD18B)),
      CatalogueAvailability.requested => (l10n.seerrTagRequested, AppColorScheme.statusRequested),
      CatalogueAvailability.toRequest => (l10n.vjodToRequest, AppColorScheme.accent),
    };
    final poster = item.posterPath;
    return VjodFocusable(
      autofocus: autofocus,
      onTap: onTap,
      builder: (context, focused) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: width * 1.5,
              decoration: BoxDecoration(
                color: AppColorScheme.surface,
                borderRadius: BorderRadius.circular(4),
                boxShadow: vjodFocusRing(s, on: focused),
              ),
              clipBehavior: Clip.antiAlias,
              child: poster == null
                  ? const SizedBox.shrink()
                  : OfflineAwareImage(imageUrl: '$_tmdbPoster$poster', fit: BoxFit.cover),
            ),
            SizedBox(height: 6 * s),
            Row(
              children: [
                Container(
                  width: 7 * s,
                  height: 7 * s,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                SizedBox(width: 6 * s),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color == AppColorScheme.accent ? vjodInk : color,
                      fontSize: 15 * s,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              item.title ?? item.name ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: vjodInk.withValues(alpha: 0.7), fontSize: 14 * s),
            ),
          ],
        ),
      ),
    );
  }
}
