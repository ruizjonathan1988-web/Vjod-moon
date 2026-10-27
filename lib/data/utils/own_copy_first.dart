import '../models/aggregated_item.dart';

/// The key two copies of one film or series share: the TMDB id when there is
/// one, else the type, name and year.
String? _titleKey(AggregatedItem item) {
  final type = item.type;
  if (type != 'Movie' && type != 'Series') return null;
  final tmdb = item.tmdbId;
  if (tmdb != null && tmdb.isNotEmpty) return '$type|tmdb|$tmdb';
  final name = item.name.trim().toLowerCase();
  if (name.isEmpty) return null;
  return '$type|$name|${item.productionYear ?? ''}';
}

/// Drops a provider's stream of a film or series when the same list already
/// holds the server's own file of it, so the viewer lands on their copy
/// rather than a stream that may stop answering. Order is kept otherwise.
List<AggregatedItem> withoutStreamDuplicates(List<AggregatedItem> items) {
  if (!items.any((i) => i.isProviderStream)) return items;
  final owned = <String>{};
  for (final item in items) {
    if (item.isProviderStream) continue;
    final key = _titleKey(item);
    if (key != null) owned.add(key);
  }
  if (owned.isEmpty) return items;
  return [
    for (final item in items)
      if (!item.isProviderStream || !owned.contains(_titleKey(item))) item,
  ];
}
