/// Groups duplicate live-TV channels so a lineup full of "M6", "M6 HD",
/// "M6 FHD" behaves like one channel: tuning picks the best variant, and a
/// failed stream can fall back to the next. It only reads channel names; it
/// never fetches or ranks a source.

/// Quality/language tags that mark a variant of the same channel rather than a
/// different channel. Compared on the normalized token.
const Set<String> _variantTags = {
  'hd', 'fhd', 'uhd', 'sd', 'hq', 'sq', 'lq',
  '4k', '8k', 'h265', 'h264', 'hevc', '1080', '1080p', '720', '720p',
  'fr', 'vf', 'vip', 'raw', 'multi',
};

String _normToken(String token) {
  final b = StringBuffer();
  for (final r in token.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    if (RegExp(r'[a-z0-9]').hasMatch(c)) b.write(c);
  }
  return b.toString();
}

/// The identity of a channel ignoring its quality/language variant. "M6 HD"
/// and "M6 FHD" share a base key; "France 2" and "France 3" do not, because
/// their meaningful number is kept.
String channelBaseKey(String name) {
  final tokens = name.split(RegExp(r'[^A-Za-z0-9+]+'));
  final kept = <String>[];
  for (final t in tokens) {
    final n = _normToken(t);
    if (n.isEmpty) continue;
    if (_variantTags.contains(n)) continue;
    kept.add(n);
  }
  final key = kept.join();
  // A name that was only tags (unlikely) falls back to the whole normalized
  // name so it is not merged with everything else.
  return key.isEmpty ? _normToken(name) : key;
}

/// Lower sorts first: the better the stated quality, the earlier it is tried.
int channelQualityRank(String name) {
  final n = _normToken(name);
  if (n.contains('uhd') || n.contains('4k') || n.contains('8k')) return 0;
  if (n.contains('fhd') || n.contains('1080')) return 1;
  if (n.contains('hd') || n.contains('720')) return 2;
  if (n.contains('sd')) return 4;
  return 3;
}

/// Groups the channel [names] by [channelBaseKey]. Each group lists the
/// original indices best variant first (quality, then original order). Groups
/// come in the order their best member first appears, so a lineup keeps its
/// overall shape with each channel collapsed to one entry.
List<List<int>> groupChannelIndices(List<String> names) {
  final order = <String>[];
  final byKey = <String, List<int>>{};
  for (var i = 0; i < names.length; i++) {
    final key = channelBaseKey(names[i]);
    final group = byKey.putIfAbsent(key, () {
      order.add(key);
      return <int>[];
    });
    group.add(i);
  }
  for (final key in order) {
    byKey[key]!.sort((a, b) {
      final q = channelQualityRank(names[a]).compareTo(channelQualityRank(names[b]));
      return q != 0 ? q : a.compareTo(b);
    });
  }
  return [for (final key in order) byKey[key]!];
}
