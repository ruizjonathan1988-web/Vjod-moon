// « Signaler un problème » by WhatsApp, from anywhere it helps: the settings,
// the TV player's menu, a film that won't start. The message comes prefilled
// with what VJOD knows (what is on screen, the last problem it noted, the
// version, the device and its number on the Ma TV page), so the admin knows
// at once what the person is talking about. The number is set on the seedbox
// (Ma TV), never written into the app.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:server_core/server_core.dart' show DeviceInfo;

import '../../../data/services/vjod/ma_tv_reports.dart';
import '../../../data/services/vjod/tv_sources.dart';
import '../../../util/platform_detection.dart';
import '../../../util/vjod_build.dart';
import '../../../util/vjod_text.dart';
import '../support_dialog.dart';

/// The admin's WhatsApp number from Ma TV, once known (null: none set, or
/// Ma TV not reached). The buttons stay hidden without it.
final ValueNotifier<String?> vjodSupportNumber = ValueNotifier<String?>(null);
DateTime? _askedAt;

/// Asks Ma TV for the number (at most every 10 minutes).
Future<String?> loadSupportNumber() async {
  final now = DateTime.now();
  if (vjodSupportNumber.value != null) return vjodSupportNumber.value;
  if (_askedAt != null && now.difference(_askedAt!) < const Duration(minutes: 10)) return null;
  _askedAt = now;
  final server = TvSourcesClient().server;
  if (server == null) return null;
  try {
    final r = await http.get(server.endpoint('/tv/api/support')).timeout(const Duration(seconds: 6));
    if (r.statusCode != 200) return null;
    final json = jsonDecode(utf8.decode(r.bodyBytes));
    final n = json is Map ? (json['whatsapp'] ?? '').toString().trim() : '';
    if (n.isNotEmpty) vjodSupportNumber.value = n;
    return n.isEmpty ? null : n;
  } catch (_) {
    return null;
  }
}

/// The prefilled message. [what] says what was on screen (« Chaîne 1 TF1 »,
/// « Film : Dune »); [last] is the last problem noted on the device, shown
/// when it is recent.
@visibleForTesting
String reportProblemText({
  required String intro,
  String what = '',
  MaTvReport? last,
  required String version,
  required String device,
  String deviceId = '',
  DateTime? now,
}) {
  final lines = <String>[intro, '', ''];
  if (what.isNotEmpty) lines.add('— $what');
  final at = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last.at * 1000);
  final n = now ?? DateTime.now();
  if (last != null && at != null && n.difference(at) < const Duration(hours: 24)) {
    final mins = n.difference(at).inMinutes;
    final ago = mins < 1 ? 'à l’instant' : (mins < 60 ? 'il y a $mins min' : 'il y a ${mins ~/ 60} h');
    final kind = switch (last.kind) { 'crash' => 'plantage', 'play' => 'lecture ratée', _ => 'erreur' };
    var msg = last.message.split('\n').first.trim();
    if (msg.length > 120) msg = '${msg.substring(0, 117)}…';
    final where = [last.channel, last.title].where((s) => s.isNotEmpty).join(' · ');
    lines.add('— Dernier souci noté : $kind${where.isEmpty ? '' : ' ($where)'}, $ago : $msg');
  }
  lines.add('— VJOD $version · $device');
  if (deviceId.isNotEmpty) lines.add('— Appareil $deviceId (page Ma TV)');
  return lines.join('\n');
}

/// Opens WhatsApp with the message (a QR code to scan on a TV). False when no
/// number is set on Ma TV.
Future<bool> openReportProblem(BuildContext context, {String what = ''}) async {
  final number = vjodSupportNumber.value ?? await loadSupportNumber();
  if (number == null || !context.mounted) return false;
  final reports = MaTvReports.instance;
  final last = await reports.last();
  final id = await reports.deviceId();
  if (!context.mounted) return false;
  final text = reportProblemText(
    intro: vjodText(context, fr: 'Problème sur VJOD :', en: 'Problem with VJOD:', ru: 'Проблема с VJOD:', zh: 'VJOD 问题：'),
    what: what,
    last: last,
    version: VjodBuild.commit.isEmpty ? VjodBuild.version : '${VjodBuild.version} (${VjodBuild.commit})',
    device: [
      PlatformDetection.isTV ? 'TV' : 'Mobile',
      if (GetIt.instance.isRegistered<DeviceInfo>()) GetIt.instance<DeviceInfo>().name,
    ].join(' · '),
    deviceId: id,
  );
  await showQrOrLaunch(
    context,
    url: 'https://wa.me/$number?text=${Uri.encodeComponent(text)}',
    title: vjodText(context, fr: 'Signaler un problème', en: 'Report a problem', ru: 'Сообщить о проблеме', zh: '报告问题'),
  );
  return true;
}
