/// Knows the French TV lineup well enough to order a channel list like a real
/// French TV, and to tell the généralistes and the French sports channels
/// apart so they can be favourited in one go. It only reads channel names; it
/// never fetches or chooses a source.

/// Normalizes a channel name for matching: lower case, accents stripped,
/// everything but letters and digits removed. "Canal+ Sport" → "canalsport".
String normalizeChannelName(String name) {
  const from = 'àâäáãéèêëíìîïóòôöõúùûüýÿçñ';
  const to = 'aaaaaeeeeiiiiooooouuuuyycn';
  final buffer = StringBuffer();
  for (final rune in name.toLowerCase().runes) {
    var ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    if (i >= 0) ch = to[i];
    if (RegExp(r'[a-z0-9]').hasMatch(ch)) buffer.write(ch);
  }
  return buffer.toString();
}

/// The French TNT order, normalized name → position. The generalist channels
/// everyone knows, in the order a French TV lists them.
const Map<String, int> _tntOrder = {
  'tf1': 1,
  'france2': 2,
  'france3': 3,
  'canal': 4,
  'canalplus': 4,
  'france5': 5,
  'm6': 6,
  'arte': 7,
  'c8': 8,
  'w9': 9,
  'tmc': 10,
  'tfx': 11,
  'nrj12': 12,
  'lcp': 13,
  'publicsenat': 13,
  'france4': 14,
  'bfmtv': 15,
  'cnews': 16,
  'cstar': 17,
  'gulli': 18,
  'tf1seriesfilms': 19,
  'lequipe': 20,
  '6ter': 21,
  'rmcstory': 22,
  'rmcdecouverte': 23,
  'cherie25': 24,
  'lci': 25,
  'franceinfo': 26,
};

/// French sports channels, in a sensible order, matched by a fragment of the
/// normalized name so numbered variants (beIN Sports 1/2/3…) all match.
const List<String> _sportsFragments = [
  'canalsport',
  'canalfoot',
  'beinsport',
  'rmcsport',
  'eurosport',
  'infosport',
  'lequipe',
  'ligue1',
  'dazn',
];

/// The TNT position of a known generalist channel, or null.
int? frenchChannelRank(String name) => _tntOrder[normalizeChannelName(name)];

/// Whether the channel is a French sports channel.
bool isFrenchSportsChannel(String name) {
  final n = normalizeChannelName(name);
  // L'Équipe is both TNT 20 and sports; count it as sports too.
  return _sportsFragments.any((f) => n.contains(f));
}

/// Whether the channel is a well-known French generalist (TNT) channel.
bool isFrenchMainChannel(String name) => frenchChannelRank(name) != null;

/// Whether the channel should be favourited by the one-tap French set: the
/// généralistes and the French sports channels.
bool isFrenchFavourite(String name) =>
    isFrenchMainChannel(name) || isFrenchSportsChannel(name);

/// Sort key for the "French TV" order: known generalists first in TNT order,
/// then French sports channels, then everything else (left to a fallback sort
/// by number). Lower sorts first.
int frenchTvOrder(String name) {
  final rank = frenchChannelRank(name);
  if (rank != null) return rank;
  final n = normalizeChannelName(name);
  for (var i = 0; i < _sportsFragments.length; i++) {
    if (n.contains(_sportsFragments[i])) return 500 + i;
  }
  return 100000;
}
