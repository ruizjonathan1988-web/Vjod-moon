// What the IPTV player needs to chain the episodes of a series read from the
// provider: the episode after the one playing, and how long this series'
// opening credits last (learned from the viewer's own jumps, since a provider
// file carries no chapter marks).
import 'package:shared_preferences/shared_preferences.dart';

import 'xtream_catalog.dart';

/// The episode after [season] / [number] (or the one whose id is [id]), in the
/// order of the seasons; null after the last one or when it isn't found.
XtreamEpisode? episodeAfter(XtreamSeriesInfo info, {required int season, required int number, String id = ''}) {
  final all = [for (final s in info.seasonNumbers) ...?info.seasons[s]];
  var i = id.isEmpty ? -1 : all.indexWhere((e) => e.id == id);
  if (i < 0) i = all.indexWhere((e) => e.season == season && e.number == number);
  if (i < 0 || i + 1 >= all.length) return null;
  return all[i + 1];
}

/// How far « Passer le générique » jumps, per series. 1 min 25 at first; when
/// the viewer corrects the jump just after it (a few seconds back or forth),
/// the corrected length is kept for the next episodes.
class IptvIntroSkip {
  IptvIntroSkip._();

  static const defaultLength = Duration(seconds: 85);
  static const _min = Duration(seconds: 15);
  static const _max = Duration(minutes: 4);

  static String _key(String seriesId) => 'vjod_iptv_intro_$seriesId';

  static Future<Duration> lengthFor(String seriesId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getInt(_key(seriesId));
      if (s != null) return Duration(seconds: s);
    } catch (_) {}
    return defaultLength;
  }

  /// The length to keep after a jump then a correction; null when the
  /// correction makes no sense (gone back before the jump, or far too long).
  static Duration? corrected(Duration jumpedFrom, Duration landedAt) {
    final len = landedAt - jumpedFrom;
    if (len < _min || len > _max) return null;
    return len;
  }

  static Future<void> remember(String seriesId, Duration length) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_key(seriesId), length.inSeconds);
    } catch (_) {}
  }
}
