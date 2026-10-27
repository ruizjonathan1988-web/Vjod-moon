/// Builds a direct link to a title in Radarr or Sonarr from the server list
/// Seerr returns at /settings/radarr and /settings/sonarr, the same way the
/// Seerr web UI does. Admin-only data; a non-admin gets an empty list and so
/// no link.

/// The browsable URL of the title in its Radarr/Sonarr server, or null when it
/// cannot be built (no slug, unknown server, no address).
String? buildArrUrl(
  List<dynamic> servers, {
  required int? serviceId,
  required String? slug,
  required bool isMovie,
}) {
  if (slug == null || slug.trim().isEmpty) return null;

  Map<String, dynamic>? server;
  for (final s in servers) {
    if (s is Map && s['id'] == serviceId) {
      server = s.cast<String, dynamic>();
      break;
    }
  }
  // Fall back to the only/first configured server when the id does not match.
  if (server == null) {
    for (final s in servers) {
      if (s is Map) {
        server = s.cast<String, dynamic>();
        break;
      }
    }
  }
  if (server == null) return null;

  final external = (server['externalUrl'] as String?)?.trim();
  String base;
  if (external != null && external.isNotEmpty) {
    base = external;
  } else {
    final host = server['hostname']?.toString().trim() ?? '';
    if (host.isEmpty) return null;
    final ssl = server['useSsl'] == true;
    final port = server['port'];
    final baseUrl = (server['baseUrl'] as String?)?.trim() ?? '';
    base = '${ssl ? 'https' : 'http'}://$host'
        '${port == null ? '' : ':$port'}$baseUrl';
  }
  base = base.replaceAll(RegExp(r'/+$'), '');
  final slugPath = slug.trim();
  return '$base/${isMovie ? 'movie' : 'series'}/$slugPath';
}
