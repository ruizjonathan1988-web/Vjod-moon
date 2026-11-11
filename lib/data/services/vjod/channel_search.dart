/// Channel search as a viewer types it on a remote: case, accents, spaces
/// and punctuation are ignored, so "tf 1", "TF1" and "tf-1" all find TF1, and
/// "equipe" finds "L'Équipe".
// VJOD 5.13: the accents by character code, so a letter costs a lookup and
// not a string and a regular expression each. On a small box searching
// thousands of channels on every key press, that was enough to freeze the
// screen (« L'application ne répond pas »).
const _accents = <int, String>{
  0xe0: 'a', 0xe2: 'a', 0xe4: 'a', 0xe1: 'a', 0xe3: 'a',
  0xe7: 'c',
  0xe9: 'e', 0xe8: 'e', 0xea: 'e', 0xeb: 'e',
  0xee: 'i', 0xef: 'i', 0xed: 'i',
  0xf4: 'o', 0xf6: 'o', 0xf3: 'o', 0xf5: 'o',
  0xf9: 'u', 0xfb: 'u', 0xfc: 'u', 0xfa: 'u',
  0xff: 'y', 0xf1: 'n', 0x153: 'oe', 0xe6: 'ae',
};

// The same names come back on every key press: each is worked out once.
final _normalized = <String, String>{};
const _normalizedMax = 30000;

String normalizeChannelQuery(String text) {
  final known = _normalized[text];
  if (known != null) return known;
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    if ((rune >= 0x61 && rune <= 0x7a) || (rune >= 0x30 && rune <= 0x39)) {
      buffer.writeCharCode(rune);
    } else {
      final plain = _accents[rune];
      if (plain != null) buffer.write(plain);
    }
  }
  final result = buffer.toString();
  if (_normalized.length >= _normalizedMax) _normalized.clear();
  _normalized[text] = result;
  return result;
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
