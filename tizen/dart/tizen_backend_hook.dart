// The Samsung build's version of lib/playback/tizen_backend_hook.dart, copied
// over it by samsung-essai.yml. Video goes through video_player, whose
// Samsung implementation (video_player_tizen) drives the TV's AVPlay player,
// which decodes in hardware. Adapted from the experimental Tizen backend of a
// Moonfin fork.
//
// What the TV player can't do here (the server makes up for it by choosing
// tracks and transcoding): change audio or subtitle track while playing,
// picture subtitles, subtitle styling and delays.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:playback_core/playback_core.dart';
import 'package:video_player/video_player.dart';

import '../preference/user_preferences.dart';
import 'html_video_backend_profile.dart';

PlayerBackend? createTizenBackend(UserPreferences prefs) => TizenPlayerBackend(prefs);

Widget? tizenVideoView(PlayerBackend? backend) {
  if (backend is! TizenPlayerBackend) return null;
  final controller = backend.controller;
  if (controller == null) return const ColoredBox(color: Color(0xFF000000));
  return ColoredBox(
    color: const Color(0xFF000000),
    child: Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    ),
  );
}

class TizenPlayerBackend extends PlayerBackend {
  TizenPlayerBackend(this._prefs);

  final UserPreferences _prefs;
  VideoPlayerController? _controller;
  VideoPlayerController? get controller => _controller;

  final _positionCtl = StreamController<Duration>.broadcast();
  final _durationCtl = StreamController<Duration>.broadcast();
  final _bufferCtl = StreamController<Duration>.broadcast();
  final _playingCtl = StreamController<bool>.broadcast();
  final _bufferingCtl = StreamController<bool>.broadcast();
  final _completedCtl = StreamController<bool>.broadcast();
  final _errorCtl = StreamController<Map<String, dynamic>>.broadcast();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  double _speed = 1.0;
  bool _completedEmitted = false;
  bool _isDisposed = false;

  void _onValue() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (value.position != _position) {
      _position = value.position;
      _positionCtl.add(_position);
    }
    if (value.duration != _duration) {
      _duration = value.duration;
      _durationCtl.add(_duration);
    }
    final buffered = value.buffered.isNotEmpty ? value.buffered.last.end : Duration.zero;
    if (buffered != _buffer) {
      _buffer = buffered;
      _bufferCtl.add(_buffer);
    }
    if (value.isPlaying != _isPlaying) {
      _isPlaying = value.isPlaying;
      _playingCtl.add(_isPlaying);
    }
    if (value.isBuffering != _isBuffering) {
      _isBuffering = value.isBuffering;
      _bufferingCtl.add(_isBuffering);
    }
    final reachedEnd = value.duration > Duration.zero && value.position >= value.duration && !value.isPlaying;
    if (reachedEnd) {
      if (!_completedEmitted) {
        _completedEmitted = true;
        _completedCtl.add(true);
      }
    } else {
      _completedEmitted = false;
    }
    if (value.hasError) {
      _errorCtl.add(<String, dynamic>{'message': value.errorDescription ?? 'Tizen playback error'});
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    controller.removeListener(_onValue);
    try {
      await controller.dispose();
    } catch (_) {}
  }

  @override
  Future<void> play(dynamic mediaItem, {Duration startPosition = Duration.zero}) async {
    final url = mediaItem is String ? mediaItem : (mediaItem is Map ? mediaItem['url']?.toString() ?? '' : '');
    if (url.isEmpty) return;
    await _disposeController();
    if (_isDisposed) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    _completedEmitted = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _buffer = Duration.zero;
    controller.addListener(_onValue);
    await controller.initialize();
    if (_isDisposed) {
      await _disposeController();
      return;
    }
    if (startPosition > Duration.zero) await controller.seekTo(startPosition);
    await controller.setPlaybackSpeed(_speed);
    await controller.play();
    _onValue();
  }

  @override
  Future<void> resume() async => _controller?.play();
  @override
  Future<void> pause() async => _controller?.pause();
  @override
  Future<void> stop() async {
    await _controller?.pause();
    await _disposeController();
  }

  @override
  Future<void> seekTo(Duration position) async => _controller?.seekTo(position);

  @override
  Duration get position => _controller?.value.position ?? _position;
  @override
  Duration get duration => _controller?.value.duration ?? _duration;
  @override
  Duration get buffer => _buffer;
  @override
  bool get isPlaying => _controller?.value.isPlaying ?? _isPlaying;
  @override
  bool get isBuffering => _controller?.value.isBuffering ?? _isBuffering;
  @override
  double get playbackSpeed => _speed;

  @override
  Stream<Duration> get positionStream => _positionCtl.stream;
  @override
  Stream<Duration> get durationStream => _durationCtl.stream;
  @override
  Stream<Duration> get bufferStream => _bufferCtl.stream;
  @override
  Stream<bool> get playingStream => _playingCtl.stream;
  @override
  Stream<bool> get bufferingStream => _bufferingCtl.stream;
  @override
  Stream<bool> get completedStream => _completedCtl.stream;
  @override
  Stream<Map<String, dynamic>>? get errorStream => _errorCtl.stream;

  // Step 1: the browser's conservative profile (H.264 and AAC played as is,
  // the rest transcoded by the server). The TV can do more (HEVC, 4K); a
  // Samsung profile comes once playback is confirmed on the set.
  @override
  Map<String, dynamic> getDeviceProfile({bool useProgressiveTranscode = false}) =>
      buildHtmlVideoBackendDeviceProfile(_prefs, useProgressiveTranscode: useProgressiveTranscode);

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _speed = speed;
    await _controller?.setPlaybackSpeed(speed);
  }

  @override
  Future<void> setAudioTrack(int index) async {}
  @override
  Future<void> setSubtitleTrack(
    int index, {
    bool isBitmapSubtitle = false,
    String? subtitleCodec,
    bool isExternalSubtitle = false,
    String? externalSubtitleUrl,
  }) async {}
  @override
  Future<void> disableSubtitleTrack() async {}
  @override
  Future<void> waitForTracksReady() async {}
  @override
  Future<void> waitForEmbeddedSubtitleCount(int count) async {}
  @override
  Future<void> setVolume(double volume) async =>
      _controller?.setVolume((volume / 100.0).clamp(0.0, 1.0));
  @override
  Future<void> setAudioDelay(double seconds) async {}
  @override
  Future<void> setSubtitleDelay(double seconds) async {}
  @override
  Future<void> addExternalSubtitle(String url, {String? title, String? language, String? codec}) async {}
  @override
  Future<void> configureSubtitleStyle({
    int? textColor,
    int? backgroundColor,
    int? strokeColor,
    double? fontSize,
    int? fontWeight,
    double? verticalOffset,
  }) async {}
  @override
  Future<void> setSubtitleRendererMode(SubtitleRendererMode mode) async {}

  @override
  bool get supportsRuntimeTrackSelection => false;
  @override
  bool get nativelyHandlesStartPosition => true;
  @override
  bool get canRenderBitmapSubtitles => false;
  @override
  bool get demuxesEmbeddedSubtitles => false;

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_disposeController());
    _positionCtl.close();
    _durationCtl.close();
    _bufferCtl.close();
    _playingCtl.close();
    _bufferingCtl.close();
    _completedCtl.close();
    _errorCtl.close();
  }
}
