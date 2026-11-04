// VJOD 4.27: « Le mois à la maison », from the Playback Reporting plugin of
// Jellyfin: hours watched by each profile, the most watched series and
// films of the last 30 days. Jellyfin only answers an administrator.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class WatchMonth {
  /// Profile → hours, the most first.
  final List<(String, double)> people;

  /// Series → hours, the most first (at most 8).
  final List<(String, double)> series;

  /// Films → hours, the most first (at most 8).
  final List<(String, double)> films;
  final double totalHours;

  const WatchMonth({this.people = const [], this.series = const [], this.films = const [], this.totalHours = 0});

  bool get isEmpty => totalHours <= 0;

  static const query =
      "SELECT UserId, ItemType, ItemName, SUM(PlayDuration) FROM PlaybackActivity "
      "WHERE DateCreated >= datetime('now', '-30 days') GROUP BY UserId, ItemType, ItemName";

  /// « Malcolm - s07e20 - Le grand jour » → « Malcolm ».
  static String seriesOf(String name) {
    final m = RegExp(r'^(.*?)\s+-\s+s\d+e\d+', caseSensitive: false).firstMatch(name);
    if (m != null) return m.group(1)!.trim();
    final dash = name.indexOf(' - ');
    return dash > 0 ? name.substring(0, dash).trim() : name.trim();
  }

  /// From the plugin's answer: {colums: [...], results: [[user, type, name, seconds], ...]}.
  factory WatchMonth.fromRows(List<List<Object?>> rows) {
    final people = <String, double>{};
    final series = <String, double>{};
    final films = <String, double>{};
    var total = 0.0;
    for (final r in rows) {
      if (r.length < 4) continue;
      final h = (double.tryParse('${r[3]}') ?? 0) / 3600;
      if (h <= 0) continue;
      final who = '${r[0] ?? ''}'.trim();
      final type = '${r[1] ?? ''}';
      final name = '${r[2] ?? ''}'.trim();
      total += h;
      if (who.isNotEmpty) people[who] = (people[who] ?? 0) + h;
      if (name.isEmpty) continue;
      if (type == 'Episode') {
        final s = seriesOf(name);
        series[s] = (series[s] ?? 0) + h;
      } else if (type == 'Movie') {
        films[name] = (films[name] ?? 0) + h;
      }
    }
    List<(String, double)> top(Map<String, double> m, int n) =>
        (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(n).map((e) => (e.key, e.value)).toList();
    return WatchMonth(people: top(people, 20), series: top(series, 8), films: top(films, 8), totalHours: total);
  }

  /// « 12 h 30 », « 45 min ».
  static String hours(double h) {
    final m = (h * 60).round();
    if (m < 60) return '$m min';
    return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
  }

  /// Asks Jellyfin; null with [error] set when it can't.
  static Future<(WatchMonth?, String)> load({required String baseUrl, required String token, http.Client? client}) async {
    final uri = Uri.parse('$baseUrl/user_usage_stats/submit_custom_query');
    final body = jsonEncode({'CustomQueryString': query, 'ReplaceUserId': true});
    final headers = {'Content-Type': 'application/json', 'X-Emby-Token': token, 'Accept': 'application/json'};
    try {
      final r = await (client?.post(uri, headers: headers, body: body) ?? http.post(uri, headers: headers, body: body))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 404) return (null, 'Le module Playback Reporting n’est pas installé sur Jellyfin.');
      if (r.statusCode == 401 || r.statusCode == 403) return (null, 'Réservé aux administrateurs de Jellyfin.');
      if (r.statusCode != 200) return (null, 'Jellyfin a répondu ${r.statusCode}.');
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final rows = j is Map ? (j['results'] as List? ?? const []) : const [];
      return (WatchMonth.fromRows([for (final x in rows) if (x is List) List<Object?>.from(x)]), '');
    } on TimeoutException {
      return (null, 'Jellyfin n’a pas répondu à temps.');
    } catch (e) {
      return (null, 'Lecture impossible : $e');
    }
  }
}
