// Films and Séries, as the whole catalogue: VJOD's tabs used to open the
// server's libraries only, and people took them for everything there is.
// Now they show what is popular, each poster saying how to watch it (on the
// server, at once from the IPTV provider, or to ask for), with a filter on
// top. The server's full library, with its sorting, stays one press away.
import 'dart:async';

import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/seerr/seerr_api_models.dart';
import '../../../data/services/vjod/catalogue_availability.dart';
import '../../../data/services/vjod/simple_mode.dart';
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

  // The magnifier: any title of this kind, not only the popular ones.
  bool _searching = false;
  final _searchCtl = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchTvKey = GlobalKey<CustomTVTextFieldState>();
  Timer? _searchDebounce;
  String? _searchedFor;
  int _searchRun = 0;
  bool _searchLoading = false;
  bool _searchFailed = false;
  final _searchResults = <SeerrDiscoverItem>[];
  // « Avec Tom Hardy »: what the people the search names played in or made.
  final _peopleResults = <(String, List<SeerrDiscoverItem>)>[];

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(_onSearchText);
    unawaited(_load(_firstPages));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openSearch() {
    if (_searching) {
      _closeSearch();
      return;
    }
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      if (PlatformDetection.isTV) _searchTvKey.currentState?.openKeyboard();
    });
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchRun++;
    _searchCtl.clear();
    setState(() {
      _searching = false;
      _searchedFor = null;
      _searchLoading = false;
      _searchFailed = false;
      _searchResults.clear();
      _peopleResults.clear();
    });
  }

  void _onSearchText() {
    _searchDebounce?.cancel();
    final q = catalogueSearchQuery(_searchCtl.text);
    if (q == null) {
      if (_searchedFor != null) {
        _searchRun++;
        setState(() {
          _searchedFor = null;
          _searchLoading = false;
          _searchFailed = false;
          _searchResults.clear();
          _peopleResults.clear();
        });
      }
      return;
    }
    if (q == _searchedFor) return;
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => unawaited(_search(q)));
  }

  Future<void> _search(String q) async {
    final run = ++_searchRun;
    setState(() {
      _searchedFor = q;
      _searchLoading = true;
      _searchFailed = false;
    });
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      if (!repo.isAvailable) throw StateError('Seerr unavailable');
      // Two pages: people and the other kind take part of each.
      final pages = await Future.wait([
        repo.search(q, mediaType: _mediaType, offset: 0),
        repo.search(q, mediaType: _mediaType, offset: 20),
      ]);
      if (!mounted || run != _searchRun) return;
      bool keep(SeerrDiscoverItem item) =>
          !item.adult &&
          !item.isBlacklisted &&
          catalogueSearchKeeps(series: widget.isTv, mediaType: item.mediaType);
      // An actor or a director: their films (or series), the best known first.
      final people = catalogueSearchPeople([for (final page in pages) ...page.results]);
      final credits = await Future.wait([
        for (final person in people)
          repo.getPersonCombinedCredits(person.id).then<SeerrPersonCombinedCredits?>((c) => c).catchError((_) => null),
      ]);
      if (!mounted || run != _searchRun) return;
      final byPerson = <(String, List<SeerrDiscoverItem>)>[];
      for (final (i, person) in people.indexed) {
        final c = credits[i];
        if (c == null) continue;
        final ids = <int>{};
        final works = [
          for (final w in [...c.cast, ...c.crew])
            if (keep(w) && ids.add(w.id)) w,
        ]..sort((a, b) => (b.popularity ?? 0).compareTo(a.popularity ?? 0));
        if (works.isNotEmpty) byPerson.add((person.name ?? '', works.take(30).toList()));
      }
      final seen = <int>{};
      final found = <SeerrDiscoverItem>[
        for (final page in pages)
          for (final item in page.results)
            if (keep(item) && seen.add(item.id))
              item,
      ];
      setState(() {
        _searchResults
          ..clear()
          ..addAll(found);
        _peopleResults
          ..clear()
          ..addAll(byPerson);
        _searchLoading = false;
      });
    } catch (e) {
      debugPrint('[Catalogue] Search failed: $e');
      if (mounted && run == _searchRun) {
        setState(() {
          _searchLoading = false;
          _searchFailed = true;
        });
      }
    }
  }

  void _onSearchSubmitted(String text) {
    final q = catalogueSearchQuery(text);
    if (q == null || q == _searchedFor) return;
    _searchDebounce?.cancel();
    unawaited(_search(q));
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (!PlatformDetection.isTV || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select) {
      _searchTvKey.currentState?.openKeyboard();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _searchField(double s) {
    final hint = widget.isTv
        ? vjodText(context,
            fr: 'Une série, un acteur, un réalisateur…',
            en: 'A series, an actor, a director…',
            ru: 'Сериал, актёр, режиссёр…',
            zh: '剧集、演员、导演…')
        : vjodText(context,
            fr: 'Un film, un acteur, un réalisateur…',
            en: 'A movie, an actor, a director…',
            ru: 'Фильм, актёр, режиссёр…',
            zh: '电影、演员、导演…');
    // Big letters: what is typed must read from the sofa.
    final big = (PlatformDetection.isTV ? 28.0 : 22.0) * s.clamp(0.85, 1.2);
    final style = TextStyle(color: vjodInk, fontSize: big, fontWeight: FontWeight.w600);
    final hintStyle = TextStyle(color: vjodInk.withValues(alpha: 0.55), fontSize: big * 0.75);
    final icon = Icon(Icons.search_rounded, color: vjodInk, size: big);
    final height = big * 2.4;
    return SizedBox(
      width: (480 * s).clamp(260.0, 600.0),
      height: height,
      child: PlatformDetection.isTV
          ? Focus(
              focusNode: _searchFocus,
              onKeyEvent: _onSearchKey,
              child: ListenableBuilder(
                listenable: _searchFocus,
                builder: (context, _) => CustomTVTextField(
                  key: _searchTvKey,
                  controller: _searchCtl,
                  isFocused: _searchFocus.hasFocus,
                  inputPurpose: InputPurpose.search,
                  preferSystemIme: GetIt.instance<UserPreferences>().get(UserPreferences.preferSystemImeKeyboard),
                  hint: hint,
                  textStyle: style,
                  hintStyle: hintStyle,
                  prefixIcon: icon,
                  filled: true,
                  fillColor: AppColorScheme.surfaceVariant,
                  borderRadius: height / 2,
                  focusedBorderColor: vjodInk,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  popParentOnKeyboardClose: false,
                  onFieldSubmitted: _onSearchSubmitted,
                ),
              ),
            )
          : TextField(
              controller: _searchCtl,
              focusNode: _searchFocus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: _onSearchSubmitted,
              style: style,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: hintStyle,
                prefixIcon: icon,
                filled: true,
                fillColor: AppColorScheme.surfaceVariant,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(height / 2),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
    );
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

  /// Simple mode: « Regarder » on an IPTV film plays it at once; anything
  /// else opens the title's page, where the one big button waits.
  void _tap(SeerrDiscoverItem item, CatalogueAvailability a) {
    if (vjodSimpleMode() &&
        a == CatalogueAvailability.iptv &&
        playProviderCopy(context, series: widget.isTv, tmdbId: '${item.id}')) {
      return;
    }
    _open(item);
  }

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

  Widget _buildSearchResults(String query, double s, double left) {
    Widget note(String text) => Padding(
      padding: EdgeInsets.only(top: 24 * s),
      child: Text(text, style: TextStyle(color: vjodInk.withValues(alpha: 0.6), fontSize: 16 * s)),
    );
    final children = <Widget>[];
    if (_searchLoading && _searchResults.isEmpty) {
      children.add(Padding(
        padding: EdgeInsets.only(top: 24 * s),
        child: const Align(alignment: Alignment.centerLeft, child: CircularProgressIndicator()),
      ));
    } else if (_searchFailed) {
      children.add(note(vjodText(
        context,
        fr: 'La recherche n\'a pas marché. Réessaie dans un instant.',
        en: 'The search didn\'t work. Try again in a moment.',
        ru: 'Поиск не сработал. Попробуй чуть позже.',
        zh: '搜索失败，请稍后再试。',
      )));
    } else {
      List<(SeerrDiscoverItem, CatalogueAvailability)> tag(List<SeerrDiscoverItem> list) => [
        for (final item in list)
          if (catalogueFilterKeeps(_filter, _availabilityOf(item))) (item, _availabilityOf(item)),
      ];
      Widget grid(List<(SeerrDiscoverItem, CatalogueAvailability)> list) => Wrap(
        spacing: 15 * s,
        runSpacing: 18 * s,
        children: [
          for (final (item, a) in list)
            _CatalogueCard(
              item: item,
              availability: a,
              width: 165 * s,
              scale: s,
              autofocus: false,
              onTap: () => _tap(item, a),
            ),
        ],
      );
      Widget section(String title) => Padding(
        padding: EdgeInsets.only(top: 20 * s, bottom: 10 * s),
        child: Text(title, style: TextStyle(color: vjodInk, fontSize: 22 * s, fontWeight: FontWeight.w700)),
      );
      final tagged = tag(_searchResults);
      final withPeople = [
        for (final (name, works) in _peopleResults)
          if (tag(works).isNotEmpty) (name, tag(works)),
      ];
      for (final (name, works) in withPeople) {
        children
          ..add(section(vjodText(context, fr: 'Avec $name', en: 'With $name', ru: 'С участием: $name', zh: '$name 参与')))
          ..add(grid(works));
      }
      if (withPeople.isNotEmpty && tagged.isNotEmpty) {
        children.add(section(vjodText(context, fr: 'Titres', en: 'Titles', ru: 'Названия', zh: '作品')));
      }
      if (tagged.isEmpty && withPeople.isNotEmpty) {
        // The people's works already answer the search.
      } else if (tagged.isEmpty) {
        children.add(note(vjodText(
          context,
          fr: 'Rien trouvé pour « $query ».',
          en: 'Nothing found for « $query ».',
          ru: 'Ничего не найдено по «$query».',
          zh: '没有找到「$query」。',
        )));
      } else {
        children.add(grid(tagged));
      }
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(left, 0, left, 40),
      children: children,
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
    // Simple mode: no filter, posters say Regarder or Demander.
    final simple = vjodSimpleMode();

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
          VjodRoundButton(
            size: 48 * s.clamp(0.8, 1.2),
            scale: s,
            background: _searching ? vjodInk.withValues(alpha: 0.18) : Colors.white,
            semanticLabel: _searching
                ? vjodText(context, fr: 'Fermer la recherche', en: 'Close search', ru: 'Закрыть поиск', zh: '关闭搜索')
                : vjodText(context, fr: 'Rechercher', en: 'Search', ru: 'Поиск', zh: '搜索'),
            onTap: _openSearch,
            child: Icon(
              _searching ? Icons.close_rounded : Icons.search_rounded,
              color: _searching ? vjodInk : const Color(0xFF141414),
              size: 26 * s.clamp(0.8, 1.2),
            ),
          ),
          if (_searching) _searchField(s),
          if (!simple) VjodSegmented(
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
          if (!_searching && !simple) Text(
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
    final searched = _searchedFor;
    if (_searching && searched != null) {
      content = _buildSearchResults(searched, s, left);
    } else if (_items.isEmpty) {
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
              onTap: () => _tap(item, a),
            ),
        ],
      );
      Widget section(String title) => Padding(
        padding: EdgeInsets.only(top: 24 * s, bottom: 10 * s),
        child: Text(title, style: TextStyle(color: vjodInk, fontSize: 22 * s, fontWeight: FontWeight.w700)),
      );
      // « Tout »: what the server has first, then the rest.
      final children = <Widget>[];
      if (simple) {
        final now = [for (final t in shown) if (simpleActionFor(t.$2) == SimpleAction.watch) t];
        final later = [for (final t in shown) if (simpleActionFor(t.$2) != SimpleAction.watch) t];
        if (now.isNotEmpty) {
          children
            ..add(section(vjodText(context, fr: 'À regarder tout de suite', en: 'Watch right now', ru: 'Смотреть сейчас', zh: '立即观看')))
            ..add(grid(now, first: true));
        }
        if (later.isNotEmpty) {
          children
            ..add(section(l10n.vjodToRequest))
            ..add(grid(later, first: now.isEmpty));
        }
      } else if (_filter == 0) {
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
            if (vjodSimpleMode())
              _SimpleActionLabel(action: simpleActionFor(availability), scale: s)
            else
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

/// Simple mode, under each poster: what pressing it does, and nothing else.
class _SimpleActionLabel extends StatelessWidget {
  final SimpleAction action;
  final double scale;

  const _SimpleActionLabel({required this.action, required this.scale});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final (label, icon, filled) = switch (action) {
      SimpleAction.watch => (
        vjodText(context, fr: 'Regarder', en: 'Watch', ru: 'Смотреть', zh: '观看'),
        Icons.play_arrow_rounded,
        true,
      ),
      SimpleAction.request => (
        vjodText(context, fr: 'Demander', en: 'Request', ru: 'Запросить', zh: '申请'),
        Icons.add_rounded,
        false,
      ),
      SimpleAction.requested => (
        vjodText(context, fr: 'Demandé', en: 'Requested', ru: 'Запрошено', zh: '已申请'),
        Icons.check_rounded,
        false,
      ),
    };
    final ink = filled ? const Color(0xFF141414) : vjodInk;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 6 * s),
      decoration: BoxDecoration(
        color: filled
            ? Colors.white
            : vjodInk.withValues(alpha: action == SimpleAction.requested ? 0.08 : 0.16),
        borderRadius: BorderRadius.circular(5 * s),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18 * s, color: ink.withValues(alpha: action == SimpleAction.requested ? 0.6 : 1)),
          SizedBox(width: 4 * s),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink.withValues(alpha: action == SimpleAction.requested ? 0.6 : 1),
                fontSize: 15 * s,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
