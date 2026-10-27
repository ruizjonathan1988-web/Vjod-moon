/// The channels watched last, kept as a comma-separated list of ids, most
/// recent first, as a TV box shows them.
const int kMaxRecentChannels = 12;

List<String> parseRecentChannels(String stored) => [
      for (final id in stored.split(','))
        if (id.trim().isNotEmpty) id.trim(),
    ];

/// Puts [channelId] first, without duplicates, capped at [max].
String pushRecentChannel(String stored, String channelId,
    {int max = kMaxRecentChannels}) {
  final id = channelId.trim();
  if (id.isEmpty) return stored;
  final ids = [id, ...parseRecentChannels(stored).where((e) => e != id)];
  return ids.take(max).join(',');
}
