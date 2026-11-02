// VJOD tells Ma TV what goes wrong on each device: crashes (Dart, and the
// native exits Android recorded), and channels or films that would not play.
// The admin sees them grouped on the Ma TV page and gets a phone alert for a
// new crash, instead of guessing from a photo of the screen.
//
// Reports wait on the device (SharedPreferences, 30 at most, a week at most)
// until Ma TV answers, so a crash that kills the app is sent at the next
// launch. The IPTV key, accounts and passwords are taken out of every text.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../preference/user_preferences.dart';
import '../../../util/vjod_build.dart';
import '../../../util/vjod_log.dart';
import 'tv_sources.dart';

/// One thing that went wrong, as Ma TV stores it (`/tv/api/report`).
@immutable
class MaTvReport {
  /// `crash`, `error` or `play`.
  final String kind;
  final String message;
  final String stack;

  /// Where in VJOD: `flutter`, `android`, `tv`, `iptv`…
  final String where;
  final String channel;
  final String title;
  final String player;
  final String source;
  final int at;

  MaTvReport({
    required this.kind,
    required this.message,
    this.stack = '',
    this.where = '',
    this.channel = '',
    this.title = '',
    this.player = '',
    this.source = '',
    int? at,
  }) : at = at ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'message': message,
    if (stack.isNotEmpty) 'stack': stack,
    if (where.isNotEmpty) 'where': where,
    if (channel.isNotEmpty) 'channel': channel,
    if (title.isNotEmpty) 'title': title,
    if (player.isNotEmpty) 'player': player,
    if (source.isNotEmpty) 'source': source,
    'at': at,
  };

  static MaTvReport? fromJson(Object? j) {
    if (j is! Map) return null;
    final m = j.cast<String, dynamic>();
    final message = m['message']?.toString() ?? '';
    if (message.isEmpty) return null;
    return MaTvReport(
      kind: m['kind']?.toString() ?? 'error',
      message: message,
      stack: m['stack']?.toString() ?? '',
      where: m['where']?.toString() ?? '',
      channel: m['channel']?.toString() ?? '',
      title: m['title']?.toString() ?? '',
      player: m['player']?.toString() ?? '',
      source: m['source']?.toString() ?? '',
      at: (m['at'] as num?)?.toInt(),
    );
  }

  /// The same report with the IPTV secrets taken out and the texts cut to
  /// what Ma TV keeps.
  MaTvReport redacted() => MaTvReport(
    kind: kind,
    message: _cut(redactIptvSecrets(message), 500),
    stack: _cut(redactIptvSecrets(stack), 4000),
    where: where,
    channel: channel,
    title: title,
    player: player,
    source: _cut(redactIptvSecrets(source), 120),
    at: at,
  );

  static String _cut(String s, int n) => s.length > n ? s.substring(0, n) : s;
}

class MaTvReports {
  MaTvReports._();
  static final MaTvReports instance = MaTvReports._();

  static const storageKey = 'vjod_matv_reports';
  static const deviceKey = 'vjod_device_id';
  static const maxStored = 30;
  static const maxAge = Duration(days: 7);

  /// Same problem within a launch: once is enough (a broken widget throws at
  /// every frame).
  final Set<String> _seen = <String>{};
  Timer? _debounce;
  bool _sending = false;

  /// Writes one after the other: two errors at once must not each read the
  /// list and lose the other's.
  Future<void> _writes = Future<void>.value();
  Map<String, String>? _device;

  /// Overridable in tests.
  @visibleForTesting
  http.Client? httpClient;
  @visibleForTesting
  TvSourcesServer? Function() serverOf = () => TvSourcesClient().server;
  @visibleForTesting
  Duration debounce = const Duration(seconds: 4);

  /// Off when the household turned crash reports off in the settings.
  bool get _allowed {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<UserPreferences>()) return true;
    try {
      return getIt<UserPreferences>().get(UserPreferences.crashReportsEnabled);
    } catch (_) {
      return true;
    }
  }

  /// An uncaught Dart error.
  void crash(Object error, StackTrace? stack, {String where = 'flutter'}) {
    final first = error.toString().split('\n').first;
    report(MaTvReport(
      kind: 'crash',
      message: error.toString(),
      stack: _frames(stack),
      where: where,
    ), key: 'crash|$first');
  }

  /// A channel, film or episode that would not play.
  void play(String message, {String where = 'tv', String channel = '', String title = '', String player = '', String source = ''}) {
    report(MaTvReport(
      kind: 'play',
      message: message,
      where: where,
      channel: channel,
      title: title,
      player: player,
      source: source,
    ), key: 'play|$where|$channel|$title|$message');
  }

  /// Keeps [r] and sends it shortly (it waits on the device if Ma TV can't
  /// be reached). Never throws.
  void report(MaTvReport r, {String? key}) {
    try {
      if (!_allowed) return;
      if (!_seen.add(key ?? '${r.kind}|${r.where}|${r.message}')) return;
      if (_seen.length > 200) _seen.clear();
      final clean = r.redacted();
      _writes = _writes.then((_) => _store(clean));
    } catch (_) {
      // Reporting must never become a second crash.
    }
  }

  Future<void> _store(MaTvReport r) async {
    try {
      final list = await pending();
      list.add(r);
      while (list.length > maxStored) {
        list.removeAt(0);
      }
      await _save(list);
      _debounce?.cancel();
      _debounce = Timer(debounce, () => unawaited(flush()));
    } catch (_) {}
  }

  /// What waits on the device, oldest first, without what is too old.
  Future<List<MaTvReport>> pending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch ~/ 1000;
      return [
        for (final j in (jsonDecode(raw) as List))
          if (MaTvReport.fromJson(j) case final r? when r.at >= cutoff) r,
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<MaTvReport> list) async {
    final prefs = await SharedPreferences.getInstance();
    if (list.isEmpty) {
      await prefs.remove(storageKey);
    } else {
      await prefs.setString(storageKey, jsonEncode([for (final r in list) r.toJson()]));
    }
  }

  /// Sends what waits to Ma TV; removes it once Ma TV took it. Returns how
  /// many were sent.
  Future<int> flush() async {
    if (_sending || !_allowed) return 0;
    final server = serverOf();
    if (server == null) return 0;
    _sending = true;
    try {
      final list = await pending();
      if (list.isEmpty) return 0;
      final who = await _who();
      final batch = list.take(20).toList();
      final body = jsonEncode({
        'reports': [for (final r in batch) {...who, ...r.toJson()}],
      });
      final uri = server.endpoint('/tv/api/report');
      final client = httpClient;
      final res = await (client != null
              ? client.post(uri, headers: {'Content-Type': 'application/json'}, body: body)
              : http.post(uri, headers: {'Content-Type': 'application/json'}, body: body))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return 0;
      // Ma TV may refuse some (a device that sends too much): they are not
      // retried, the rest of the batch is done either way.
      final left = (await pending()).where((r) => !batch.any((b) => b.at == r.at && b.message == r.message)).toList();
      await _save(left);
      if (left.isNotEmpty) {
        _debounce?.cancel();
        _debounce = Timer(debounce, () => unawaited(flush()));
      }
      return batch.length;
    } catch (_) {
      return 0;
    } finally {
      _sending = false;
    }
  }

  /// Which device, which VJOD, which profile: what the Ma TV page shows.
  Future<Map<String, String>> _who() async {
    final cached = _device;
    final base = cached ?? await _deviceInfo();
    _device = base;
    final profile = maTvReportProfile?.call() ?? '';
    return {
      ...base,
      'app': VjodBuild.version,
      if (VjodBuild.commit.isNotEmpty) 'build': VjodBuild.commit,
      if (profile.isNotEmpty) 'profile': profile,
    };
  }

  Future<Map<String, String>> _deviceInfo() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(deviceKey) ?? '';
    if (id.isEmpty) {
      final rnd = Random.secure();
      id = List.generate(12, (_) => rnd.nextInt(36).toRadixString(36)).join();
      await prefs.setString(deviceKey, id);
    }
    var model = '', os = '';
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final a = await DeviceInfoPlugin().androidInfo;
        model = '${a.manufacturer} ${a.model}'.trim();
        os = 'Android ${a.version.release}';
      } else if (kIsWeb) {
        model = 'Navigateur';
        os = 'web';
      } else {
        os = defaultTargetPlatform.name;
      }
    } catch (_) {}
    return {'device': id, if (model.isNotEmpty) 'model': model, if (os.isNotEmpty) 'os': os};
  }

  static String _frames(StackTrace? stack) {
    if (stack == null) return '';
    final lines = stack.toString().split('\n').where((l) => l.trim().isNotEmpty).take(25);
    return lines.join('\n');
  }
}

/// The name of the profile in use, set by the app once a user is signed in.
String Function()? maTvReportProfile;
