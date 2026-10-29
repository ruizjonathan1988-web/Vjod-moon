// Recordings made by Ma TV on the seedbox: it records by itself, the TV can
// be off. A programme from the guide, every airing of a title on a channel,
// or a time range. Kept 7 days unless marked to keep.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ma_tv.dart';

class MaTvRecording {
  final String id;
  final String channelId;
  final String channelName;
  final int? number;
  final String title;
  final String subtitle;
  final DateTime start;
  final DateTime end;

  /// scheduled, recording, done, partial or failed.
  final String status;
  final String rule;
  final bool keep;
  final int size;
  final String message;

  const MaTvRecording({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.title,
    required this.start,
    required this.end,
    required this.status,
    this.number,
    this.subtitle = '',
    this.rule = '',
    this.keep = false,
    this.size = 0,
    this.message = '',
  });

  bool get scheduled => status == 'scheduled';
  bool get recording => status == 'recording';
  bool get failed => status == 'failed';

  /// Something to watch: finished, cut short, or under way.
  bool get playable => size > 0 && (status == 'done' || status == 'partial' || status == 'recording');

  /// Whether this recording covers [start] on [channelId].
  bool covers(String channelId, DateTime start) =>
      this.channelId == channelId && !failed && !start.isBefore(this.start) && start.isBefore(end);

  static DateTime _t(Object? v) =>
      DateTime.fromMillisecondsSinceEpoch(((v is num ? v : num.tryParse('$v') ?? 0) * 1000).round());

  static MaTvRecording? fromJson(Object? j) {
    if (j is! Map || '${j['id'] ?? ''}'.isEmpty) return null;
    return MaTvRecording(
      id: '${j['id']}',
      channelId: '${j['chan'] ?? ''}',
      channelName: '${j['chan_name'] ?? ''}',
      number: j['num'] is num ? (j['num'] as num).toInt() : null,
      title: '${j['title'] ?? ''}',
      subtitle: '${j['sub'] ?? ''}',
      start: _t(j['start']),
      end: _t(j['end']),
      status: '${j['status'] ?? 'scheduled'}',
      rule: '${j['rule'] ?? ''}',
      keep: j['keep'] == true,
      size: j['size'] is num ? (j['size'] as num).toInt() : 0,
      message: '${j['msg'] ?? ''}',
    );
  }
}

/// "Every airing of this title on this channel".
class MaTvRecordingRule {
  final String id;
  final String channelId;
  final String channelName;
  final String title;

  const MaTvRecordingRule({required this.id, required this.channelId, required this.channelName, required this.title});

  static MaTvRecordingRule? fromJson(Object? j) {
    if (j is! Map || '${j['id'] ?? ''}'.isEmpty) return null;
    return MaTvRecordingRule(
      id: '${j['id']}',
      channelId: '${j['chan'] ?? ''}',
      channelName: '${j['chan_name'] ?? ''}',
      title: '${j['title'] ?? ''}',
    );
  }
}

class MaTvRecordings {
  final List<MaTvRecording> items;
  final List<MaTvRecordingRule> rules;
  final int used;
  final int? free;
  final int keepDays;

  const MaTvRecordings({this.items = const [], this.rules = const [], this.used = 0, this.free, this.keepDays = 7});

  /// The scheduled or running recording of the programme starting at [start]
  /// on [channelId], if any.
  MaTvRecording? of(String channelId, DateTime start) =>
      items.where((r) => (r.scheduled || r.recording) && r.covers(channelId, start)).firstOrNull;
}

class MaTvRecorder {
  MaTvRecorder({MaTvClient? client}) : _client = client ?? MaTvClient();

  final MaTvClient _client;
  static const _timeout = Duration(seconds: 10);

  /// The last listing read, so the guide can mark what is scheduled at once.
  static MaTvRecordings? last;

  Future<MaTvRecordings?> list() async {
    final s = _client.server;
    if (s == null) return null;
    try {
      final r = await http.get(s.endpoint('/tv/api/rec')).timeout(_timeout);
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return null;
      final out = MaTvRecordings(
        items: [
          for (final e in (j['items'] is List ? j['items'] as List : const []))
            if (MaTvRecording.fromJson(e) case final x?) x,
        ],
        rules: [
          for (final e in (j['rules'] is List ? j['rules'] as List : const []))
            if (MaTvRecordingRule.fromJson(e) case final x?) x,
        ],
        used: j['used'] is num ? (j['used'] as num).toInt() : 0,
        free: j['free'] is num ? (j['free'] as num).toInt() : null,
        keepDays: j['keep_days'] is num ? (j['keep_days'] as num).toInt() : 7,
      );
      last = out;
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Schedules [start]–[end] on [channelId]; with [series], every airing of
  /// [title] on that channel too. Null when done, else what went wrong.
  Future<String?> add({
    required String channelId,
    required DateTime start,
    required DateTime end,
    String title = '',
    String subtitle = '',
    bool series = false,
  }) async {
    final r = await _post('/tv/api/rec/add', {
      'chan': channelId,
      'start': start.millisecondsSinceEpoch ~/ 1000,
      'end': end.millisecondsSinceEpoch ~/ 1000,
      'title': title,
      'sub': subtitle,
      'series': series,
    });
    if (r == null) return 'Ma TV ne répond pas';
    if (r.$1 == 200) return null;
    final j = r.$2;
    return j is Map && j['error'] != null ? '${j['error']}' : "L'enregistrement n'a pas pu être programmé";
  }

  Future<bool> remove(String id) async => (await _post('/tv/api/rec/delete', {'id': id}))?.$1 == 200;

  Future<bool> keep(String id, bool keep) async =>
      (await _post('/tv/api/rec/keep', {'id': id, 'keep': keep}))?.$1 == 200;

  Future<bool> removeRule(String id) async => (await _post('/tv/api/rec/rule/delete', {'id': id}))?.$1 == 200;

  /// The file of a recording, with seeking.
  Uri? playUri(MaTvRecording r) => _client.server?.endpoint('/tv/rec/${r.id}.ts');

  Future<(int, Object?)?> _post(String path, Map<String, Object?> body) async {
    final s = _client.server;
    if (s == null) return null;
    try {
      final r = await http
          .post(s.endpoint(path), headers: const {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_timeout);
      Object? j;
      try {
        j = jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {}
      return (r.statusCode, j);
    } catch (_) {
      return null;
    }
  }
}
