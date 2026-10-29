// The live player of Ma TV, like TiviMate: DOWN / UP zap inside the category
// (CH+ / CH- too), OK opens the channel list over the picture, LEFT / RIGHT go
// back or forward 30 s in the live (out of the seedbox's buffer of the last
// minutes), a long OK or MENU the options (sources, favourite, watch from the
// start, replay, guide grid, quality), PLAY/PAUSE pauses and picks up where it
// stopped, BACK closes what is open, then returns to live, then leaves. Digits
// jump to a number. The relay on the seedbox does the rest: best source
// first, the next one if it drops, one connection shared by everyone.
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
import 'ma_tv_guide.dart';
import 'ma_tv_widgets.dart';

enum _Overlay { none, guide, list, sources, replay }

class MaTvPlayerScreen extends StatefulWidget {
  final List<MaTvChannel> channels;
  final int startIndex;
  final String categoryId;
  final String categoryLabel;
  final List<MaTvCategory> categories;

  /// A past programme to open in replay rather than the live channel.
  final MaTvProgram? startReplay;

  /// Kids Mode: only the channels given, no sources, no other categories.
  final bool kids;

  const MaTvPlayerScreen({
    super.key,
    required this.channels,
    required this.startIndex,
    required this.categoryId,
    required this.categoryLabel,
    this.categories = const [],
    this.startReplay,
    this.kids = false,
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
  // Built each time: the caps it carries follow the quality chosen and the
  // connection measured.
  TvSourcesClient get _sources => _client.sourcesClient();
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

  // Back in time: how far behind live the picture is (zero = live), and
  // when it was paused.
  Duration _delay = Duration.zero;
  DateTime? _pausedAt;
  Duration _pendingDelay = Duration.zero;
  bool _seekPending = false;
  Timer? _seekTimer;
  DateTime? _selectDownAt;
  bool _selectLongFired = false;
  String? _sourceLine;
  int _tuneSeq = 0;
  DateTime? _openedAt;
  bool _picture = false;
  bool _retried = false;
  bool _failed = false;
  bool _nextSourceInFlight = false;
  DateTime? _reconnectAfter;
  MaTvChannel? _openedCh;
  final Set<String> _tried = {};
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
        final opened = _openedAt;
        if (!mounted) return;
        // How long the picture took, shown a moment: the number to compare
        // from one source, channel or box to another.
        final secs = opened == null ? null : DateTime.now().difference(opened).inMilliseconds / 1000;
        setState(() => _status = secs == null ? null : 'Image en ${secs.toStringAsFixed(1).replaceAll('.', ',')} s');
        Timer(const Duration(seconds: 4), () {
          if (mounted && (_status ?? '').startsWith('Image en')) setState(() => _status = null);
        });
      }
    }));
    _subs.add(_player.stream.buffering.listen((b) {
      if (!mounted || !_picture) return;
      setState(() => _status = b ? 'Mise en mémoire…' : null);
      if (b) _onStall();
    }));
    _subs.add(_player.stream.error.listen((e) {
      if (!mounted) return;
      final wasPlaying = _picture;
      setState(() => _status = wasPlaying ? 'Lecture interrompue, reconnexion…' : 'Le flux ne démarre pas, nouvel essai…');
      if (wasPlaying) {
        // Back to no picture: a recovery before the reconnect delay (ffmpeg's
        // own reconnect) sets it again and cancels the reopen.
        _picture = false;
        _reconnect();
      }
    }));
    // The picture had started and the stream ended anyway (the link to the
    // seedbox dropped, the provider closed…): open the same address again.
    _subs.add(_player.stream.completed.listen((done) {
      if (done != true || !mounted || _replaying != null || _pausedAt != null || !_picture) return;
      _picture = false;
      _reconnect();
    }));
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) => _refreshList());
    if (_list.isNotEmpty) {
      final replay = widget.startReplay;
      if (replay != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _playReplay(replay);
        });
      } else {
        _tune(immediate: true);
      }
    }
  }

  Future<void> _tuneLiveDefaults() async {
    final p = _player.platform;
    if (p is! NativePlayer) return;
    // A live stream from the relay: open fast (less probing), reconnect if
    // the link to the seedbox drops, keep the buffer modest on TV boxes.
    for (final kv in const [
      ('network-timeout', '15'),
      // Read less of the stream before showing it: ffmpeg's default probe
      // (5 MB) alone is several seconds on a live channel.
      ('demuxer-lavf-analyzeduration', '0.6'),
      ('demuxer-lavf-probesize', '700000'),
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

  // ---------------------------------------------------------------- adapting to the connection
  final List<DateTime> _stalls = [];
  DateTime? _lighterAt;

  /// The picture keeps stopping to fill its buffer: the connection carries
  /// less than this source needs. Three stalls in a minute move to a lighter
  /// source (smaller picture or lower rate), for this time only.
  void _onStall() {
    if (_replaying != null) return;
    final now = DateTime.now();
    _stalls
      ..removeWhere((t) => now.difference(t) > const Duration(seconds: 60))
      ..add(now);
    if (_stalls.length < 3) return;
    if (_lighterAt != null && now.difference(_lighterAt!) < const Duration(seconds: 45)) return;
    _lighterAt = now;
    _stalls.clear();
    unawaited(_goLighter());
  }

  Future<void> _goLighter() async {
    final ch = _channel;
    final data = await _sources.channel(ch.number);
    if (!mounted || data == null || data.sources.length < 2) return;
    final cur = data.current;
    int weight(TvSource s) => (s.kbps ?? 0) > 0 ? s.kbps! : ((s.height ?? 0) > 0 ? s.height! * 6 : 4000);
    final curWeight = cur == null ? 1 << 30 : weight(cur);
    if (cur?.kbps != null && cur!.kbps! > 0) MaTvDevice.lowerTo((cur.kbps! * 0.9).round());
    final lighter = data.sources.where((s) => s.key != cur?.key && s.ok != false && weight(s) < curWeight).toList()
      ..sort((a, b) => weight(b).compareTo(weight(a)));
    if (lighter.isEmpty) {
      setState(() => _status = 'Connexion faible et aucune source plus légère');
      return;
    }
    final pick = lighter.first;
    await _sources.prefer(data.id, pick.key);
    if (!mounted) return;
    setState(() => _status = 'Connexion faible : source plus légère (${pick.resolutionLabel.isEmpty ? pick.quality : pick.resolutionLabel})');
    _showBanner(time: const Duration(seconds: 5));
  }

  void _screensaver(bool on) {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<ScreensaverController>()) getIt<ScreensaverController>().setPlaybackActive(on);
  }

  @override
  void dispose() {
    _screensaver(false);
    for (final t in [_clock, _zapTimer, _bannerTimer, _watchdog, _summaryTimer, _numberTimer, _refreshTimer, _seekTimer]) {
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
    _delay = Duration.zero;
    _pausedAt = null;
    _seekPending = false;
    _seekTimer?.cancel();
    _zapTimer?.cancel();
    _tried.clear();
    setState(() {
      _status = 'Ouverture…';
      _sourceLine = null;
      _now = DateTime.now();
      _failed = false;
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
    _openedCh = ch;
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
      // Source failover only exists for the live channel; a replay or a
      // timeshift that gives no picture must not silently turn into live TV.
      if (_replaying != null || _delay > Duration.zero) {
        _watchdog?.cancel();
        setState(() {
          _status = 'Pas d’image pour cette lecture · Retour pour revenir au direct';
          _failed = true;
        });
        _showBanner(time: const Duration(seconds: 12));
      } else {
        unawaited(_nextSource());
      }
    }
  }

  /// The stream was playing and died: open the same address again once the
  /// player settles, unless the relay already picks up on the other side.
  void _reconnect() {
    // Live reopens the live address; a timeshift comes back where the picture
    // stopped (recomputed at fire time, the anchor grows with elapsed
    // playback) instead of restarting from the original seek point.
    final ch = _openedCh;
    final live = _delay == Duration.zero;
    if (ch == null || _replaying != null || _pausedAt != null || _overlay == _Overlay.sources) return;
    final when = DateTime.now().add(const Duration(milliseconds: 1200));
    final at = _reconnectAfter;
    if (at != null && at.isAfter(when)) return;
    _reconnectAfter = when;
    Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || _reconnectAfter != when) return;
      _reconnectAfter = null;
      if (_picture || _replaying != null || _pausedAt != null || _openedCh?.id != ch.id) return;
      if (live) {
        final uri = _client.liveUri(ch);
        if (uri != null) unawaited(_open(ch, uri));
      } else {
        unawaited(() async {
          final seq = _tuneSeq;
          await _applyDelay(_delay);
          // _applyDelay only opens when the relay still has the buffer; when it
          // can't, surface the failure like a dead source instead of a stuck
          // screen — OK falls back to live via _tryNextSource.
          if (!mounted || _picture || _tuneSeq != seq) return;
          _watchdog?.cancel();
          setState(() {
            _status = 'Pas d’image pour cette lecture · Retour pour revenir au direct';
            _failed = true;
          });
          _showBanner(time: const Duration(seconds: 12));
        }());
      }
    });
  }

  /// Every source the automatic order put first was tried: ask the relay for
  /// the next one. Nothing left -> give up with the choice still open.
  Future<void> _nextSource() async {
    if (_nextSourceInFlight || _replaying != null || _delay > Duration.zero) return;
    _nextSourceInFlight = true;
    try {
      final ch = _channel;
      final data = await _sources.channel(ch.number);
      if (!mounted || data == null || data.sources.isEmpty) {
        _watchdog?.cancel();
        setState(() {
          _status = 'La chaîne ne répond pas';
          _failed = true;
        });
        _showBanner(time: const Duration(seconds: 12));
        return;
      }
      final cur = data.current;
      if (cur != null) _tried.add(cur.key);
      final rest = data.sources
          .where((x) => x.key != cur?.key && !_tried.contains(x.key) && x.ok != false && !x.duplicate)
          .toList();
      if (rest.isEmpty) {
        _watchdog?.cancel();
        setState(() {
          _status = 'Aucune source ne répond · MENU puis Sources pour en choisir une';
          _failed = true;
        });
        _showBanner(time: const Duration(seconds: 12));
        return;
      }
      final pick = rest.first;
      setState(() => _status = 'Source ${pick.rank}/${data.sources.length} : ${pick.resolutionLabel.isEmpty ? pick.quality : pick.resolutionLabel}…');
      await _sources.prefer(data.id, pick.key);
      if (!mounted) return;
      _retried = false;
      unawaited(_open(ch, _client.liveUri(ch)));
    } finally {
      _nextSourceInFlight = false;
    }
  }

  /// The "next source" action shown when everything failed.
  void _tryNextSource() {
    if (_replaying != null || _delay > Duration.zero) {
      _goLive();
      return;
    }
    _tried.clear();
    unawaited(_nextSource());
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
    if (widget.kids) {
      setState(() => _status = 'Pas de chaîne $n ici');
      _showBanner();
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

  // ---------------------------------------------------------------- back in time
  /// « −1 min 30 », « −45 s ».
  static String fmtDelay(Duration d) {
    final s = d.inSeconds;
    final m = s ~/ 60, r = s % 60;
    if (m == 0) return '−$r s';
    return r == 0 ? '−$m min' : '−$m min ${r.toString().padLeft(2, '0')}';
  }

  /// LEFT / RIGHT: 30 s back or forward. Presses in a row add up and the
  /// stream reopens once, a moment after the last one.
  void _seekBy(int seconds) {
    if (_replaying != null) {
      final pos = _player.state.position + Duration(seconds: seconds);
      unawaited(_player.seek(pos < Duration.zero ? Duration.zero : pos));
      setState(() => _status = seconds < 0 ? '−30 s' : '+30 s');
      _showBanner(time: const Duration(seconds: 2));
      return;
    }
    final base = _seekPending ? _pendingDelay : _delay;
    final next = base - Duration(seconds: seconds);
    _pendingDelay = next < Duration.zero ? Duration.zero : next;
    _seekPending = true;
    setState(() => _status = _pendingDelay == Duration.zero ? 'Direct' : 'Différé ${fmtDelay(_pendingDelay)}');
    _showBanner();
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 600), () {
      _seekPending = false;
      unawaited(_applyDelay(_pendingDelay));
    });
  }

  /// Plays the channel [wanted] behind live, out of the seedbox's buffer
  /// (no further back than it goes). Zero goes back to live.
  Future<void> _applyDelay(Duration wanted, {bool resume = false}) async {
    final ch = _channel;
    if (wanted <= Duration.zero) {
      if (_delay > Duration.zero || resume) _goLive();
      return;
    }
    final info = await _client.shiftInfo(ch);
    if (!mounted || _channel.id != ch.id) return;
    if (info == null || !info.available) {
      setState(() => _status = 'Retour en arrière indisponible');
      _showBanner();
      if (resume) unawaited(_player.play());
      return;
    }
    final now = DateTime.now();
    final delay = info.clamp(wanted, now);
    if (delay <= Duration.zero) {
      setState(() => _status = 'Pas encore assez d’images gardées pour reculer');
      _showBanner();
      if (resume) unawaited(_player.play());
      return;
    }
    setState(() {
      _delay = delay;
      _pausedAt = null;
      _status = 'Différé ${fmtDelay(delay)}';
    });
    _showBanner(time: const Duration(seconds: 4));
    unawaited(_open(ch, _client.shiftUri(ch, now.subtract(delay))));
  }

  void _goLive() {
    _tune(immediate: true);
    setState(() => _status = 'Retour au direct');
  }

  /// PLAY/PAUSE: the picture stops; it starts again where it stopped, out of
  /// the buffer, so nothing is missed.
  void _playPause() {
    if (_replaying != null) {
      unawaited(_player.playOrPause());
      return;
    }
    final paused = _pausedAt;
    if (paused == null) {
      _pausedAt = DateTime.now();
      unawaited(_player.pause());
      _bannerTimer?.cancel();
      setState(() {
        _banner = true;
        _status = 'Pause · ▶ pour reprendre';
      });
      return;
    }
    _pausedAt = null;
    final shownAt = paused.subtract(_delay);
    unawaited(_applyDelay(DateTime.now().difference(shownAt), resume: true));
  }

  /// "Watch from the start": out of the buffer when it goes back that far,
  /// else from the provider's replay.
  Future<void> _fromStart(MaTvProgram cur) async {
    final info = await _client.shiftInfo(_channel);
    if (!mounted) return;
    if (info != null && info.available && info.holds(cur.start)) {
      _close();
      await _applyDelay(DateTime.now().difference(cur.start));
      return;
    }
    if (_channel.replayDays > 0) {
      _playReplay(cur);
      return;
    }
    setState(() => _status = 'Le début n’est plus gardé');
    _close();
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
      if (_replaying != null || _delay > Duration.zero) (icon: Icons.live_tv_rounded, label: 'Revenir au direct'),
      if (ch.programAt(_now) != null && _replaying == null)
        (icon: Icons.restart_alt_rounded, label: 'Revoir depuis le début'),
      if (ch.replayDays > 0) (icon: Icons.history_rounded, label: 'Replay de la chaîne'),
      (icon: fav ? Icons.star_rounded : Icons.star_border_rounded, label: fav ? 'Retirer des favoris' : 'Ajouter aux favoris'),
      (icon: Icons.grid_view_rounded, label: 'Grille des programmes'),
      (icon: Icons.high_quality_rounded, label: 'Qualité : ${MaTvDevice.qualityLabel}'),
      if (!widget.kids) (icon: Icons.tune_rounded, label: 'Sources'),
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
        if (cur != null) await _fromStart(cur);
      case 'Replay de la chaîne':
        await _openReplay();
      case 'Sources':
        setState(() => _overlay = _Overlay.sources);
      case 'Liste des chaînes':
        _openList();
      case 'Grille des programmes':
        await _openGrid();
      case final String q when q.startsWith('Qualité'):
        {
          await MaTvDevice.nextQuality();
          if (!mounted) return;
          setState(() {});
          // Reopen with the new ceiling: the relay picks the source again.
          _zapTimer?.cancel();
          _zapTimer = Timer(const Duration(milliseconds: 1500), () {
            if (mounted && _replaying == null) _open(_channel, _client.liveUri(_channel));
          });
        }
      default:
        await _toggleFavorite();
        setState(() {});
    }
  }

  Future<void> _openGrid() async {
    setState(() => _overlay = _Overlay.none);
    final pick = await Navigator.of(context).push<MaTvGuidePick>(
      maTvRoute((_) => MaTvGuideScreen(channels: _list, startIndex: _index, categoryLabel: _catLabel)),
    );
    if (!mounted) return;
    _focus.requestFocus();
    if (pick == null) return;
    setState(() => _index = pick.index.clamp(0, _list.length - 1));
    final replay = pick.replay;
    if (replay != null) {
      _playReplay(replay);
    } else {
      _tune(immediate: true);
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
    if (widget.kids) {
      return [MaTvCategory(id: _catId, label: _catLabel, kind: 'theme', count: _list.length)];
    }
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
      chans = await _client.channelsByIds(c.kind == 'fav' ? MaTvMemory.favorites : MaTvMemory.recent);
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
    final key = event.logicalKey;
    // OK on the picture: a short press opens the list (or goes to the number
    // typed), a long one the options. Told apart when the key comes up.
    if (_overlay == _Overlay.none && key.isSelectKey) return _selectKey(event);
    if (!event.isActionable) return KeyEventResult.handled;
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
      if (_replaying != null || _delay > Duration.zero || _pausedAt != null) {
        _goLive();
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
    if (key.isLeftKey || key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-30);
      return KeyEventResult.handled;
    }
    if (key.isRightKey || key == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(30);
      return KeyEventResult.handled;
    }
    if (key.isContextMenuKey) {
      unawaited(_openGuide());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.info) {
      _showBanner();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.mediaPause || key == LogicalKeyboardKey.mediaPlay) {
      _playPause();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static const _longPress = Duration(milliseconds: 550);

  KeyEventResult _selectKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      _selectDownAt = DateTime.now();
      _selectLongFired = false;
      return KeyEventResult.handled;
    }
    final down = _selectDownAt;
    if (event is KeyRepeatEvent) {
      // Remotes repeat a held key: past the delay, it is a long press.
      if (!_selectLongFired && down != null && DateTime.now().difference(down) > _longPress) {
        _selectLongFired = true;
        unawaited(_openGuide());
      }
      return KeyEventResult.handled;
    }
    _selectDownAt = null;
    if (down == null || _selectLongFired) return KeyEventResult.handled;
    if (DateTime.now().difference(down) > _longPress) {
      // A remote that doesn't repeat: the length of the press tells.
      unawaited(_openGuide());
    } else if (_number.isNotEmpty) {
      _numberTimer?.cancel();
      unawaited(_goNumber());
    } else if (_failed) {
      _tryNextSource();
    } else {
      _openList();
    }
    return KeyEventResult.handled;
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
                      replayLabel: _replaying != null
                          ? 'Replay · ${_replaying!.title} · ${maTvDay(_replaying!.start, _now)} ${maTvRange(_replaying!)}'
                          : (_delay > Duration.zero
                                ? 'Différé ${fmtDelay(_delay)} · Retour pour revenir au direct'
                                : null),
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
                if (_delay > Duration.zero && !_banner && _overlay == _Overlay.none)
                  Positioned(
                    top: 24,
                    right: 32,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: MaTvColors.panel, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        'Différé ${fmtDelay(_delay)}',
                        style: const TextStyle(color: MaTvColors.ink, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
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
            b(Icons.replay_30_rounded, 'Reculer de 30 s', () => _seekBy(-30)),
            b(Icons.forward_30_rounded, 'Avancer de 30 s', () => _seekBy(30)),
            if (_delay > Duration.zero || _replaying != null) b(Icons.live_tv_rounded, 'Direct', _goLive),
            b(Icons.list_rounded, 'Liste', _openList),
            b(Icons.info_outline_rounded, 'Guide', () => unawaited(_openGuide())),
            b(Icons.grid_view_rounded, 'Grille', () => unawaited(_openGrid())),
            if (!widget.kids) b(Icons.tune_rounded, 'Sources', () => setState(() => _overlay = _Overlay.sources)),
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
