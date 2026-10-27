import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File> _file(String key) async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/xtream_catalog/$key.json');
}

/// The catalogue saved under [key], or null when there is none or it can't
/// be read.
Future<String?> readCatalogCache(String key) async {
  try {
    final file = await _file(key);
    if (!await file.exists()) return null;
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

/// Saves the catalogue under [key]. Written beside and then moved over the
/// old one, so a crash mid-write never leaves a half file behind.
Future<void> writeCatalogCache(String key, String data) async {
  try {
    final file = await _file(key);
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(file.path);
  } catch (_) {
    // A catalogue that can't be saved is fetched again next launch.
  }
}
