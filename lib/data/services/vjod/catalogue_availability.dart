// The Films and Series pages show the whole catalogue: what the server has,
// what plays at once from the IPTV provider, and what can be asked for. Each
// poster says which, and the filter keeps one kind.

import '../seerr/seerr_api_models.dart';

enum CatalogueAvailability { server, iptv, requested, toRequest }

/// How a title can be watched: on the server first, then at the provider,
/// then already asked for, else to ask for.
CatalogueAvailability catalogueAvailability({int? seerrStatus, required bool hasIptv}) {
  if (seerrStatus == SeerrMediaStatus.available || seerrStatus == SeerrMediaStatus.partiallyAvailable) {
    return CatalogueAvailability.server;
  }
  if (hasIptv) return CatalogueAvailability.iptv;
  if (seerrStatus == SeerrMediaStatus.pending || seerrStatus == SeerrMediaStatus.processing) {
    return CatalogueAvailability.requested;
  }
  return CatalogueAvailability.toRequest;
}

/// The filter at the top: 0 everything, 1 on the server, 2 IPTV, 3 to
/// request (already asked for included).
bool catalogueFilterKeeps(int filter, CatalogueAvailability a) => switch (filter) {
  1 => a == CatalogueAvailability.server,
  2 => a == CatalogueAvailability.iptv,
  3 => a == CatalogueAvailability.toRequest || a == CatalogueAvailability.requested,
  _ => true,
};
