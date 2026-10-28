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

/// Country tags IPTV providers put in front of a name ("FR - TF1 SD",
/// "|UK| Sky", "CA: SuperSport").
const Set<String> _countryTags = {
  'fr', 'be', 'ch', 'qc', 'ca', 'uk', 'us', 'de', 'es', 'it', 'pt', 'nl',
  'ar', 'tr', 'pl', 'ru', 'af', 'za', 'ma', 'dz', 'tn', 'ex', 'au', 'in',
};

final RegExp _tagPattern =
    RegExp(r'^\W*([a-z]{2,3})\s*[\]\)|:\-]+\s*', caseSensitive: false);

final RegExp _qualitySuffix = RegExp(
  r'(\s|[-|])+(sd|hd|fhd|uhd|4k|hevc|h265|720p?|1080p?|50fps|60fps|raw|backup)\s*$',
  caseSensitive: false,
);

/// The country tag in front of a provider's channel name, lower case, or
/// null when there is none.
String? channelCountryTag(String name) {
  final match = _tagPattern.firstMatch(name);
  final tag = match?.group(1)?.toLowerCase();
  return tag != null && _countryTags.contains(tag) ? tag : null;
}

/// The channel's own name, without the provider's country tag and quality
/// suffixes: "FR - TF1 SD" → "TF1", "|FR| FRANCE 2 FHD" → "FRANCE 2".
String bareChannelName(String name) {
  var bare = name.trim();
  if (channelCountryTag(bare) != null) {
    bare = bare.replaceFirst(_tagPattern, '');
  }
  while (true) {
    final next = bare.replaceFirst(_qualitySuffix, '').trim();
    if (next == bare) break;
    bare = next;
  }
  return bare;
}

/// Whether the channel is tagged for another country than France.
bool _isForeign(String name) {
  final tag = channelCountryTag(name);
  return tag != null && tag != 'fr';
}

/// Whether the channel is French: tagged FR by the provider, or a known
/// French generalist or sports channel with no other country's tag.
bool isFrenchChannel(String name) =>
    channelCountryTag(name) == 'fr' ||
    isFrenchMainChannel(name) ||
    isFrenchSportsChannel(name);

/// The TNT position of a known generalist channel, or null.
int? frenchChannelRank(String name) => _isForeign(name)
    ? null
    : _tntOrder[normalizeChannelName(bareChannelName(name))];

/// Whether the channel is a French sports channel.
bool isFrenchSportsChannel(String name) {
  if (_isForeign(name)) return false;
  final n = normalizeChannelName(bareChannelName(name));
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
  if (isFrenchSportsChannel(name)) {
    final n = normalizeChannelName(bareChannelName(name));
    for (var i = 0; i < _sportsFragments.length; i++) {
      if (n.contains(_sportsFragments[i])) return 500 + i;
    }
  }
  // Other French channels come before the rest of the world.
  if (channelCountryTag(name) == 'fr') return 1000;
  return 100000;
}
