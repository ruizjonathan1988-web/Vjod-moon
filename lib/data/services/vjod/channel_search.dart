/// Channel search as a viewer types it on a remote: case, accents, spaces
/// and punctuation are ignored, so "tf 1", "TF1" and "tf-1" all find TF1, and
/// "equipe" finds "L'Équipe".
String normalizeChannelQuery(String text) {
  const accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
    'ç': 'c',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'í': 'i',
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'õ': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
    'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
  };
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final plain = accents[char] ?? char;
    if (RegExp(r'^[a-z0-9]+$').hasMatch(plain)) buffer.write(plain);
  }
  return buffer.toString();
}

/// Whether a channel matches [query]: its name, its number, or the title of
/// one of [programTitles] (what it airs now or later), so "psg" finds the
/// channel showing the match.
bool channelMatchesQuery(
  String query, {
  required String name,
  String? number,
  Iterable<String> programTitles = const [],
}) {
  final q = normalizeChannelQuery(query);
  if (q.isEmpty) return true;
  if (normalizeChannelQuery(name).contains(q)) return true;
  if (number != null && normalizeChannelQuery(number) == q) return true;
  for (final title in programTitles) {
    if (normalizeChannelQuery(title).contains(q)) return true;
  }
  return false;
}
