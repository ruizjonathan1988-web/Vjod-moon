/// Tells a title streamed from the IPTV provider (a STRM file the Xtream
/// Library plugin wrote) from a file of the server's own, by the item's path.
library;

import 'secondary_library.dart';

List<String> _folders(String path) {
  final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty);
  final list = parts.toList();
  if (list.isNotEmpty) list.removeLast();
  return list;
}

/// Whether an item at [path] is played from the provider rather than from a
/// file of the server's own. A missing path says no, so a server that keeps
/// paths to itself never gets its own files tagged.
bool isProviderStreamPath(String? path) {
  if (path == null || path.isEmpty) return false;
  if (path.toLowerCase().endsWith('.strm')) return true;
  return _folders(path).any(isProviderLibraryName);
}

/// Whether an item at [path] sits in a language copy library, such as
/// "Russian Movies".
bool isLanguageCopyPath(String? path) {
  if (path == null || path.isEmpty) return false;
  return _folders(path).any(isRussianLibraryName);
}

/// How much a copy of a title is worth playing, lowest first: a file of the
/// main libraries, then one of a language copy, then the provider's stream.
int copyRankOfPath(String? path) {
  if (isProviderStreamPath(path)) return 2;
  if (isLanguageCopyPath(path)) return 1;
  return 0;
}
