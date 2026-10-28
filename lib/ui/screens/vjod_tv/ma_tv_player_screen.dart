// The live player of Ma TV, like a TV box: DOWN / UP zap inside the category
// (CH+ / CH- too), LEFT opens the channel list over the picture, RIGHT the
// sources, OK the mini-guide (with "watch from the start" when the provider
// keeps the replay), MENU adds the channel to the favourites, digits jump to
// a number. The relay on the seedbox does the rest: best source first, the
// next one if it drops, one connection shared by everyone on the channel.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/services/vjod/ma_tv.dart';
import '../../../data/services/vjod/tv_sources.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/platform_detection.dart';
import '../../../util/system_ui.dart';
import '../../screensaver/screensaver_controller.dart';
import '../../widgets/live_tv/tv_sources_panel.dart';
import 'ma_tv_widgets.dart';

enum _Overlay { none, guide, list, sources, replay }

class MaTvPlayerScreen extends StatefulWidget {
  final List<MaTvChannel> channels;
  final int startIndex;
  final String categoryId;
  final String categoryLabel;
  final List<MaTvCategory> categories;

  const MaTvPlayerScreen({
    super.key,
    required this.channels,
    required this.startIndex,
    required this.categoryId,
    required this.categoryLabel,
    this.categories = const [],
  });

  @override
  State<MaTvPlayerScreen> createState() => _MaTvPlayerScreenState();
}

class _MaTvPlayerScreenState extends State<MaTvPlayerScreen> with ImmersiveSystemUi {
  static const _zapDelay = Duration(milliseconds: 420);
  static const _bannerTime = Duration(seconds: 5);
  static const _noPictureRetry = Duration(seconds: 14);
  static const _noPictureGiveUp = Duration(seconds: 30);

  final _client = MaTvClient();
  late final TvSourcesClient _sources = _client.sourcesClient();
  final _focus = FocusNode(debugLabel: 'MaTvPlayer');
  final _listCatScroll = ScrollController();
  final _listChanScroll = ScrollController();
  final _replayScroll = ScrollController();

  late final Player _player;
  late final VideoController _video;
  final List<StreamSubscription<Object?>> _subs = [];

  late List<MaTvChannel> _list;
  late int _index;
  late String _catId;
  late String _catLabel;

  DateTime _now = DateTime.now();
  Timer? _clock;
  Timer? _zapTimer;
  Timer? _bannerTimer;
  Timer? _watchdog;
  Timer? _summaryTimer;
  Timer? _numberTimer;
  Timer? _refreshTimer;
  bool _banner = true;
  String? _status;
  String? _sourceLine;
  int _tuneSeq = 0;
  DateTime? _openedAt;
  bool _picture = false;
  bool _retried = false;
  String? _playingId;
  String _number = '';
  Set<String> _favorites = {};

  _Overlay _overlay = _Overlay.none;
  List<MaTvProgram> _guidePrograms = const [];
  int _guideAction = 0;

  // Channel list opened with LEFT.
  int _listColumn = 1;
  int _listCat = 0;
  List<MaTvChannel> _listChans = const [];
  int _listChan = 0;
  String _listCatId = '';

  // Replay: the past programmes of the channel, and the one playing.
  List<MaTvProgram> _replayPrograms = const [];
  int _replayIndex = 0;
  MaTvProgram? _replaying;

  MaTvChannel get _channel => _list[_index.clamp(0, _list.length - 1)];
  bool get _touch => !PlatformDetection.isTV;

  @override
  void initState() {
    super.initState();
    _list = List.of(widget.channels);
    _index = widget.startIndex.clamp(0, _list.isEmpty ? 0 : _list.length - 1);
    _catId = widget.categoryId;
    _catLabel = widget.categoryLabel;
    _favorites = MaTvMemory.favorites.toSet();
    setImmersive(true);
    _screensaver(true);
    _player = Player(configuration: const PlayerConfiguration(libass: false));
    _video = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        hwdec: PlatformDetection.isAndroid ? 'auto-copy' : (PlatformDetection.isLinux ? 'auto-safe' : null),
      ),
    );
    unawaited(_tuneLiveDefaults());
    _subs.add(_player.stream.width.listen((w) {
      if ((w ?? 0) > 0 && !_picture) {
        _picture = true;
        if (mounted) setState(() => _status = null);
      }
    }));
    _subs.add(_player.stream.buffering.listen((b) {
      if (!mounted || !_picture) return;
      setState(() => _status = b ? 'Mise en mémoire…' : null);
    }));
    _subs.add(_player.stream.error.listen((e) {
      if (!mounted || _picture) return;
      setState(() => _status = 'Le flux ne démarre pas, nouvel essai…');
    }));
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) => _refreshList());
    if (_list.isNotEmpty) _tune(immediate: true);
  }

  Future<void> _tuneLiveDefaults() async {
    final p = _player.platform;
    if (p is! NativePlayer) return;
    // A live stream from the relay: open fast (less probing), reconnect if
    // the link to the seedbox drops, keep the buffer modest on TV boxes.
    for (final kv in const [
      ('network-timeout', '15'),
      ('demuxer-lavf-analyzeduration', '1'),
      ('cache', 'yes'),
      ('demuxer-readahead-secs', '8'),
      ('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=4'),
      ('sub-create-cc-track', 'yes'),
    ]) {
      try {
        // NativePlayer's web stub has no setProperty: go through dynamic, as
        // the media_kit backend does.
        final dynamic native = p;
        await Future<void>.value(native.setProperty(kv.$1, kv.$2));
      } catch (_) {}
    }
  }

  void _screensaver(bool on) {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<ScreensaverController>()) getIt<ScreensaverController>().setPlaybackActive(on);
  }

  @override
  void dispose() {
    _screensaver(false);
    for (final t in [_clock, _zapTimer, _bannerTimer, _watchdog, _summaryTimer, _numberTimer, _refreshTimer]) {
      t?.cancel();
    }
    for (final s in _subs) {
      s.cancel();
    }
    unawaited(_player.dispose());
    _focus.dispose();
    _listCatScroll.dispose();
    _listChanScroll.dispose();
    _replayScroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- tuning
  void _showBanner({Duration? time}) {
    _bannerTimer?.cancel();
    setState(() => _banner = true);
    _bannerTimer = Timer(time ?? _bannerTime, () {
      if (mounted && _overlay == _Overlay.none && _number.isEmpty) setState(() => _banner = false);
    });
  }

  void _tune({bool immediate = false}) {
    if (_list.isEmpty) return;
    _replaying = null;
    _zapTimer?.cancel();
    setState(() {
      _status = 'Ouverture…';
      _sourceLine = null;
      _now = DateTime.now();
    });
    _showBanner();
    final ch = _channel;
    // Zapping several channels in a row only opens the one stopped on.
    _zapTimer = Timer(immediate ? Duration.zero : _zapDelay, () => _open(ch, _client.liveUri(ch)));
  }

  Future<void> _open(MaTvChannel ch, Uri? uri, {bool retry = false}) async {
    if (uri == null) {
      setState(() => _status = 'Ma TV n’est pas configurée');
      return;
    }
    final seq = ++_tuneSeq;
    _picture = false;
    _retried = retry;
    _openedAt = DateTime.now();
    _playingId = ch.id;
    try {
      await _player.open(Media(uri.toString()), play: true);
    } catch (_) {}
    if (_replaying == null) unawaited(MaTvMemory.watched(ch.id, _catId));
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _checkPicture(seq, ch, uri));
    _summaryTimer?.cancel();
    if (_replaying == null) {
      _summaryTimer = Timer(const Duration(milliseconds: 2500), () => _fetchSummary(seq, ch));
    }
  }

  void _checkPicture(int seq, MaTvChannel ch, Uri uri) {
    if (seq != _tuneSeq || !mounted) {
      return;
    }
    if (_picture) {
      _watchdog?.cancel();
      return;
    }
    final waited = DateTime.now().difference(_openedAt ?? DateTime.now());
    if (!_retried && waited > _noPictureRetry) {
      setState(() => _status = 'Pas d’image, nouvel essai…');
      unawaited(_open(ch, uri, retry: true));
    } else if (_retried && waited > _noPictureGiveUp - _noPictureRetry) {
      _watchdog?.cancel();
      setState(() => _status = 'Aucune source ne répond · ▶ pour en choisir une');
      _showBanner(time: const Duration(seconds: 12));
    }
  }

  Future<void> _fetchSummary(int seq, MaTvChannel ch) async {
    final data = await _sources.channel(ch.number);
    if (!mounted || seq != _tuneSeq || data == null) return;
    final cur = data.current;
    if (cur == null) return;
    final details = cur.details(french: true);
    setState(() {
      _sourceLine = 'Source ${cur.rank}/${data.sources.length}${details.isEmpty ? '' : ' · $details'}';
    });
  }

  void _zap(int delta) {
    if (_list.length < 2) return;
    setState(() => _index = (_index + delta) % _list.length);
    _tune();
  }

  Future<void> _refreshList() async {
    if (_catId == 'fav' || _catId == 'recent') return;
    final fresh = await _client.channels(_catId, fresh: true);
    if (!mounted || fresh == null || fresh.isEmpty) return;
    final id = _channel.id;
    final i = fresh.indexWhere((c) => c.id == id);
    if (i < 0) return;
    setState(() {
      _list = fresh;
      _index = i;
      _now = DateTime.now();
    });
  }

  // ---------------------------------------------------------------- number entry
  void _digit(String d) {
    _numberTimer?.cancel();
    setState(() => _number = (_number + d).length > 5 ? d : _number + d);
    _showBanner();
    _numberTimer = Timer(const Duration(milliseconds: 1400), _goNumber);
  }

  Future<void> _goNumber() async {
    final n = int.tryParse(_number);
    setState(() => _number = '');
    if (n == null) return;
    final here = _list.indexWhere((c) => c.number == n);
    if (here >= 0) {
      setState(() => _index = here);
      _tune(immediate: true);
      return;
    }
    final all = await _client.allChannels();
    if (!mounted || all == null) return;
    final i = all.indexWhere((c) => c.number == n);
    if (i < 0) {
      setState(() => _status = 'Pas de chaîne $n');
      _showBanner();
      return;
    }
    setState(() {
      _list = all;
      _index = i;
      _catId = 'all';
      _catLabel = 'Toutes les chaînes';
    });
    _tune(immediate: true);
  }

  // ---------------------------------------------------------------- overlays
  void _close() {
    setState(() => _overlay = _Overlay.none);
    _showBanner(time: const Duration(seconds: 2));
    _focus.requestFocus();
  }

  List<({IconData icon, String label})> get _guideActions {
    final ch = _channel;
    final fav = _favorites.contains(ch.id);
    return [
      if (_replaying != null) (icon: Icons.live_tv_rounded, label: 'Revenir au direct'),
      if (ch.replayDays > 0 && ch.programAt(_now) != null && _replaying == null)
        (icon: Icons.restart_alt_rounded, label: 'Revoir depuis le début'),
      if (ch.replayDays > 0) (icon: Icons.history_rounded, label: 'Replay de la chaîne'),
      (icon: fav ? Icons.star_rounded : Icons.star_border_rounded, label: fav ? 'Retirer des favoris' : 'Ajouter aux favoris'),
      (icon: Icons.tune_rounded, label: 'Sources'),
      (icon: Icons.list_rounded, label: 'Liste des chaînes'),
    ];
  }

  Future<void> _openGuide() async {
    setState(() {
      _overlay = _Overlay.guide;
      _guideAction = 0;
      _guidePrograms = const [];
    });
    final ch = _channel;
    final now = DateTime.now();
    final progs = await _client.programs([ch.id], now.subtract(const Duration(hours: 1)), now.add(const Duration(hours: 10)));
    if (!mounted || _channel.id != ch.id) return;
    setState(() => _guidePrograms = progs?[ch.id] ?? const []);
  }

  Future<void> _guideDo(int i) async {
    final actions = _guideActions;
    if (i < 0 || i >= actions.length) return;
    final label = actions[i].label;
    switch (label) {
      case 'Revenir au direct':
        _close();
        _tune(immediate: true);
      case 'Revoir depuis le début':
        final cur = _guidePrograms.where((p) => p.isOnAt(DateTime.now())).firstOrNull ?? _channel.programAt(DateTime.now());
        if (cur != null) _playReplay(cur);
      case 'Replay de la chaîne':
        await _openReplay();
      case 'Sources':
        setState(() => _overlay = _Overlay.sources);
      case 'Liste des chaînes':
        _openList();
      default:
        await _toggleFavorite();
        setState(() {});
    }
  }

  Future<void> _toggleFavorite() async {
    final ch = _channel;
    final on = await MaTvMemory.toggleFavorite(ch.id);
    if (!mounted) return;
    setState(() {
      _favorites = MaTvMemory.favorites.toSet();
      _status = on ? 'Ajoutée aux favoris' : 'Retirée des favoris';
    });
    _showBanner(time: const Duration(seconds: 3));
    Timer(const Duration(seconds: 3), () {
      if (mounted && (_status == 'Ajoutée aux favoris' || _status == 'Retirée des favoris')) {
        setState(() => _status = null);
      }
    });
  }

  List<MaTvCategory> get _listCats {
    final fav = MaTvMemory.favorites;
    final server = widget.categories.where((c) => c.kind != 'fav' && c.kind != 'recent');
    return [
      if (fav.isNotEmpty) MaTvCategory(id: 'fav', label: 'Favoris', kind: 'fav', count: fav.length),
      MaTvCategory(id: 'recent', label: 'Récentes', kind: 'recent', count: MaTvMemory.recent.length),
      ...server,
    ];
  }

  void _openList() {
    final cats = _listCats;
    final at = cats.indexWhere((c) => c.id == _catId);
    setState(() {
      _overlay = _Overlay.list;
      _listColumn = 1;
      _listCat = at >= 0 ? at : 0;
      _listCatId = _catId;
      _listChans = _list;
      _listChan = _index;
    });
    _scrollIn(_listChanScroll, _listChan, MaTvChannelRow.compactHeight + 6);
    _scrollIn(_listCatScroll, _listCat, MaTvCategoryList.rowHeight);
  }

  Future<void> _listOpenCategory(int i) async {
    final cats = _listCats;
    if (i < 0 || i >= cats.length) return;
    final c = cats[i];
    setState(() => _listCat = i);
    List<MaTvChannel>? chans;
    if (c.kind == 'fav' || c.kind == 'recent') {
      final all = await _client.allChannels();
      final byId = {for (final ch in all ?? const <MaTvChannel>[]) ch.id: ch};
      final ids = c.kind == 'fav' ? MaTvMemory.favorites : MaTvMemory.recent;
      chans = [for (final id in ids) if (byId[id] case final MaTvChannel ch) ch];
    } else {
      chans = await _client.channels(c.id);
    }
    if (!mounted || _listCat != i) return;
    setState(() {
      _listCatId = c.id;
      _listChans = chans ?? const [];
      final here = _listChans.indexWhere((x) => x.id == _channel.id);
      _listChan = here >= 0 ? here : 0;
    });
    _scrollIn(_listChanScroll, _listChan, MaTvChannelRow.compactHeight + 6);
  }

  void _listPlay(int i) {
    if (i < 0 || i >= _listChans.length) return;
    final cats = _listCats;
    setState(() {
      _list = _listChans;
      _index = i;
      _catId = _listCatId;
      _catLabel = cats.isEmpty ? '' : cats[_listCat.clamp(0, cats.length - 1)].label;
      _overlay = _Overlay.none;
    });
    _tune(immediate: true);
  }

  Future<void> _openReplay() async {
    final ch = _channel;
    setState(() {
      _overlay = _Overlay.replay;
      _replayPrograms = const [];
      _replayIndex = 0;
    });
    final now = DateTime.now();
    final days = ch.replayDays.clamp(1, 7);
    final progs = await _client.programs([ch.id], now.subtract(Duration(days: days)), now);
    if (!mounted || _channel.id != ch.id) return;
    final past = (progs?[ch.id] ?? const <MaTvProgram>[]).where((p) => p.start.isBefore(now)).toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    setState(() => _replayPrograms = past);
  }

  void _playReplay(MaTvProgram p) {
    final ch = _channel;
    final uri = _client.replayUri(ch, p);
    setState(() {
      _overlay = _Overlay.none;
      _replaying = p;
      _status = 'Ouverture du replay…';
      _sourceLine = null;
    });
    _showBanner(time: const Duration(seconds: 6));
    unawaited(_open(ch, uri));
  }

  void _scrollIn(ScrollController c, int index, double extent) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!c.hasClients) return;
      final view = c.position.viewportDimension;
      final top = index * extent;
      var target = c.offset;
      if (top < c.offset + extent) target = top - extent;
      if (top + extent > c.offset + view - extent) target = top + 2 * extent - view;
      c.jumpTo(target.clamp(0.0, c.position.maxScrollExtent));
    });
  }

  // ---------------------------------------------------------------- keys
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_overlay == _Overlay.sources) return KeyEventResult.ignored; // the panel has the keys
    if (!event.isActionable) return KeyEventResult.handled;
    final key = event.logicalKey;
    final digit = _digitOf(key);
    if (digit != null && _overlay == _Overlay.none) {
      _digit(digit);
      return KeyEventResult.handled;
    }
    switch (_overlay) {
      case _Overlay.guide:
        return _guideKey(key, event);
      case _Overlay.list:
        return _listKey(key, event);
      case _Overlay.replay:
        return _replayKey(key, event);
      case _Overlay.sources:
      case _Overlay.none:
        break;
    }
    if (key.isBackKey) {
      if (_replaying != null) {
        _tune(immediate: true);
        return KeyEventResult.handled;
      }
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (key.isDownKey || key == LogicalKeyboardKey.channelUp) {
      _zap(1);
      return KeyEventResult.handled;
    }
    if (key.isUpKey || key == LogicalKeyboardKey.channelDown) {
      _zap(-1);
      return KeyEventResult.handled;
    }
    if (key.isLeftKey) {
      _openList();
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      setState(() => _overlay = _Overlay.sources);
      return KeyEventResult.handled;
    }
    if (key.isSelectKey && event is KeyDownEvent) {
      if (_number.isNotEmpty) {
        _numberTimer?.cancel();
        unawaited(_goNumber());
      } else {
        unawaited(_openGuide());
      }
      return KeyEventResult.handled;
    }
    if (key.isContextMenuKey) {
      unawaited(_toggleFavorite());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.info) {
      _showBanner();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.mediaPause || key == LogicalKeyboardKey.mediaPlay) {
      unawaited(_player.playOrPause());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String? _digitOf(LogicalKeyboardKey key) {
    const digits = [
      LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
    ];
    const pad = [
      LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
    ];
    final i = digits.indexOf(key);
    if (i >= 0) return '$i';
    final j = pad.indexOf(key);
    return j >= 0 ? '$j' : null;
  }

  KeyEventResult _guideKey(LogicalKeyboardKey key, KeyEvent event) {
    final n = _guideActions.length;
    if (key.isBackKey || key.isDownKey || key.isUpKey) {
      _close();
      return KeyEventResult.handled;
    }
    if (key.isLeftKey) {
      setState(() => _guideAction = (_guideAction - 1).clamp(0, n - 1));
    } else if (key.isRightKey) {
      setState(() => _guideAction = (_guideAction + 1).clamp(0, n - 1));
    } else if (key.isSelectKey && event is KeyDownEvent) {
      unawaited(_guideDo(_guideAction));
    } else if (key.isContextMenuKey) {
      unawaited(_toggleFavorite());
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _listKey(LogicalKeyboardKey key, KeyEvent event) {
    final cats = _listCats;
    if (key.isBackKey) {
      _close();
      return KeyEventResult.handled;
    }
    if (key.isUpKey || key.isDownKey || key.pageDirection != 0) {
      final d = key.pageDirection != 0 ? key.pageDirection * 8 : (key.isDownKey ? 1 : -1);
      if (_listColumn == 0) {
        final next = (_listCat + d).clamp(0, cats.length - 1);
        unawaited(_listOpenCategory(next));
        _scrollIn(_listCatScroll, next, MaTvCategoryList.rowHeight);
      } else if (_listChans.isNotEmpty) {
        setState(() => _listChan = (_listChan + d).clamp(0, _listChans.length - 1));
        _scrollIn(_listChanScroll, _listChan, MaTvChannelRow.compactHeight + 6);
      }
      return KeyEventResult.handled;
    }
    if (key.isLeftKey) {
      if (_listColumn == 1) {
        setState(() => _listColumn = 0);
      } else {
        _close();
      }
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      if (_listColumn == 0) {
        setState(() => _listColumn = 1);
      } else {
        _close();
      }
      return KeyEventResult.handled;
    }
    if (key.isSelectKey && event is KeyDownEvent) {
      if (_listColumn == 0) {
        setState(() => _listColumn = 1);
      } else {
        _listPlay(_listChan);
      }
      return KeyEventResult.handled;
    }
    if (key.isContextMenuKey && _listColumn == 1 && _listChan < _listChans.length) {
      final id = _listChans[_listChan].id;
      unawaited(MaTvMemory.toggleFavorite(id).then((_) {
        if (mounted) setState(() => _favorites = MaTvMemory.favorites.toSet());
      }));
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _replayKey(LogicalKeyboardKey key, KeyEvent event) {
    if (key.isBackKey || key.isLeftKey) {
      _close();
      return KeyEventResult.handled;
    }
    if ((key.isUpKey || key.isDownKey) && _replayPrograms.isNotEmpty) {
      setState(() => _replayIndex = (_replayIndex + (key.isDownKey ? 1 : -1)).clamp(0, _replayPrograms.length - 1));
      _scrollIn(_replayScroll, _replayIndex, MaTvReplayList.rowHeight + 6);
      return KeyEventResult.handled;
    }
    if (key.isSelectKey && event is KeyDownEvent && _replayIndex < _replayPrograms.length) {
      _playReplay(_replayPrograms[_replayIndex]);
    }
    return KeyEventResult.handled;
  }

  // ---------------------------------------------------------------- layout
  @override
  Widget build(BuildContext context) {
    final ch = _list.isEmpty ? null : _channel;
    return PopScope(
      canPop: _overlay == _Overlay.none && _replaying == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_overlay != _Overlay.none) {
          _close();
        } else if (_replaying != null) {
          _tune(immediate: true);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_overlay != _Overlay.none) {
                _close();
              } else if (_banner) {
                setState(() => _banner = false);
              } else {
                _showBanner();
              }
            },
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() > 300 && _overlay == _Overlay.none) _zap(v < 0 ? 1 : -1);
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: Video(
                    controller: _video,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                    fill: Colors.black,
                    pauseUponEnteringBackgroundMode: false,
                  ),
                ),
                if (!_picture && _status != null && _overlay == _Overlay.none)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                if (ch != null && (_banner || _number.isNotEmpty) && _overlay == _Overlay.none)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: MaTvBanner(
                      channel: ch,
                      now: _now,
                      sourceLine: _sourceLine,
                      status: _status,
                      categoryLabel: _catLabel,
                      favorite: _favorites.contains(ch.id),
                      replayLabel: _replaying == null
                          ? null
                          : 'Replay · ${_replaying!.title} · ${maTvDay(_replaying!.start, _now)} ${maTvRange(_replaying!)}',
                    ),
                  ),
                if (_number.isNotEmpty)
                  Positioned(
                    top: 32,
                    right: 40,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(color: MaTvColors.panel, borderRadius: BorderRadius.circular(12)),
                      child: Text(_number, style: const TextStyle(color: MaTvColors.ink, fontSize: 40, fontWeight: FontWeight.w800)),
                    ),
                  ),
                if (_touch && _banner && _overlay == _Overlay.none) _touchBar(),
                if (ch != null && _overlay == _Overlay.guide)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: MaTvMiniGuide(
                      channel: ch,
                      programs: _guidePrograms,
                      now: DateTime.now(),
                      actions: _guideActions,
                      selectedAction: _guideAction,
                      onAction: (i) => unawaited(_guideDo(i)),
                    ),
                  ),
                if (_overlay == _Overlay.list) _listPanel(),
                if (ch != null && _overlay == _Overlay.replay) _replayPanel(ch),
                if (ch != null && _overlay == _Overlay.sources)
                  TvSourcesPanel(
                    channelNumber: ch.number,
                    channelName: ch.name,
                    client: _sources,
                    onClose: _close,
                    onPicked: (text) {
                      setState(() => _sourceLine = text);
                      _showBanner();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _touchBar() {
    Widget b(IconData icon, String tip, VoidCallback onTap) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon, color: MaTvColors.ink, size: 28),
    );
    return Positioned(
      top: 12,
      right: 12,
      child: Container(
        decoration: BoxDecoration(color: MaTvColors.panelSoft, borderRadius: BorderRadius.circular(26)),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            b(Icons.arrow_back_rounded, 'Fermer', () => Navigator.of(context).maybePop()),
            b(Icons.keyboard_arrow_up_rounded, 'Chaîne précédente', () => _zap(-1)),
            b(Icons.keyboard_arrow_down_rounded, 'Chaîne suivante', () => _zap(1)),
            b(Icons.list_rounded, 'Liste', _openList),
            b(Icons.info_outline_rounded, 'Guide', () => unawaited(_openGuide())),
            b(Icons.tune_rounded, 'Sources', () => setState(() => _overlay = _Overlay.sources)),
          ],
        ),
      ),
    );
  }

  Widget _listPanel() {
    final cats = _listCats;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 760;
    return Positioned(
      top: 0,
      bottom: 0,
      left: 0,
      width: narrow ? width : 720,
      child: Container(
        color: MaTvColors.panel,
        padding: EdgeInsets.fromLTRB(18, MediaQuery.paddingOf(context).top + 18, 18, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!narrow) ...[
              SizedBox(
                width: 210,
                child: MaTvCategoryList(
                  categories: cats,
                  selected: _listCat,
                  focused: _listColumn == 0,
                  controller: _listCatScroll,
                  onTap: (i) {
                    setState(() => _listColumn = 0);
                    unawaited(_listOpenCategory(i));
                  },
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: MaTvChannelList(
                channels: _listChans,
                selected: _listChan,
                focused: _listColumn == 1,
                now: DateTime.now(),
                favorites: _favorites,
                playingId: _playingId,
                compact: true,
                controller: _listChanScroll,
                onTap: _listPlay,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _replayPanel(MaTvChannel ch) {
    final width = MediaQuery.sizeOf(context).width;
    return Positioned(
      top: 0,
      bottom: 0,
      left: 0,
      width: width < 760 ? width : 640,
      child: Container(
        color: MaTvColors.panel,
        padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('REPLAY', style: TextStyle(color: MaTvColors.mute, fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${ch.number}  ${ch.name}', style: const TextStyle(color: MaTvColors.ink, fontSize: 22, fontWeight: FontWeight.w700)),
            Text('Jusqu’à ${ch.replayDays} jours en arrière', style: const TextStyle(color: MaTvColors.faint, fontSize: 13)),
            const SizedBox(height: 14),
            Expanded(
              child: MaTvReplayList(
                channel: ch,
                programs: _replayPrograms,
                now: DateTime.now(),
                selected: _replayIndex,
                controller: _replayScroll,
                onTap: (i) => _playReplay(_replayPrograms[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
