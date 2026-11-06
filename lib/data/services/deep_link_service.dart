import 'dart:async';

import 'package:app_links/app_links.dart';

import '../../util/platform_detection.dart';

/// Routes OS-registered `moonfin://` deep links into the app. tvOS and web
/// are gated off, they have no app_links backend.
class DeepLinkService {
  StreamSubscription<Uri>? _subscription;

  static bool get _enabled =>
      !PlatformDetection.isWeb && !PlatformDetection.isAppleTV;

  /// Starts listening for `moonfin://` links, including the one the app was
  /// launched with. [onRoute] receives an in-app route path.
  void startListener(void Function(String route) onRoute) {
    if (!_enabled) return;
    _subscription?.cancel();
    // uriLinkStream replays the launch link before live ones, so this is both
    // the cold-start and the warm path.
    _subscription = AppLinks().uriLinkStream.listen(
      (uri) {
        final route = routeForDeepLink(uri);
        if (route != null) onRoute(route);
      },
      onError: (_) {},
    );
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Resolves a `moonfin://` deep link into an in-app route path, or null if
  /// the link isn't recognized.
  ///
  /// Recognized forms:
  ///  - `moonfin://item?id=<itemId>[&serverId=<serverId>][&userId=<userId>]`
  ///  - `moonfin://play?id=<itemId>[&serverId=<serverId>][&userId=<userId>]`
  ///    (starts playback)
  ///  - `moonfin://tmdb?id=<tmdbId>[&type=movie|tv][&title=<titre>]` : la
  ///    fiche « Regarder / Demander » d'un titre TMDB, qu'il soit sur le
  ///    serveur, en VOD chez le fournisseur IPTV ou à demander (Seerr).
  ///    Envoyé par Aura, le jeu de cinéma.
  ///
  /// `userId` optionally pins a stored user, skipping the profile picker on a
  /// cold start and switching to that user when another one is signed in. It
  /// is only honored for users already signed in on this device, and never
  /// bypasses a PIN, an always-authenticate setting or Kids Mode.
  static String? routeForDeepLink(Uri uri) {
    if (uri.scheme != 'moonfin') return null;
    // A playlist link shared from another app: open the TV tab with it ready
    // to save.
    // The "VJOD TV" icon: Ma TV, straight onto the last channel watched.
    if (uri.host == 'matv') return '/live-tv/guide?autoplay=1';
    if (uri.host == 'tvadd') {
      final u = uri.queryParameters['u'];
      if (u == null || u.isEmpty) return null;
      return '/tv?add=${Uri.encodeQueryComponent(u)}';
    }
    // The seedbox's catalogue, sent as an invitation: open the TV tab, which
    // asks before using it.
    if (uri.host == 'vjodcatalog') {
      final u = uri.queryParameters['u'];
      if (u == null || u.isEmpty) return null;
      return '/tv?catalog=${Uri.encodeQueryComponent(u)}';
    }
    // Un titre TMDB (envoyé par Aura) : sa fiche, comme depuis le Catalogue.
    if (uri.host == 'tmdb') {
      final tmdbId = uri.queryParameters['id']?.trim() ?? '';
      if (!RegExp(r'^\d+$').hasMatch(tmdbId)) return null;
      final type = uri.queryParameters['type'] == 'tv' ? 'tv' : 'movie';
      final title = uri.queryParameters['title']?.trim() ?? '';
      return Uri(path: '/seerr/media/$tmdbId', queryParameters: {
        'mediaType': type,
        if (title.isNotEmpty) 'title': title,
      }).toString();
    }
    final id = uri.queryParameters['id'];
    if (id == null || id.isEmpty) return null;
    final serverId = uri.queryParameters['serverId'];
    final userId = uri.queryParameters['userId'];
    final params = <String, String>{
      if (serverId != null && serverId.isNotEmpty) 'serverId': serverId,
      if (userId != null && userId.isNotEmpty) 'userId': userId,
      if (uri.host == 'play') 'autoPlay': 'true',
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return query.isEmpty ? '/item/$id' : '/item/$id?$query';
  }
}
