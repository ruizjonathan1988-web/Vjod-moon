// VJOD's own bits of logging: where an error used to be dropped without a
// word, it now lands in the diagnostic log (when logging is on), so a crash
// on a device can be explained; and the IPTV secrets are kept out of it.
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../data/services/log_service.dart';

/// Notes an error VJOD recovers from, with where it happened.
void vjodLogError(String where, Object error) {
  debugPrint('[VJOD] $where: $error');
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<LogService>()) return;
  getIt<LogService>().log(
    LogCategory.general,
    '[VJOD] $where',
    level: LogLevel.warning,
    error: error,
  );
}

// The Ma TV key travels as `k=` (or `key=`), the provider's account as
// `username=`/`password=` in its API and in the path of every stream
// (`/movie/<user>/<password>/<id>.mkv`, the same under /series, /live and
// /timeshift, and Ma TV's own `/tv/xc/movie/vjod/<key>/`).
final _iptvQuery = RegExp(
  r'([?&;](?:k|key|username|user|password|pass|pwd)=)[^&\s"\x27<>]+',
  caseSensitive: false,
);
final _iptvPath = RegExp(
  r'/(movie|series|live|timeshift)/[^/\s"\x27<>]+/[^/\s"\x27<>]+/',
  caseSensitive: false,
);

/// [text] with the IPTV key, account and password replaced.
String redactIptvSecrets(String text) {
  if (!text.contains('=') && !text.contains('/')) return text;
  return text
      .replaceAllMapped(_iptvQuery, (m) => '${m.group(1)}[REDACTED]')
      .replaceAllMapped(_iptvPath, (m) => '/${m.group(1)}/[REDACTED]/[REDACTED]/');
}
