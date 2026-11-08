// VJOD's own Jellyfin: offered by itself on the first launch, so a new
// viewer lands straight on its sign-in page instead of a blank server
// choice. « Choisir un serveur » on that page still leads to any other
// server, for people who are not on this one.

/// The house Jellyfin. Its address is not written in the code (the code is
/// public) : the build gives it from the GitHub secret VJOD_SERVEUR. Empty
/// when the secret is missing, and then nothing is offered.
const vjodHomeServerUrl = String.fromEnvironment('VJOD_SERVEUR');

/// Whether the server choice should open the house server by itself: only
/// while no server is saved on the device, and only once, so someone who
/// removed it to use another server is never sent back to it.
bool shouldOfferHomeServer({required bool hasServers, required bool alreadyOffered}) =>
    !hasServers && !alreadyOffered;
