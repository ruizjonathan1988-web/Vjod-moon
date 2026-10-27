/// The invitation that sets a device up for the seedbox's nightly catalogue
/// in one tap: a `moonfin://vjodcatalog?u=…` link carrying the file's
/// address, HTTP access login included. Whoever owns the seedbox sends it
/// privately; the device it reaches asks before using it.
library;

/// The invitation for the catalogue file at [serverUrl].
String buildCatalogInvite(String serverUrl) =>
    'moonfin://vjodcatalog?u=${Uri.encodeQueryComponent(serverUrl.trim())}';

/// The catalogue address held by [text], which may be an invitation, the
/// bare address of the file, or a message around either. Null when there is
/// none. The address is only ever returned if it is an http(s) one.
String? parseCatalogInvite(String? text) {
  final t = text?.trim() ?? '';
  if (t.isEmpty) return null;
  final invite = RegExp(r'moonfin://vjodcatalog\?\S+').firstMatch(t);
  if (invite != null) {
    final uri = Uri.tryParse(_trimTail(invite.group(0)!));
    return _httpOrNull(uri?.queryParameters['u']);
  }
  final url = RegExp(r'https?://\S+').firstMatch(t)?.group(0);
  if (url != null && url.contains('catalog.json')) {
    return _httpOrNull(_trimTail(url));
  }
  return null;
}

/// Punctuation a message puts after a link is not part of it.
String _trimTail(String s) => s.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');

String? _httpOrNull(String? url) {
  final value = url?.trim();
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  if (!(uri.isScheme('http') || uri.isScheme('https'))) return null;
  return value;
}
