import 'package:playback_core/playback_core.dart';

import '../data/repositories/offline_repository.dart';

/// Decorates the server play-session service so local-file playback keeps the
/// downloads DB position current (the source of truth for offline resume) and
/// only talks to the server when it's reachable.
///
/// The manager fires these callbacks unawaited, so server failures while
/// offline must be swallowed here. The sync service flushes the locally
/// recorded progress on reconnect.
class LocalAwarePlayerService implements PlayerService {
  final PlayerService _inner;
  final OfflineRepository _offlineRepo;
  final bool Function() _canReachServer;

  /// Told which item stopped once its stop has been reported, so whatever
  /// reacts to a finished episode reads the server's played state after it.
  final void Function(dynamic mediaItem)? _onStopped;

  /// Told when playback of an item starts, and where it stops, to keep the
  /// journal of evenings.
  final void Function(dynamic mediaItem, int? positionTicks)? _onSessionStart;
  final void Function(dynamic mediaItem, Duration position)? _onSessionStop;

  LocalAwarePlayerService(
    this._inner,
    this._offlineRepo, {
    required bool Function() canReachServer,
    void Function(dynamic mediaItem)? onStopped,
    void Function(dynamic mediaItem, int? positionTicks)? onSessionStart,
    void Function(dynamic mediaItem, Duration position)? onSessionStop,
  }) : _canReachServer = canReachServer,
       _onStopped = onStopped,
       _onSessionStart = onSessionStart,
       _onSessionStop = onSessionStop;

  void _notify(void Function() call) {
    try {
      call();
    } catch (_) {}
  }

  Future<void> _recordLocal(dynamic mediaItem, int positionTicks) async {
    try {
      final itemId = MediaStreamResolver.extractItemId(mediaItem);
      await _offlineRepo.updatePlaybackPosition(itemId, positionTicks);
    } catch (_) {}
  }

  Future<void> _forward(Future<void> Function() report) async {
    if (!_canReachServer()) return;
    try {
      await report();
    } catch (_) {}
  }

  @override
  Future<void> onPlaybackStart(
    dynamic mediaItem,
    StreamResolutionResult resolution, {
    int? positionTicks,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    if (_onSessionStart case final onStart?) {
      _notify(() => onStart(mediaItem, positionTicks));
    }
    if (!resolution.isLocalMedia) {
      return _inner.onPlaybackStart(
        mediaItem,
        resolution,
        positionTicks: positionTicks,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );
    }
    await _forward(
      () => _inner.onPlaybackStart(
        mediaItem,
        resolution,
        positionTicks: positionTicks,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      ),
    );
  }

  @override
  Future<void> onPlaybackProgress(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool isPaused = false,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? volumeLevel,
    bool? isMuted,
  }) async {
    if (!resolution.isLocalMedia) {
      return _inner.onPlaybackProgress(
        mediaItem,
        resolution,
        position,
        isPaused: isPaused,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
        volumeLevel: volumeLevel,
        isMuted: isMuted,
      );
    }
    await _recordLocal(mediaItem, position.inMicroseconds * 10);
    await _forward(
      () => _inner.onPlaybackProgress(
        mediaItem,
        resolution,
        position,
        isPaused: isPaused,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
        volumeLevel: volumeLevel,
        isMuted: isMuted,
      ),
    );
  }

  @override
  Future<void> onPlaybackStop(
    dynamic mediaItem,
    StreamResolutionResult resolution,
    Duration position, {
    bool releaseLiveStream = true,
  }) async {
    if (_onSessionStop case final onStop?) {
      _notify(() => onStop(mediaItem, position));
    }
    try {
      if (!resolution.isLocalMedia) {
        return await _inner.onPlaybackStop(
          mediaItem,
          resolution,
          position,
          releaseLiveStream: releaseLiveStream,
        );
      }
      await _recordLocal(mediaItem, position.inMicroseconds * 10);
      await _forward(
        () => _inner.onPlaybackStop(
          mediaItem,
          resolution,
          position,
          releaseLiveStream: releaseLiveStream,
        ),
      );
    } finally {
      _onStopped?.call(mediaItem);
    }
  }

  @override
  Future<void> closeLiveStream(String liveStreamId) =>
      _inner.closeLiveStream(liveStreamId);

  @override
  Future<void> stopTranscoding(StreamResolutionResult resolution) async {
    if (resolution.isLocalMedia) return;
    return _inner.stopTranscoding(resolution);
  }

  @override
  void dispose() => _inner.dispose();
}
