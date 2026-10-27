import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../preference/seerr_preferences.dart';

/// The Jellyfin collection the seedbox writes VJOD's settings into each
/// night. Every signed-in viewer can read it, so a device sets itself up
/// with nothing to type.
const vjodConfigCollectionName = 'VJOD – réglages';

/// The catalogue address carried by the collection's [overview], or null
/// when it holds none. The address is only ever returned if it is http(s).
String? catalogUrlFromOverview(String? overview) {
  final match = RegExp(
    r'VJOD-CONFIG:([A-Za-z0-9_\-+/=]+)',
  ).firstMatch(overview ?? '');
  if (match == null) return null;
  try {
    final raw = match.group(1)!.replaceAll('+', '-').replaceAll('/', '_');
    final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(raw))));
    if (json is! Map) return null;
    final url = json['catalog']?.toString().trim() ?? '';
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    if (!(uri.isScheme('http') || uri.isScheme('https'))) return null;
    return url;
  } catch (_) {
    return null;
  }
}

/// Reads the settings collection from the signed-in Jellyfin server and, when
/// it carries a catalogue address other than this device's, takes it on (the
/// account of an earlier address is forgotten, since the new file brings its
/// own). Returns whether anything changed. Nothing found changes nothing, so
/// an address set by hand stays.
Future<bool> syncVjodConfigFromServer() async {
  if (kIsWeb) return false;
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<MediaServerClient>() ||
      !getIt.isRegistered<SeerrPreferences>()) {
    return false;
  }
  try {
    final data = await getIt<MediaServerClient>().itemsApi.getItems(
      includeItemTypes: const ['BoxSet'],
      recursive: true,
      searchTerm: 'VJOD',
      fields: 'Overview',
      limit: 20,
    );
    final items = data['Items'];
    if (items is! List) return false;
    for (final item in items) {
      if (item is! Map) continue;
      final url = catalogUrlFromOverview(item['Overview']?.toString());
      if (url == null) continue;
      final prefs = getIt<SeerrPreferences>();
      if (prefs.vjodCatalogServerUrl == url) return false;
      await prefs.setVjodCatalogServerUrl(url);
      await prefs.setVjodCatalogServerAccountJson('');
      return true;
    }
  } catch (_) {
    // A server that doesn't answer leaves the device as it was.
  }
  return false;
}
