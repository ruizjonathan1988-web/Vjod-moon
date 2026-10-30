import 'dart:convert';

import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../preference/seerr_preferences.dart';
import 'tv_sources.dart';
import 'xtream_catalog.dart';

/// The Jellyfin collection the seedbox writes VJOD's settings into each
/// night. Every signed-in viewer can read it, so a device sets itself up
/// with nothing to type.
const vjodConfigCollectionName = 'VJOD – réglages';

/// The collection IPTV Checker writes the address of its "Ma TV" into, kept
/// apart so the seedbox's nightly rewrite of the settings never drops it.
const vjodTvCollectionName = 'VJOD – TV';

/// What the settings collection carries: the provider account every device
/// of the house plays with, and (only if written by hand) a catalogue
/// address. The seedbox never puts its HTTP access there, since that is also
/// the WebDAV access to its files.
class VjodServerConfig {
  final XtreamAccount? provider;
  final String? catalogUrl;

  const VjodServerConfig({this.provider, this.catalogUrl});
}

/// The settings held by the collection's [overview], or null when it holds
/// none.
VjodServerConfig? configFromOverview(String? overview) {
  final match = RegExp(
    r'VJOD-CONFIG:([A-Za-z0-9_\-+/=]+)',
  ).firstMatch(overview ?? '');
  if (match == null) return null;
  try {
    final raw = match.group(1)!.replaceAll('+', '-').replaceAll('/', '_');
    final json = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(raw))),
    );
    if (json is! Map) return null;
    final provider = XtreamAccount.fromJson(json['provider']);
    final url = json['catalog']?.toString().trim() ?? '';
    final uri = Uri.tryParse(url);
    final catalogUrl =
        uri != null &&
            uri.host.isNotEmpty &&
            (uri.isScheme('http') || uri.isScheme('https'))
        ? url
        : null;
    if (provider == null && catalogUrl == null) return null;
    return VjodServerConfig(provider: provider, catalogUrl: catalogUrl);
  } catch (_) {
    return null;
  }
}

/// Reads the settings collection from the signed-in Jellyfin server and takes
/// on what it carries: the provider account for the whole device, and a
/// catalogue address if one is there. Returns whether anything changed.
/// Nothing found changes nothing, so what was set by hand stays.
///
/// Also runs in a browser: that is how the web app learns Ma TV's address, and
/// a plain-HTTP provider it can't reach is set aside later, when the
/// catalogue is chosen (see `reachableFromPage`).
Future<bool> syncVjodConfigFromServer() async {
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
    // IPTV Checker's "Ma TV" sits in a collection of its own ("VJOD – TV"),
    // so the seedbox rewriting its settings never drops it.
    var tvChanged = false;
    for (final item in items) {
      if (item is! Map) continue;
      final tv = tvServerFromOverview(item['Overview']?.toString());
      if (tv != null) {
        tvChanged = await saveTvSourcesServer(tv);
        break;
      }
    }
    for (final item in items) {
      if (item is! Map) continue;
      final config = configFromOverview(item['Overview']?.toString());
      if (config == null) continue;
      final prefs = getIt<SeerrPreferences>();
      var changed = false;
      final provider = config.provider;
      if (provider != null) {
        final json = jsonEncode(provider.toJson());
        if (prefs.vjodJellyfinProviderAccountJson != json) {
          await prefs.setVjodJellyfinProviderAccountJson(json);
          changed = true;
        }
      }
      final url = config.catalogUrl;
      if (url != null && prefs.vjodCatalogServerUrl != url) {
        await prefs.setVjodCatalogServerUrl(url);
        await prefs.setVjodCatalogServerAccountJson('');
        changed = true;
      }
      return changed || tvChanged;
    }
    return tvChanged;
  } catch (_) {
    // A server that doesn't answer leaves the device as it was.
  }
  return false;
}
