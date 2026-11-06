// VJOD 4.28: « Nouvel épisode » for the shows followed in the replay. On the
// phone, a notification once per new episode (one for several at once);
// the TV keeps the badge on « Mes émissions ». The first look on a device
// only notes what is there, so nothing old pops up.
import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../util/platform_detection.dart';
import '../seerr_notification_service.dart';
import 'ma_tv_replay.dart';

/// What to say for [fresh] new episodes, or null.
({String title, String body})? replayAlertText(List<ReplayItem> fresh) {
  if (fresh.isEmpty) return null;
  if (fresh.length == 1) {
    final e = fresh.single;
    return (title: 'Nouvel épisode : ${e.show}', body: e.title.isNotEmpty && e.title != e.show ? e.title : 'Au replay, dans « Mes émissions »');
  }
  final shows = {for (final e in fresh) e.show}.toList();
  return (
    title: '${fresh.length} nouveaux épisodes',
    body: shows.length <= 3 ? shows.join(', ') : '${shows.take(3).join(', ')} et ${shows.length - 3} autre${shows.length - 3 > 1 ? 's' : ''}',
  );
}

class ReplayAlerts {
  ReplayAlerts._();

  static const _key = 'vjod_replay_alerted';
  static const route = '/replay/mes-emissions';
  static bool _started = false;

  /// Every 30 minutes while VJOD is open, on the phone.
  static void start() {
    if (_started || PlatformDetection.isTV) return;
    _started = true;
    Timer(const Duration(minutes: 1), () => unawaited(check()));
    Timer.periodic(const Duration(minutes: 30), (_) => unawaited(check()));
  }

  static Future<void> check() async {
    final home = await MaTvReplay().home().timeout(const Duration(seconds: 20), onTimeout: () => null);
    if (home != null) await note(home);
  }

  /// The episodes of [home] not told yet; tells them on the phone.
  static Future<List<ReplayItem>> note(ReplayHome home, {bool notify = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final first = !prefs.containsKey(_key);
      final told = <String>{...?prefs.getStringList(_key)};
      final fresh = [for (final e in home.mine) if (e.isNew && !told.contains(e.id)) e];
      if (fresh.isEmpty && !first) return const [];
      final keep = [...told, for (final e in fresh) e.id];
      await prefs.setStringList(_key, keep.length > 300 ? keep.sublist(keep.length - 300) : keep);
      if (first) return const [];
      final text = replayAlertText(fresh);
      if (notify && text != null && !PlatformDetection.isTV && GetIt.instance.isRegistered<SeerrNotificationService>()) {
        GetIt.instance<SeerrNotificationService>().show(text.title, text.body, route);
      }
      return fresh;
    } catch (_) {
      return const [];
    }
  }
}
