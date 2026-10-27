/// Libraries that hold another language's copy of the main ones, such as
/// "Russian Movies" next to "Films". They share the main library's tab and are
/// reached from a chip on the library page.
library;

/// Whether a library with this name holds an IPTV provider's catalogue
/// (streams linked by the Xtream Library plugin) rather than files of the
/// server's own. Told by the library's name, never the provider's, so
/// switching providers changes nothing here.
bool isProviderLibraryName(String name) {
  final lower = name.toLowerCase();
  return lower.contains('fournisseur') ||
      lower.contains('provider') ||
      lower.contains('iptv') ||
      lower.contains('xtream');
}

/// Whether a library with this name is a language copy rather than a main one.
bool isRussianLibraryName(String name) {
  final lower = name.toLowerCase();
  return lower.contains('russ') || lower.contains('рус');
}

/// Whether a library sits beside a main one, behind a chip: a language copy
/// or a provider's catalogue.
bool isSecondaryLibraryName(String name) =>
    isRussianLibraryName(name) || isProviderLibraryName(name);

/// Where a library comes in the chips: the main one, the language copy, then
/// the provider's catalogue.
int libraryChipRank(String name) => isProviderLibraryName(name)
    ? 2
    : isRussianLibraryName(name)
    ? 1
    : 0;

/// The short label a library gets on the chip that switches to it.
String libraryChipLabel(String name, String collectionType) {
  final series = collectionType.toLowerCase() == 'tvshows';
  final base = series ? 'Séries' : 'Films';
  if (isProviderLibraryName(name)) return 'Fournisseur';
  return isRussianLibraryName(name) ? '$base RU' : base;
}
