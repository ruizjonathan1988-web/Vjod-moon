import 'dart:async';
import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../auth/repositories/user_repository.dart';
import '../../../ui/navigation/destinations.dart';
import '../seerr_notification_service.dart';
import 'ma_tv.dart';

/// Something Ma TV (IPTV Checker) wants the administrator to know: a night
/// that failed, an account about to expire, a channel none of whose sources
/// work.
class MaTvAlert {
  final String id;
  final String kind;
  final String title;
  final String text;

  const MaTvAlert({required this.id, required this.kind, required this.title, required this.text});
}

/// The alerts of a `/tv/api/alerts` answer; anything malformed is skipped.
List<MaTvAlert> parseMaTvAlerts(Object? json) {
  if (json is! Map || json['alerts'] is! List) return const [];
  return [
    for (final a in json['alerts'] as List)
      if (a is Map && (a['id']?.toString() ?? '').isNotEmpty && (a['title']?.toString() ?? '').isNotEmpty)
        MaTvAlert(
          id: a['id'].toString(),
          kind: a['kind']?.toString() ?? '',
          title: a['title'].toString(),
          text: a['text']?.toString() ?? '',
        ),
  ];
}

/// The alerts not shown yet, given the ids already shown. The ids shown are
/// kept to the last [keep], newest last.
({List<MaTvAlert> fresh, List<String> shown}) newMaTvAlerts(
  List<MaTvAlert> alerts,
  List<String> shown, {
  int keep = 60,
}) {
  final seen = shown.toSet();
  final fresh = [for (final a in alerts) if (!seen.contains(a.id)) a];
  final all = [...shown, for (final a in fresh) a.id];
  return (fresh: fresh, shown: all.length > keep ? all.sublist(all.length - keep) : all);
}

/// Shows Ma TV's alerts as notifications, on an administrator's profile
/// only: once home has settled, then every hour while VJOD is open. Each
/// alert is shown once on this device.
class MaTvAlerts {
  MaTvAlerts._();

  static bool _started = false;
  static const _shownKey = 'vjod_matv_alerts_shown';

  static void start() {
    if (_started) return;
    _started = true;
    Timer(const Duration(seconds: 40), () => unawaited(check()));
    Timer.periodic(const Duration(hours: 1), (_) => unawaited(check()));
  }

  static bool get _isAdmin {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<UserRepository>()) return false;
    return getIt<UserRepository>().currentUser?.isAdministrator ?? false;
  }

  static Future<void> check() async {
    try {
      if (!_isAdmin || !GetIt.instance.isRegistered<SeerrNotificationService>()) return;
      final alerts = await MaTvClient().alerts();
      if (alerts == null || alerts.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      List<String> shown;
      try {
        shown = (jsonDecode(prefs.getString(_shownKey) ?? '[]') as List).map((e) => e.toString()).toList();
      } catch (_) {
        shown = [];
      }
      final next = newMaTvAlerts(alerts, shown);
      if (next.fresh.isEmpty) return;
      await prefs.setString(_shownKey, jsonEncode(next.shown));
      final notify = GetIt.instance<SeerrNotificationService>();
      for (final a in next.fresh) {
        notify.show(a.title, a.text, Destinations.liveTvGuide);
      }
    } catch (_) {
      // Une alerte manquée revient à la prochaine vérification.
    }
  }
}
