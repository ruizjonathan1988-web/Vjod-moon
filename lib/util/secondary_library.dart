/// Libraries that hold another language's copy of the main ones, such as
/// "Russian Movies" next to "Films". They share the main library's tab and are
/// reached from a chip on the library page.
library;

/// Whether a library with this name is a language copy rather than a main one.
bool isSecondaryLibraryName(String name) {
  final lower = name.toLowerCase();
  return lower.contains('russ') || lower.contains('рус');
}

/// The short label a library gets on the chip that switches to it.
String libraryChipLabel(String name, String collectionType) {
  final series = collectionType.toLowerCase() == 'tvshows';
  final base = series ? 'Séries' : 'Films';
  return isSecondaryLibraryName(name) ? '$base RU' : base;
}
