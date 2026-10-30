// VJOD's own Jellyfin: offered by itself on the first launch, so a new
// viewer lands straight on its sign-in page instead of a blank server
// choice. « Choisir un serveur » on that page still leads to any other
// server, for people who are not on this one.

/// The house Jellyfin (on the Ultra.cc seedbox).
const vjodHomeServerUrl = 'https://ava88.zen.usbx.me/jellyfin';

/// Whether the server choice should open the house server by itself: only
/// while no server is saved on the device, and only once, so someone who
/// removed it to use another server is never sent back to it.
bool shouldOfferHomeServer({required bool hasServers, required bool alreadyOffered}) =>
    !hasServers && !alreadyOffered;
