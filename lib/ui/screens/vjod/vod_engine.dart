// The two engines behind the IPTV films and episodes player, behind one face
// (same idea as the live TV's tv_engine.dart):
//
// - ExoPlayer (Media3), Android's own engine, already in Moonfin for
//   Jellyfin: the box's video decoder, frame-rate matching.
// - mpv (media_kit), the fallback for what ExoPlayer won't open, and the only
//   engine off Android.
// - In a browser, the page's own <video> (Moonfin's web player): it plays
//   what the browser decodes (MP4 and most MKV in H.264, not every audio
//   format), without the file's audio and subtitle tracks to choose from.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:moonfin_native_video/moonfin_native_video.dart';

import '../../../playback/html_video_backend.dart';
import '../../../playback/media3_player_backend.dart';
import '../../../playback/subtitle_style.dart';
import '../../../preference/user_preferences.dart';

/// One audio or subtitle track of the file.
class VodTrack {
  final String id;
  final String language;
  final String title;
  const VodTrack(this.id, this.language, this.title);
}

abstract class VodEngine {
  String get name;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get playing;
  Stream<bool> get buffering;
  Stream<String> get errors;
  Stream<void> get firstFrame;

  /// The track lists or the selection changed.
  Stream<void> get tracksChanged;
  List<VodTrack> get audio;
  List<VodTrack> get subtitles;
  String? get audioId;

  /// Null when subtitles are off.
  String? get subtitleId;

  Future<void> open(String url, Map<String, String> headers, {Duration start = Duration.zero});
  Future<void> seek(Duration position);
  Future<void> playOrPause();
  Future<void> setAudio(VodTrack track);
  Future<void> setSubtitle(VodTrack? track);

  /// [scale] around the viewer's usual subtitle size; [raised] lifts them.
  Future<void> styleSubtitles({required double scale, required bool raised});
  Future<void> setSubtitleDelay(double seconds);
  Widget view({required double scale, required bool raised});
  Future<void> dispose();
}

// ---------------------------------------------------------------------- mpv
class MpvVodEngine implements VodEngine {
  MpvVodEngine() {
    _video = VideoController(_player);
    _subs.add(_player.stream.width.listen((w) {
      if ((w ?? 0) > 0 && !_seen) {
        _seen = true;
        _first.add(null);
      }
    }));
    _subs.add(_player.stream.tracks.listen((t) {
      _tracks = t;
      _changed.add(null);
    }));
    _subs.add(_player.stream.track.listen((t) {
      _track = t;
      _changed.add(null);
    }));
  }

  final _player = Player(configuration: const PlayerConfiguration(libass: false));
  late final VideoController _video;
  final _first = StreamController<void>.broadcast();
  final _changed = StreamController<void>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  bool _seen = false;
  Tracks _tracks = const Tracks();
  Track _track = const Track();

  static bool _real(String id) => id != 'auto' && id != 'no';

  @override
  String get name => 'mpv';
  @override
  Stream<Duration> get position => _player.stream.position;
  @override
  Stream<Duration> get duration => _player.stream.duration;
  @override
  Stream<bool> get playing => _player.stream.playing;
  @override
  Stream<bool> get buffering => _player.stream.buffering;
  @override
  Stream<String> get errors => _player.stream.error;
  @override
  Stream<void> get firstFrame => _first.stream;
  @override
  Stream<void> get tracksChanged => _changed.stream;

  @override
  List<VodTrack> get audio => [
    for (final a in _tracks.audio)
      if (_real(a.id)) VodTrack(a.id, a.language ?? '', a.title ?? ''),
  ];
  @override
  List<VodTrack> get subtitles => [
    for (final s in _tracks.subtitle)
      if (_real(s.id)) VodTrack(s.id, s.language ?? '', s.title ?? ''),
  ];
  @override
  String? get audioId => _track.audio.id;
  @override
  String? get subtitleId => _real(_track.subtitle.id) ? _track.subtitle.id : null;

  @override
  Future<void> open(String url, Map<String, String> headers, {Duration start = Duration.zero}) async {
    try {
      final dynamic native = _player.platform;
      for (final kv in const [
        ('network-timeout', '60'),
        ('cache', 'yes'),
        ('demuxer-max-bytes', '150MiB'),
        ('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5'),
      ]) {
        try {
          await Future<void>.value(native.setProperty(kv.$1, kv.$2));
        } catch (_) {}
      }
    } catch (_) {}
    _seen = false;
    await _player.open(Media(url, httpHeaders: headers));
    if (start > Duration.zero) await _player.seek(start);
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> setAudio(VodTrack track) async {
    final t = _tracks.audio.where((a) => a.id == track.id).firstOrNull;
    if (t != null) await _player.setAudioTrack(t);
  }

  @override
  Future<void> setSubtitle(VodTrack? track) async {
    if (track == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final t = _tracks.subtitle.where((s) => s.id == track.id).firstOrNull;
    if (t != null) await _player.setSubtitleTrack(t);
  }

  // Size and place are drawn by the Video widget below.
  @override
  Future<void> styleSubtitles({required double scale, required bool raised}) async {}

  @override
  Future<void> setSubtitleDelay(double seconds) async {
    try {
      final dynamic native = _player.platform;
      await Future<void>.value(native.setProperty('sub-delay', seconds.toStringAsFixed(2)));
    } catch (_) {}
  }

  @override
  Widget view({required double scale, required bool raised}) => Video(
    controller: _video,
    controls: NoVideoControls,
    fit: BoxFit.contain,
    fill: Colors.black,
    subtitleViewConfiguration: SubtitleViewConfiguration(
      style: TextStyle(
        fontSize: 44 * scale,
        color: Colors.white,
        backgroundColor: const Color(0x99000000),
        height: 1.3,
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, raised ? 120 : 24),
    ),
  );

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _first.close();
    await _changed.close();
    await _player.dispose();
  }
}

// ---------------------------------------------------------------- ExoPlayer
class ExoVodEngine implements VodEngine {
  ExoVodEngine() : _backend = GetIt.instance<Media3PlayerBackend>() {
    _subs.add(_backend.firstFrameStream.listen((_) => _first.add(null)));
    _subs.add(_backend.errorStream.listen((e) {
      _errors.add((e['message'] ?? e['error'] ?? e['code'] ?? 'erreur ExoPlayer').toString());
    }));
    _subs.add(_backend.tracksChangedStream.listen((_) => _changed.add(null)));
  }

  final Media3PlayerBackend _backend;
  final _first = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _changed = StreamController<void>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  Completer<void>? _viewReady = Completer<void>();

  static List<VodTrack> _list(List<Map<String, dynamic>> infos) => [
    for (final t in infos)
      if (t['supported'] != false)
        VodTrack('${t['position']}', '${t['language'] ?? ''}', '${t['label'] ?? ''}'),
  ];

  static String? _selected(List<Map<String, dynamic>> infos) =>
      infos.where((t) => t['selected'] == true).map((t) => '${t['position']}').firstOrNull;

  @override
  String get name => 'ExoPlayer';
  @override
  Stream<Duration> get position => _backend.positionStream;
  @override
  Stream<Duration> get duration => _backend.durationStream;
  @override
  Stream<bool> get playing => _backend.playingStream;
  @override
  Stream<bool> get buffering => _backend.bufferingStream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Stream<void> get firstFrame => _first.stream;
  @override
  Stream<void> get tracksChanged => _changed.stream;
  @override
  List<VodTrack> get audio => _list(_backend.audioTrackInfos);
  @override
  List<VodTrack> get subtitles => _list(_backend.textTrackInfos);
  @override
  String? get audioId => _selected(_backend.audioTrackInfos);
  @override
  String? get subtitleId => _selected(_backend.textTrackInfos);

  @override
  Future<void> open(String url, Map<String, String> headers, {Duration start = Duration.zero}) async {
    final ready = _viewReady;
    if (ready != null && !ready.isCompleted) {
      await ready.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    }
    await _backend.play({
      'url': url,
      'headers': headers,
      'isLive': false,
      'mediaType': 'video',
      'autoPlay': true,
    }, startPosition: start);
  }

  @override
  Future<void> seek(Duration position) => _backend.seekTo(position);
  @override
  Future<void> playOrPause() => _backend.isPlaying ? _backend.pause() : _backend.resume();

  @override
  Future<void> setAudio(VodTrack track) async {
    final i = int.tryParse(track.id);
    if (i != null) await _backend.setAudioTrack(i);
  }

  @override
  Future<void> setSubtitle(VodTrack? track) async {
    final i = track == null ? null : int.tryParse(track.id);
    if (i == null) {
      await _backend.disableSubtitleTrack();
    } else {
      await _backend.setSubtitleTrack(i);
    }
  }

  @override
  Future<void> styleSubtitles({required double scale, required bool raised}) async {
    // The viewer's usual subtitle look (Moonfin's settings), resized and lifted.
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<UserPreferences>()) return;
    final style = SubtitleStyle.resolve(getIt<UserPreferences>(), isHdr: false);
    await _backend.configureSubtitleStyle(
      textColor: style.textColor,
      backgroundColor: style.backgroundColor,
      strokeColor: style.strokeColor,
      fontSize: style.fontSize * scale,
      fontWeight: style.fontWeight,
      verticalOffset: raised ? style.verticalOffset + 0.12 : style.verticalOffset,
    );
  }

  @override
  Future<void> setSubtitleDelay(double seconds) => _backend.setSubtitleDelay(seconds);

  @override
  Widget view({required double scale, required bool raised}) => Media3VideoView(
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
    for (final s in _subs) {
      await s.cancel();
    }
    await _first.close();
    await _errors.close();
    await _changed.close();
    try {
      await _backend.stop();
    } catch (_) {}
  }
}

// ------------------------------------------------------------------ browser
class WebVodEngine implements VodEngine {
  WebVodEngine() : _backend = HtmlVideoBackend(GetIt.instance<UserPreferences>()) {
    _subs.add(_backend.positionStream.listen((p) {
      // The browser gives no "first frame" event of its own: time moving on
      // means the picture is there.
      if (!_seen && p > Duration.zero) {
        _seen = true;
        _first.add(null);
      }
    }));
    _subs.add(_backend.errorStream.listen((e) {
      _errors.add((e['message'] ?? e['error'] ?? 'le navigateur ne lit pas ce fichier').toString());
    }));
  }

  final HtmlVideoBackend _backend;
  final _first = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  bool _seen = false;

  @override
  String get name => 'Navigateur';
  @override
  Stream<Duration> get position => _backend.positionStream;
  @override
  Stream<Duration> get duration => _backend.durationStream;
  @override
  Stream<bool> get playing => _backend.playingStream;
  @override
  Stream<bool> get buffering => _backend.bufferingStream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Stream<void> get firstFrame => _first.stream;
  // The browser doesn't list the file's audio and subtitle tracks.
  @override
  Stream<void> get tracksChanged => const Stream.empty();
  @override
  List<VodTrack> get audio => const [];
  @override
  List<VodTrack> get subtitles => const [];
  @override
  String? get audioId => null;
  @override
  String? get subtitleId => null;

  // A <video> can't send headers of its own: Ma TV tells devices apart by
  // address instead.
  @override
  Future<void> open(String url, Map<String, String> headers, {Duration start = Duration.zero}) async {
    _seen = false;
    await _backend.play({'url': url, 'autoPlay': true}, startPosition: start);
  }

  @override
  Future<void> seek(Duration position) => _backend.seekTo(position);
  @override
  Future<void> playOrPause() => _backend.isPlaying ? _backend.pause() : _backend.resume();
  @override
  Future<void> setAudio(VodTrack track) async {}
  @override
  Future<void> setSubtitle(VodTrack? track) async {}
  @override
  Future<void> styleSubtitles({required double scale, required bool raised}) async {}
  @override
  Future<void> setSubtitleDelay(double seconds) async {}

  @override
  Widget view({required double scale, required bool raised}) =>
      ColoredBox(color: Colors.black, child: _backend.buildView());

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _first.close();
    await _errors.close();
    try {
      await _backend.stop();
    } catch (_) {}
    _backend.dispose();
  }
}
