// VJOD's own live TV, fed by IPTV Checker's "Ma TV": categories on the left,
// the channels of the category in the middle with what's on, the channel
// under the cursor on the right. OK plays it; the player zaps inside the
// category. When Ma TV isn't set up or can't be reached, the Jellyfin guide
// stays one button away.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/vjod/ma_tv.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/navigation_layout.dart';
import 'ma_tv_guide.dart';
import 'ma_tv_player_screen.dart';
import 'ma_tv_widgets.dart';

/// Where the TV entries of the app land: Ma TV when the seedbox hands it out,
/// the Jellyfin guide ([fallback]) otherwise.
class MaTvEntryScreen extends StatefulWidget {
  final Widget Function() fallback;

  /// Opened from the "VJOD TV" icon: straight onto the last channel.
  final bool autoplay;

  /// Kids Mode: the Jeunesse channels only.
  final bool kids;

  const MaTvEntryScreen({super.key, required this.fallback, this.autoplay = false, this.kids = false});

  @override
  State<MaTvEntryScreen> createState() => _MaTvEntryScreenState();
}

enum _Entry { checking, maTv, fallback, denied }

class _MaTvEntryScreenState extends State<MaTvEntryScreen> {
  _Entry _entry = MaTvClient().isConfigured ? _Entry.maTv : _Entry.checking;

  @override
  void initState() {
    super.initState();
    unawaited(_decide());
  }

  Future<void> _decide() async {
    final configured = await ensureMaTvConfigured();
    if (!configured) {
      if (mounted) setState(() => _entry = _Entry.fallback);
      return;
    }
    final allowed = await MaTvAccess.allowed();
    if (!mounted) return;
    setState(() => _entry = allowed ? _Entry.maTv : _Entry.denied);
  }

  @override
  Widget build(BuildContext context) {
    switch (_entry) {
      case _Entry.checking:
        return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
      case _Entry.fallback:
        return widget.fallback();
      case _Entry.denied:
        return Scaffold(
          backgroundColor: Colors.black,
          body: NavigationLayout(
            activeRoute: Destinations.liveTvGuide,
            child: const Center(
              child: Text(
                "La TV en direct n'est pas ouverte pour ce profil.\nDemande à l'administrateur de Jellyfin de l'autoriser.",
                textAlign: TextAlign.center,
                style: TextStyle(color: MaTvColors.mute, fontSize: 17),
              ),
            ),
          ),
        );
      case _Entry.maTv:
        return MaTvBrowserScreen(autoplay: widget.autoplay, kids: widget.kids);
    }
  }
}

class MaTvBrowserScreen extends StatefulWidget {
  final bool autoplay;
  final bool kids;

  static const kidsCategory = MaTvCategory(id: 't:Jeunesse', label: 'Dessins animés et jeunesse', kind: 'theme', count: 0);

  const MaTvBrowserScreen({super.key, this.autoplay = false, this.kids = false});

  @override
  State<MaTvBrowserScreen> createState() => _MaTvBrowserScreenState();
}

class _MaTvBrowserScreenState extends State<MaTvBrowserScreen> {
  final _client = MaTvClient();
  final _focus = FocusNode(debugLabel: 'MaTvBrowser');
  final _catScroll = ScrollController();
  final _chanScroll = ScrollController();

  List<MaTvCategory> _cats = const [];
  List<MaTvChannel> _chans = const [];
  int _cat = 0;
  int _chan = 0;
  int _column = 1;
  bool _loading = true;
  bool _failed = false;
  bool _loadingChans = false;
  int _chanRequest = 0;
  DateTime _now = DateTime.now();
  Timer? _clock;
  Timer? _detailsTimer;
  String? _detailsFor;
  List<MaTvProgram> _details = const [];
  Set<String> _favorites = {};
  String? _toast;
  Timer? _toastTimer;

  static int _idx(int i, int len) => len == 0 ? 0 : i.clamp(0, len - 1);

  bool get _wide => MediaQuery.sizeOf(context).width >= 1000;
  bool get _narrow => MediaQuery.sizeOf(context).width < 700;

  @override
  void initState() {
    super.initState();
    _favorites = MaTvMemory.favorites.toSet();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    unawaited(MaTvDevice.caps());
    unawaited(_load());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _detailsTimer?.cancel();
    _toastTimer?.cancel();
    _focus.dispose();
    _catScroll.dispose();
    _chanScroll.dispose();
    super.dispose();
  }

  List<MaTvCategory> _localCats(List<MaTvCategory> server) {
    if (widget.kids) {
      final n = server.where((c) => c.id == 't:Jeunesse').firstOrNull?.count ?? 0;
      return [
        MaTvCategory(
          id: MaTvBrowserScreen.kidsCategory.id,
          label: MaTvBrowserScreen.kidsCategory.label,
          kind: 'theme',
          count: n,
        ),
      ];
    }
    final fav = MaTvMemory.favorites;
    final recent = MaTvMemory.recent;
    return [
      if (fav.isNotEmpty) MaTvCategory(id: 'fav', label: 'Favoris', kind: 'fav', count: fav.length),
      if (recent.isNotEmpty) MaTvCategory(id: 'recent', label: 'Récentes', kind: 'recent', count: recent.length),
      ...server,
    ];
  }

  Future<void> _load({bool fresh = false}) async {
    setState(() {
      _loading = _cats.isEmpty;
      _failed = false;
    });
    final server = await _client.categories(fresh: fresh);
    if (!mounted) return;
    if (server == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    final cats = _localCats(server);
    var start = 0;
    final last = widget.kids ? '' : MaTvMemory.lastCategory;
    final i = cats.indexWhere((c) => c.id == last);
    if (i >= 0) {
      start = i;
    } else {
      final fr = cats.indexWhere((c) => c.id == 'c:FR');
      final fav = cats.indexWhere((c) => c.id == 'fav');
      start = fav >= 0 ? fav : (fr >= 0 ? fr : 0);
    }
    setState(() {
      _cats = cats;
      _cat = start;
      _loading = false;
    });
    await _openCategory(start, fresh: fresh);
    if (widget.autoplay && mounted) _autoplay();
  }

  void _autoplay() {
    final last = MaTvMemory.lastChannel;
    final i = _chans.indexWhere((c) => c.id == last);
    if (i >= 0) {
      _play(i);
    } else if (_chans.isNotEmpty) {
      _play(0);
    }
  }

  Future<List<MaTvChannel>?> _channelsOf(MaTvCategory c, {bool fresh = false}) async {
    if (c.kind == 'fav' || c.kind == 'recent') {
      final all = await _client.allChannels();
      if (all == null) return null;
      final byId = {for (final ch in all) ch.id: ch};
      final ids = c.kind == 'fav' ? MaTvMemory.favorites : MaTvMemory.recent;
      return [for (final id in ids) if (byId[id] case final MaTvChannel ch) ch];
    }
    return _client.channels(c.id, fresh: fresh);
  }

  Future<void> _openCategory(int index, {bool fresh = false}) async {
    if (index < 0 || index >= _cats.length) return;
    final request = ++_chanRequest;
    setState(() {
      _cat = index;
      _loadingChans = true;
    });
    final chans = await _channelsOf(_cats[index], fresh: fresh);
    if (!mounted || request != _chanRequest) return;
    final last = MaTvMemory.lastChannel;
    final at = (chans ?? const <MaTvChannel>[]).indexWhere((c) => c.id == last);
    setState(() {
      _chans = chans ?? const [];
      _chan = at >= 0 ? at : 0;
      _loadingChans = false;
    });
    _scrollTo(_chanScroll, _chan, MaTvChannelRow.height + 6);
    _scheduleDetails();
  }

  void _scheduleDetails() {
    _detailsTimer?.cancel();
    if (!_wide || _chans.isEmpty) return;
    final ch = _chans[_chan.clamp(0, _chans.length - 1)];
    if (_detailsFor == ch.id) return;
    _detailsTimer = Timer(const Duration(milliseconds: 350), () async {
      final now = DateTime.now();
      final progs = await _client.programs([ch.id], now.subtract(const Duration(hours: 1)), now.add(const Duration(hours: 8)));
      if (!mounted) return;
      setState(() {
        _detailsFor = ch.id;
        _details = progs?[ch.id] ?? const [];
      });
    });
  }

  void _scrollTo(ScrollController c, int index, double extent) {
    if (!c.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (c.hasClients) _scrollTo(c, index, extent);
      });
      return;
    }
    final view = c.position.viewportDimension;
    final top = index * extent;
    var target = c.offset;
    if (top < c.offset + extent) target = top - extent;
    if (top + extent > c.offset + view - extent) target = top + 2 * extent - view;
    c.jumpTo(target.clamp(0.0, c.position.maxScrollExtent));
  }

  void _say(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _toggleFavorite(int index) async {
    if (index < 0 || index >= _chans.length) return;
    final ch = _chans[index];
    final on = await MaTvMemory.toggleFavorite(ch.id);
    if (!mounted) return;
    setState(() {
      _favorites = MaTvMemory.favorites.toSet();
      final server = _cats.where((c) => c.kind != 'fav' && c.kind != 'recent').toList();
      final current = _cats[_cat].id;
      _cats = _localCats(server);
      _cat = _idx(_cats.indexWhere((c) => c.id == current), _cats.length);
    });
    _say(on ? '${ch.name} ajoutée aux favoris' : '${ch.name} retirée des favoris');
  }

  Future<void> _openGrid() async {
    if (_chans.isEmpty) return;
    final cat = _cats.isEmpty ? null : _cats[_cat];
    final pick = await Navigator.of(context, rootNavigator: true).push<MaTvGuidePick>(
      MaterialPageRoute(
        builder: (_) => MaTvGuideScreen(channels: _chans, startIndex: _chan, categoryLabel: cat?.label ?? ''),
      ),
    );
    if (!mounted) return;
    _focus.requestFocus();
    if (pick != null) await _play(pick.index, replay: pick.replay);
  }

  Future<void> _play(int index, {MaTvProgram? replay}) async {
    if (index < 0 || index >= _chans.length) return;
    final cat = _cats.isEmpty ? null : _cats[_cat];
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => MaTvPlayerScreen(
          channels: _chans,
          startIndex: index,
          categoryId: cat?.id ?? 'all',
          categoryLabel: cat?.label ?? '',
          categories: _cats,
          startReplay: replay,
          kids: widget.kids,
        ),
      ),
    );
    if (!mounted) return;
    // Back from the player: land on the channel watched last.
    final last = MaTvMemory.lastChannel;
    final server = _cats.where((c) => c.kind != 'fav' && c.kind != 'recent').toList();
    final current = _cats.isEmpty ? '' : _cats[_cat].id;
    setState(() {
      _favorites = MaTvMemory.favorites.toSet();
      _cats = _localCats(server);
      final ci = _cats.indexWhere((c) => c.id == MaTvMemory.lastCategory);
      _cat = ci >= 0 ? ci : _idx(_cats.indexWhere((c) => c.id == current), _cats.length);
      _now = DateTime.now();
    });
    await _openCategory(_cat);
    final i = _chans.indexWhere((c) => c.id == last);
    if (i >= 0 && mounted) {
      setState(() => _chan = i);
      _scrollTo(_chanScroll, i, MaTvChannelRow.height + 6);
    }
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!event.isActionable || _cats.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key.isBackKey && _column == 1 && !_narrow) {
      setState(() => _column = 0);
      return KeyEventResult.handled;
    }
    if (key.isUpKey || key.isDownKey) {
      final d = key.isDownKey ? 1 : -1;
      if (_column == 0) {
        final next = (_cat + d).clamp(0, _cats.length - 1);
        if (next != _cat) {
          unawaited(_openCategory(next));
          _scrollTo(_catScroll, next, MaTvCategoryList.rowHeight);
        }
      } else if (_chans.isNotEmpty) {
        setState(() => _chan = (_chan + d).clamp(0, _chans.length - 1));
        _scrollTo(_chanScroll, _chan, MaTvChannelRow.height + 6);
        _scheduleDetails();
      }
      return KeyEventResult.handled;
    }
    final page = key.pageDirection;
    if (page != 0 && _column == 1 && _chans.isNotEmpty) {
      setState(() => _chan = (_chan + page * 8).clamp(0, _chans.length - 1));
      _scrollTo(_chanScroll, _chan, MaTvChannelRow.height + 6);
      _scheduleDetails();
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      if (_column == 0) {
        setState(() => _column = 1);
      } else {
        // From the channels, RIGHT goes into the hours: the programme grid.
        unawaited(_openGrid());
      }
      return KeyEventResult.handled;
    }
    if (key.isLeftKey) {
      if (_column == 1) {
        setState(() => _column = 0);
        return KeyEventResult.handled;
      }
      // From the categories, LEFT goes on to the app's side menu.
      return KeyEventResult.ignored;
    }
    if (key.isContextMenuKey && _column == 1) {
      unawaited(_toggleFavorite(_chan));
      return KeyEventResult.handled;
    }
    if (key.isSelectKey && event is KeyDownEvent) {
      if (_column == 0) {
        setState(() => _column = 1);
      } else {
        unawaited(_play(_chan));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _column == 0 || _narrow,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _column == 1) setState(() => _column = 0);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0B0D),
        body: NavigationLayout(
          activeRoute: Destinations.liveTvGuide,
          child: Focus(
            focusNode: _focus,
            autofocus: true,
            onKeyEvent: _onKey,
            child: SafeArea(child: _body()),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_failed) return _unreachable();
    return MaTvBrowserView(
      categories: _cats,
      category: _cat,
      channels: _chans,
      channel: _chan,
      column: _column,
      now: _now,
      favorites: _favorites,
      details: _detailsFor != null && _chans.isNotEmpty && _chans[_chan.clamp(0, _chans.length - 1)].id == _detailsFor
          ? _details
          : const [],
      showDetails: _wide,
      narrow: _narrow,
      loadingChannels: _loadingChans,
      toast: _toast,
      catScroll: _catScroll,
      chanScroll: _chanScroll,
      onCategory: (i) {
        setState(() => _column = 0);
        unawaited(_openCategory(i));
      },
      onChannel: (i) {
        if (_narrow || (i == _chan && _column == 1)) {
          unawaited(_play(i));
        } else {
          setState(() {
            _chan = i;
            _column = 1;
          });
          _scheduleDetails();
        }
      },
      onChannelLongPress: (i) => unawaited(_toggleFavorite(i)),
      onJellyfinGuide: widget.kids ? null : () => context.push('${Destinations.liveTvGuide}?jellyfin=1'),
      onGrid: () => unawaited(_openGrid()),
      title: widget.kids ? 'TV des enfants' : 'Ma TV',
    );
  }

  Widget _unreachable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ma TV ne répond pas',
              style: TextStyle(color: MaTvColors.ink, fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              "IPTV Checker, sur la seedbox, n'a pas répondu. Il redémarre peut-être, réessaie dans un instant.",
              textAlign: TextAlign.center,
              style: TextStyle(color: MaTvColors.mute, fontSize: 15),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(autofocus: true, onPressed: () => _load(fresh: true), child: const Text('Réessayer')),
                OutlinedButton(
                  onPressed: () => context.push('${Destinations.liveTvGuide}?jellyfin=1'),
                  child: const Text('Guide Jellyfin'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The browser's layout, drawn from plain data (the captures use it as is).
class MaTvBrowserView extends StatelessWidget {
  final List<MaTvCategory> categories;
  final int category;
  final List<MaTvChannel> channels;
  final int channel;
  final int column;
  final DateTime now;
  final Set<String> favorites;
  final List<MaTvProgram> details;
  final bool showDetails;
  final bool narrow;
  final bool loadingChannels;
  final String? toast;
  final ScrollController? catScroll;
  final ScrollController? chanScroll;
  final ValueChanged<int>? onCategory;
  final ValueChanged<int>? onChannel;
  final ValueChanged<int>? onChannelLongPress;
  final VoidCallback? onJellyfinGuide;
  final VoidCallback? onGrid;
  final String title;

  const MaTvBrowserView({
    super.key,
    required this.categories,
    required this.category,
    required this.channels,
    required this.channel,
    required this.column,
    required this.now,
    this.favorites = const {},
    this.details = const [],
    this.showDetails = true,
    this.narrow = false,
    this.loadingChannels = false,
    this.toast,
    this.catScroll,
    this.chanScroll,
    this.onCategory,
    this.onChannel,
    this.onChannelLongPress,
    this.onJellyfinGuide,
    this.onGrid,
    this.title = 'Ma TV',
  });

  @override
  Widget build(BuildContext context) {
    final cat = categories.isEmpty ? null : categories[category.clamp(0, categories.length - 1)];
    final selected = channels.isEmpty ? null : channels[channel.clamp(0, channels.length - 1)];
    final header = Padding(
      padding: EdgeInsets.fromLTRB(narrow ? 16 : 28, 18, narrow ? 16 : 28, 12),
      child: Row(
        children: [
          Text(title, style: const TextStyle(color: MaTvColors.ink, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(width: 14),
          if (cat != null)
            Flexible(
              child: Text(
                '${cat.label} · ${channels.length} chaînes',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: MaTvColors.mute, fontSize: 15),
              ),
            ),
          const Spacer(),
          if (!narrow && !PlatformDetection.isWeb)
            const Text('OK regarder · DROITE grille · MENU favori', style: TextStyle(color: MaTvColors.faint, fontSize: 12.5)),
          const SizedBox(width: 14),
          if (onGrid != null)
            TextButton.icon(
              onPressed: onGrid,
              icon: const Icon(Icons.grid_view_rounded, size: 18, color: MaTvColors.mute),
              label: const Text('Grille', style: TextStyle(color: MaTvColors.mute)),
            ),
          if (onJellyfinGuide != null)
            TextButton(
              onPressed: onJellyfinGuide,
              child: const Text('Guide Jellyfin', style: TextStyle(color: MaTvColors.mute)),
            ),
          const SizedBox(width: 8),
          Text(maTvTime(now), style: const TextStyle(color: MaTvColors.ink, fontSize: 20, fontWeight: FontWeight.w700)),
        ],
      ),
    );
    final list = loadingChannels && channels.isEmpty
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : MaTvChannelList(
            channels: channels,
            selected: channel,
            focused: column == 1,
            now: now,
            favorites: favorites,
            controller: chanScroll,
            onTap: onChannel,
            onLongPress: onChannelLongPress,
            emptyText: cat?.kind == 'fav'
                ? 'Pas encore de favori : MENU (ou appui long) sur une chaîne pour l’ajouter.'
                : 'Aucune chaîne ici.',
          );
    Widget body;
    if (narrow) {
      body = Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final on = i == category;
                return GestureDetector(
                  onTap: onCategory == null ? null : () => onCategory!(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? MaTvColors.ink : MaTvColors.row,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(
                      categories[i].label,
                      style: TextStyle(color: on ? Colors.black : MaTvColors.ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: list)),
        ],
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 230,
              child: MaTvCategoryList(
                categories: categories,
                selected: category,
                focused: column == 0,
                controller: catScroll,
                onTap: onCategory,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(child: list),
            if (showDetails) ...[
              const SizedBox(width: 18),
              SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: MaTvDetailsPane(channel: selected, programs: details, now: now),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return Stack(
      children: [
        Column(children: [header, Expanded(child: body)]),
        if (toast != null)
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(color: MaTvColors.panel, borderRadius: BorderRadius.circular(22)),
                child: Text(toast!, style: const TextStyle(color: MaTvColors.ink, fontSize: 15)),
              ),
            ),
          ),
      ],
    );
  }
}
