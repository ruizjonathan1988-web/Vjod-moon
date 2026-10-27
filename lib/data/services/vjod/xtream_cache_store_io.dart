import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// Downloads the catalogue the seedbox prepared at [url], unpacking it when
/// it is gzipped. A login inside the URL (`https://user:pass@host/…`) is sent
/// as HTTP basic auth, which Ultra.cc's HTTP access asks for. Null on any
/// failure, so the caller falls back to the provider.
Future<String?> fetchServerCatalog(String url) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    return null;
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final clean = uri.replace(userInfo: '');
    final request = await client.getUrl(clean);
    if (uri.userInfo.isNotEmpty) {
      final login = Uri.decodeComponent(uri.userInfo);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode(login))}',
      );
    }
    final response = await request.close().timeout(const Duration(minutes: 2));
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(minutes: 3))) {
      builder.add(chunk);
    }
    var bytes = builder.takeBytes();
    // The server may have unpacked it already (Content-Encoding); only a
    // body that still starts with gzip's magic bytes is unpacked here.
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      bytes = Uint8List.fromList(gzip.decode(bytes));
    }
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
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
