// VJOD 4.20: lists kept on the device (Ma TV's categories and channels, the
// replay, the first page of Films and Séries), so a screen shows the last known list at once, even just after
// the app started, and puts the fresh one in place when it arrives.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

class VjodSnapshots {
  VjodSnapshots._();

  static final _mem = <String, Object?>{};
  static Directory? _dir;

  // Off under `flutter test` unless a test turns it on: a list saved by one
  // test must not show up in the next. In a browser there is no file system
  // (and `Platform.environment` throws): the lists are kept in memory only
  // (VJOD 4.35; since 4.20 every screen waited on this and spun forever).
  static bool _on = kIsWeb || !_underTest();

  static bool _underTest() {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  static bool? _webForTests;

  /// Only for tests: pretends to be a browser (true) or not (null).
  static set webForTests(bool? v) => _webForTests = v;

  static bool get _web => _webForTests ?? kIsWeb;

  /// Only for tests: where the files go (null turns saving off again).
  static set directoryForTests(Directory? d) {
    _dir = d;
    _on = d != null;
    _mem.clear();
  }

  static Future<File?> _file(String key) async {
    if (_web) return null;
    try {
      _dir ??= Directory('${(await getApplicationSupportDirectory()).path}/vjod_lists');
      final dir = _dir!;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return File('${dir.path}/${sha1.convert(utf8.encode(key)).toString().substring(0, 20)}.json');
    } catch (_) {
      return null;
    }
  }

  /// The last answer saved under [key] (memory first, then the device), or
  /// null.
  static Future<Object?> read(String key) async {
    try {
      if (!_on) return null;
      if (_mem.containsKey(key)) return _mem[key];
      final f = await _file(key);
      if (f == null || !f.existsSync()) return null;
      final j = jsonDecode(await f.readAsString());
      _mem[key] = j;
      return j;
    } catch (_) {
      return null;
    }
  }

  /// Keeps [json] under [key]; best effort.
  static Future<void> write(String key, Object? json) async {
    try {
      if (!_on) return;
      _mem[key] = json;
      final f = await _file(key);
      await f?.writeAsString(jsonEncode(json));
    } catch (_) {}
  }

  static void clearMemory() => _mem.clear();
}
