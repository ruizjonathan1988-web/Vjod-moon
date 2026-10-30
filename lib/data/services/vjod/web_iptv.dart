// The web version (browser / PWA) and the IPTV catalogue.
//
// A browser page is HTTPS, so it can't reach a plain-HTTP provider, and it
// only plays what its own <video> decodes. Only Ma TV (IPTV Checker on the
// seedbox, behind the seedbox's HTTPS, files relayed by its own routes) is
// used there; a provider read directly stays an app-only thing.
//
// Everything here is plain logic so it is tested without a browser.

/// Whether a browser may use this catalogue: Ma TV only, and only over HTTPS
/// (an HTTPS page is never allowed plain HTTP: mixed content).
bool webMayUseCatalog({required bool isMaTv, required String portal}) {
  if (!isMaTv) return false;
  final uri = Uri.tryParse(portal.trim());
  return uri != null && uri.isScheme('https') && uri.host.isNotEmpty;
}

/// File types no browser plays, by their extension. MKV and MP4 are tried:
/// most of them play (H.264), some don't (HEVC picture, AC3/DTS sound).
const _neverInBrowser = {'avi', 'ts', 'm2ts', 'flv', 'wmv', 'mpg', 'mpeg', 'vob', 'divx', 'xvid', 'rmvb'};

/// Why a browser can't play a file of this type, in French, or null when it
/// is worth trying.
String? webUnplayableReason(String extension) {
  final ext = extension.trim().toLowerCase().replaceAll('.', '');
  if (!_neverInBrowser.contains(ext)) return null;
  return 'Ce fichier (.$ext) ne se lit pas dans un navigateur. '
      'Choisis une autre version avec « Choisir le fichier », '
      'ou regarde-le sur l\'appli Android ou la TV.';
}

/// The extension in a play address (`…/123.mkv?q=1080`), empty when none.
String extensionOfUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final last = path.split('/').last;
  final dot = last.lastIndexOf('.');
  return dot < 0 ? '' : last.substring(dot + 1).toLowerCase();
}

/// Shown when the browser opened the file but can't show it.
const webPlaybackFailedMessage =
    'Ton navigateur ne sait pas lire ce fichier (souvent une vidéo HEVC ou 4K, '
    'ou un son AC3 / DTS). Essaie une autre version avec « Choisir le fichier », '
    'ou regarde-le sur l\'appli Android ou la TV.';

/// Shown when the browser can't reach Ma TV's file at all (usually Ma TV not
/// yet updated to answer the web version).
const webUnreachableMessage =
    'Le navigateur n\'arrive pas à joindre Ma TV pour ce fichier. '
    'Vérifie que Ma TV est à jour sur la seedbox, ou regarde-le sur l\'appli Android ou la TV.';
