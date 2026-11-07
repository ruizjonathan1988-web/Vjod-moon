// Media3, Android's own player, is the default on Android: it decodes on the
// box's video chip, passes HDR and surround sound through, and keeps the box
// cool. On some boxes it stutters or crashes on a format their decoder handles
// badly (the Wowlink stuttered on « Tous en scène 2 », the XGIMI crashed on an
// IPTV programme, while VLC played both). This remembers, on this device, the
// formats Media3 failed on, and plays them with mpv from then on.
//
// Two signs count as a failure:
//  * stutter: Media3 reports dropped frames in bursts while playing;
//  * a native crash while Media3 was playing (Android keeps the state, read at
//    the next launch).
import 'package:playback_core/playback_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Media3Fallback {
  Media3Fallback._();

  static final instance = Media3Fallback._();

  static const avoidKey = 'vjod_media3_avoid';
  static const lastKey = 'vjod_media3_last_format';

  /// At most this many formats are remembered; the oldest go first.
  static const maxRemembered = 30;

  /// A burst counts when at least this many frames were dropped within
  /// [burstWindowMs]. Media3 also reports a handful dropped at a seek or a
  /// stop, which stay under it.
  static const burstFrames = 40;
  static const burstWindowMs = 30000;

  /// Bursts in one film before switching to mpv.
  static const burstsToSwitch = 2;

  Set<String> _avoided = {};
  bool _loaded = false;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _avoided = {...?prefs.getStringList(avoidKey)};
      _loaded = true;
    } catch (_) {}
  }

  bool get loaded => _loaded;
  Set<String> get avoided => Set.unmodifiable(_avoided);

  /// Whether [resolution] should skip Media3 on this device.
  bool avoids(StreamResolutionResult resolution) =>
      _avoided.contains(formatKey(resolution.mediaStreams, resolution.selectedAudioStreamIndex));

  /// Media3 failed on [key]: play it with mpv from now on.
  Future<void> avoid(String key) async {
    _avoided = {..._avoided, key};
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = [...?prefs.getStringList(avoidKey)]..remove(key);
      list.add(key);
      while (list.length > maxRemembered) {
        list.removeAt(0);
      }
      await prefs.setStringList(avoidKey, list);
    } catch (_) {}
  }

  /// Media3 starts playing [key]: kept so a native crash, read at the next
  /// launch, knows which format it was.
  Future<void> playing(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastKey, key);
    } catch (_) {}
  }

  /// The previous run died in native code while Media3 was playing: that
  /// format goes to mpv. Returns the format, or null when nothing was marked.
  Future<String?> afterExit(Map<String, Object?> exit) async {
    if (!isMedia3NativeCrash(exit)) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString(lastKey);
      if (key == null || key.isEmpty) return null;
      await avoid(key);
      return key;
    } catch (_) {
      return null;
    }
  }

  /// « hevc/HDR10/eac3 »: the video codec, its range, and the audio codec
  /// being played. A source with no stream info (some IPTV films) reads
  /// « ?/?/? », so one crash there moves the other unknown ones to mpv too.
  static String formatKey(List<Map<String, dynamic>> streams, int? audioIndex) {
    String low(Object? v) => (v?.toString() ?? '').trim().toLowerCase();
    Map<String, dynamic>? video;
    Map<String, dynamic>? audio;
    for (final s in streams) {
      final type = low(s['Type']);
      if (type == 'video' && video == null) video = s;
      if (type == 'audio') {
        if (audioIndex != null && s['Index'] == audioIndex) audio = s;
        audio ??= s;
      }
    }
    String part(String v) => v.isEmpty ? '?' : v;
    final range = video == null ? '' : (video['VideoRangeType'] ?? video['VideoRange'] ?? '').toString().trim();
    return '${part(low(video?['Codec']))}/${part(range)}/${part(low(audio?['Codec']))}';
  }

  /// A native crash Android recorded while Media3 drew the main picture.
  static bool isMedia3NativeCrash(Map<String, Object?> exit) {
    final reason = exit['reason']?.toString() ?? '';
    final state = exit['state']?.toString() ?? '';
    return reason.contains('native crash') && state.contains('media3-main');
  }
}

/// Counts dropped-frame bursts in one film.
class StutterWatch {
  int _bursts = 0;
  bool _done = false;

  /// One report from Media3: [count] frames dropped over [elapsedMs].
  /// True once, when the film has stuttered enough to switch.
  bool add(int count, int elapsedMs) {
    if (_done) return false;
    if (count >= Media3Fallback.burstFrames && elapsedMs <= Media3Fallback.burstWindowMs) _bursts++;
    if (_bursts >= Media3Fallback.burstsToSwitch) {
      _done = true;
      return true;
    }
    return false;
  }
}
