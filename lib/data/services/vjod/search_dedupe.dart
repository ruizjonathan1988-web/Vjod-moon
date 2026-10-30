// VJOD search: each title once, under its best way to watch it.
//
// The search gathers three sources: the server (Jellyfin), the IPTV provider
// (Ma TV) and Seerr (everything that can be asked for). The same film used to
// show up in all three rows. Now:
// - on the server: in the server's rows only;
// - otherwise at the IPTV provider: in « À regarder tout de suite (IPTV) »;
// - otherwise: in « À demander ».
// People in Seerr's results (actors, directors) are kept as they are.

import '../seerr/seerr_api_models.dart';
import 'xtream_catalog.dart';

/// Whether Seerr says the title is already on the server.
bool _onServer(SeerrDiscoverItem item) {
  final status = item.mediaInfo?.status;
  return status == SeerrMediaStatus.available || status == SeerrMediaStatus.partiallyAvailable;
}

bool _isPerson(SeerrDiscoverItem item) => item.mediaType == 'person';

/// The IPTV and Seerr results, each title kept in the best place only.
/// [libraryTmdbIds]: the TMDB ids of the films and series the server search
/// found.
({List<XtreamTitle> provider, List<SeerrDiscoverItem> seerr}) dedupeCatalogResults({
  required Set<String> libraryTmdbIds,
  required List<XtreamTitle> provider,
  required List<SeerrDiscoverItem> seerr,
}) {
  final onServer = {
    ...libraryTmdbIds.where((id) => id.isNotEmpty),
    for (final item in seerr)
      if (!_isPerson(item) && _onServer(item)) '${item.id}',
  };
  final keptProvider = [
    for (final t in provider)
      if (t.tmdbId.isEmpty || !onServer.contains(t.tmdbId)) t,
  ];
  final atProvider = {
    for (final t in keptProvider)
      if (t.tmdbId.isNotEmpty) t.tmdbId,
  };
  final keptSeerr = [
    for (final item in seerr)
      if (_isPerson(item) ||
          (!_onServer(item) &&
              !onServer.contains('${item.id}') &&
              !atProvider.contains('${item.id}')))
        item,
  ];
  return (provider: keptProvider, seerr: keptSeerr);
}
