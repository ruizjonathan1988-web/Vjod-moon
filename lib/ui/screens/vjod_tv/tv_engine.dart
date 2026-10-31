// The two picture engines behind Ma TV's player, behind one face so the
// player doesn't care which one runs:
//
// - ExoPlayer (Media3), the engine of TiviMate and of most IPTV apps on
//   Android: the box's own video decoder, frame-rate matching, made for live
//   TS. Moonfin already ships it for Jellyfin; it is used here as it is.
// - mpv (media_kit), the engine Ma TV started with: reads about anything,
//   kept as the fallback for what ExoPlayer won't open.
//
// "Auto" starts with ExoPlayer and falls back to mpv for a channel whose
// picture ExoPlayer doesn't bring, and remembers it for the session.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:moonfin_native_video/moonfin_native_video.dart';

import '../../../playback/media3_player_backend.dart';
import '../../../preference/seerr_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../../util/vjod_text.dart';

String _tn(String fr, String en, String ru, String zh) =>
    vjodTextNow(fr: fr, en: en, ru: ru, zh: zh);


/// Which engine the viewer asked for: auto, exo or mpv.
class TvEngineChoice {
  static List<(String, String)> get options => [
    ('auto', _tn('Auto (ExoPlayer, sinon mpv)', 'Auto (ExoPlayer, else mpv)', 'Авто (ExoPlayer, иначе mpv)', '自动（ExoPlayer，否则 mpv）')),
    ('exo', 'ExoPlayer'),
    ('mpv', _tn('mpv (ancien lecteur)', 'mpv (old player)', 'mpv (старый плеер)', 'mpv（旧播放器）')),
  ];

  static SeerrPreferences? get _prefs {
    final getIt = GetIt.instance;
    return getIt.isRegistered<SeerrPreferences>() ? getIt<SeerrPreferences>() : null;
  }

  static String get value => _prefs?.maTvEngine ?? 'auto';

  static String get label =>
      options.firstWhere((o) => o.$1 == value, orElse: () => options.first).$2;

  static Future<void> next() async {
    final p = _prefs;
    if (p == null) return;
    final i = options.indexWhere((o) => o.$1 == value);
    await p.setMaTvEngine(options[(i + 1) % options.length].$1);
  }

  /// Whether ExoPlayer can run here at all (Android only).
  static bool get exoAvailable =>
      PlatformDetection.isAndroid && GetIt.instance.isRegistered<Media3PlayerBackend>();
}

abstract class TvEngine {
  /// Short name shown to the viewer.
  String get name;

  /// The first picture of what was opened last.
  Stream<void> get firstFrame;
  Stream<bool> get buffering;

  /// A failure, in words.
  Stream<String> get errors;
  Stream<bool> get completed;
  Duration get position;

  Future<void> open(String url, {bool live = true});
  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Widget view();
  Future<void> dispose();
}

// ---------------------------------------------------------------------- mpv
class MpvTvEngine implements TvEngine {
  MpvTvEngine() {
    _player = Player(configuration: const PlayerConfiguration(libass: false));
    _video = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        hwdec: PlatformDetection.isAndroid ? 'auto-copy' : (PlatformDetection.isLinux ? 'auto-safe' : null),
      ),
    );
    _subs.add(_player.stream.width.listen((w) {
      if ((w ?? 0) > 0 && !_seen) {
        _seen = true;
        _first.add(null);
      }
    }));
    _subs.add(_player.stream.error.listen(_errors.add));
    unawaited(_tuneLive());
  }

  late final Player _player;
  late final VideoController _video;
  final _first = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  bool _seen = false;

  Future<void> _tuneLive() async {
    final p = _player.platform;
    if (p is! NativePlayer) return;
    // A live stream from the relay: open fast (less probing), reconnect if
    // the link to the seedbox drops, keep the buffer modest on TV boxes.
    for (final kv in const [
      ('network-timeout', '15'),
      ('demuxer-lavf-analyzeduration', '0.6'),
      ('demuxer-lavf-probesize', '700000'),
      ('cache', 'yes'),
      ('demuxer-readahead-secs', '8'),
      // Start (and restart after a stall) with a few seconds in hand instead
      // of playing the first bytes and stopping again at once.
      ('cache-pause-initial', 'yes'),
      ('cache-pause-wait', '3'),
      ('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=4'),
      ('sub-create-cc-track', 'yes'),
    ]) {
      try {
        final dynamic native = p;
        await Future<void>.value(native.setProperty(kv.$1, kv.$2));
      } catch (_) {}
    }
  }

  @override
  String get name => 'mpv';
  @override
  Stream<void> get firstFrame => _first.stream;
  @override
  Stream<bool> get buffering => _player.stream.buffering;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Stream<bool> get completed => _player.stream.completed;
  @override
  Duration get position => _player.state.position;

  @override
  Future<void> open(String url, {bool live = true}) async {
    // The width stays at the last picture's while the next one opens, so
    // "first frame" only fires once it has been back at zero.
    _seen = false;
    await _player.open(Media(url), play: true);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> playOrPause() => _player.playOrPause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() => _player.stop();

  @override
  Widget view() => Video(
    controller: _video,
    controls: NoVideoControls,
    fit: BoxFit.contain,
    fill: Colors.black,
    pauseUponEnteringBackgroundMode: false,
  );

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _first.close();
    await _errors.close();
    await _player.dispose();
  }
}

// ---------------------------------------------------------------- ExoPlayer
class ExoTvEngine implements TvEngine {
  ExoTvEngine() : _backend = GetIt.instance<Media3PlayerBackend>() {
    _subs.add(_backend.firstFrameStream.listen((_) {
      _first.add(null);
      if (_cushionDue) {
        _cushionDue = false;
        unawaited(_fillCushion());
      }
    }));
    _subs.add(_backend.errorStream.listen((e) {
      final msg = (e['message'] ?? e['error'] ?? e['code'] ?? _tn('erreur ExoPlayer', 'ExoPlayer error', 'ошибка ExoPlayer', 'ExoPlayer 错误')).toString();
      _errors.add(msg);
    }));
  }

  final Media3PlayerBackend _backend;
  final _first = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  Completer<void>? _viewReady = Completer<void>();

  // A live channel starts as soon as ExoPlayer holds 2.5 s, while the stream
  // only arrives as fast as it plays: the slightest hiccup on the way then
  // stops the picture, which is the stutter of the first seconds. On the
  // first picture the player waits (picture shown, still) until it holds
  // [_cushion], [_cushionMax] at most, then plays with that margin.
  static const _cushion = Duration(seconds: 5);
  static const _cushionMax = Duration(seconds: 4);
  bool _cushionDue = false;
  Timer? _cushionTimer;

  Future<void> _fillCushion() async {
    _cushionTimer?.cancel();
    if (_backend.buffer - _backend.position >= _cushion) return;
    await _backend.pause();
    final until = DateTime.now().add(_cushionMax);
    _cushionTimer = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (_backend.buffer - _backend.position >= _cushion || DateTime.now().isAfter(until)) {
        t.cancel();
        _cushionTimer = null;
        unawaited(_backend.resume());
      }
    });
  }

  void _dropCushion() {
    _cushionDue = false;
    final t = _cushionTimer;
    _cushionTimer = null;
    t?.cancel();
  }

  @override
  String get name => 'ExoPlayer';
  @override
  Stream<void> get firstFrame => _first.stream;
  @override
  Stream<bool> get buffering => _backend.bufferingStream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Stream<bool> get completed => _backend.completedStream;
  @override
  Duration get position => _backend.position;

  @override
  Future<void> open(String url, {bool live = true}) async {
    // The surface has to exist before the source is set.
    final ready = _viewReady;
    if (ready != null && !ready.isCompleted) {
      await ready.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    }
    _dropCushion();
    _cushionDue = live;
    await _backend.play({
      'url': url,
      'isLive': live,
      'mediaType': 'video',
      if (live) 'container': 'ts',
      'autoPlay': true,
    });
  }

  @override
  Future<void> play() {
    _dropCushion();
    return _backend.resume();
  }

  @override
  Future<void> pause() {
    _dropCushion();
    return _backend.pause();
  }

  @override
  Future<void> playOrPause() {
    final wasHolding = _cushionTimer != null;
    _dropCushion();
    // Pressed while it fills its margin: play now.
    if (wasHolding) return _backend.resume();
    return _backend.isPlaying ? _backend.pause() : _backend.resume();
  }

  @override
  Future<void> seek(Duration position) => _backend.seekTo(position);
  @override
  Future<void> stop() {
    _dropCushion();
    return _backend.stop();
  }

  @override
  Widget view() => Media3VideoView(
    fill: Colors.black,
    onPlatformViewCreated: (id) {
      unawaited(_backend.activateView(id));
      final ready = _viewReady;
      if (ready != null && !ready.isCompleted) ready.complete();
    },
  );

  @override
  Future<void> dispose() async {
    _viewReady = null;
    _dropCushion();
    for (final s in _subs) {
      await s.cancel();
    }
    await _first.close();
    await _errors.close();
    // The backend is Moonfin's own, shared with Jellyfin playback: stopped,
    // never disposed.
    try {
      await _backend.stop();
    } catch (_) {}
  }
}
