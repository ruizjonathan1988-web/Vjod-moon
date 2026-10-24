import '../models/aggregated_item.dart';
import '../models/home_row.dart';
import 'seerr/for_you_ranker.dart';
import 'seerr/seerr_api_models.dart';

/// Tidies the home rows before they are drawn, without touching the rows the
/// paging loaders keep.
///
/// A title already shown higher up is left out of the browsing rows below
/// it, so scrolling down brings something new each time. Rows that hold a
/// list of their own, like Continue Watching, Next Up, a Top 10 or the
/// viewer's requests, keep everything.
///
/// A Seerr card the viewer requested this session shows as requested, even
/// when its row was fetched before the request, and loses [requestableFlag],
/// the mark that opens the request sheet.
List<HomeRow> tidyHomeRows(
  List<HomeRow> rows, {
  Set<String> keptRowIds = const {},
  Set<String> requestedKeys = const {},
  String? requestableFlag,
}) {
  final seen = <String>{};
  final tidy = <HomeRow>[];
  for (final row in rows) {
    var items = row.items;
    if (requestedKeys.isNotEmpty) {
      items = _markRequested(items, requestedKeys, requestableFlag);
    }
    if (_dedupes(row, keptRowIds)) {
      final fresh = [
        for (final item in items)
          if (!_keysOf(item).any(seen.contains)) item,
      ];
      // A row with nothing new keeps what it has rather than vanish
      // while its next page could still bring something.
      if (fresh.isNotEmpty && fresh.length < items.length) items = fresh;
    }
    if (row.rowType != HomeRowType.mediaBar) {
      for (final item in items) {
        seen.addAll(_keysOf(item));
      }
    }
    if (identical(items, row.items)) {
      tidy.add(row);
    } else {
      final removed = row.items.length - items.length;
      tidy.add(
        row.copyWith(
          items: items,
          totalCount: row.totalCount > removed
              ? row.totalCount - removed
              : items.length,
        ),
      );
    }
  }
  return tidy;
}

/// The browsing rows: recently added, recently released and the generated
/// rows, like For You, Gems or Family Night.
bool _dedupes(HomeRow row, Set<String> keptRowIds) {
  if (keptRowIds.contains(row.id)) return false;
  return switch (row.rowType) {
    HomeRowType.latestMedia ||
    HomeRowType.recentlyReleased ||
    HomeRowType.pluginDynamic => true,
    _ => false,
  };
}

/// What identifies the title on [item]: its library entry (an episode stands
/// for its series) and its TMDB id, so a Seerr card matches the library copy.
/// Anything that isn't a film or a series has none and is never left out.
Set<String> _keysOf(AggregatedItem item) {
  if (item.serverId == 'seerr') {
    final mediaType =
        item.seerrMediaType ??
        (item.type == 'Series' || item.type == 'tv' ? 'tv' : 'movie');
    final tmdb = _seerrTmdbId(item);
    return {if (tmdb != null) 'tmdb:$mediaType:$tmdb'};
  }
  final tmdb = item.tmdbId;
  return switch (item.type) {
    'Movie' => {
      'item:${item.serverId}:${item.id}',
      if (tmdb != null) 'tmdb:movie:$tmdb',
    },
    'Series' => {
      'item:${item.serverId}:${item.id}',
      if (tmdb != null) 'tmdb:tv:$tmdb',
    },
    'Episode' || 'Season' => {
      if (item.seriesId case final series?) 'item:${item.serverId}:$series',
    },
    _ => const {},
  };
}

/// Seerr cards are keyed by their TMDB id, or by IMDb id with the TMDB id
/// among their provider ids.
String? _seerrTmdbId(AggregatedItem item) =>
    item.tmdbId ?? (int.tryParse(item.id) != null ? item.id : null);

List<AggregatedItem> _markRequested(
  List<AggregatedItem> items,
  Set<String> requestedKeys,
  String? requestableFlag,
) {
  List<AggregatedItem>? marked;
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item.serverId != 'seerr' || SeerrMediaStatus.hasDot(item.seerrStatus)) {
      continue;
    }
    final tmdb = int.tryParse(_seerrTmdbId(item) ?? '');
    final mediaType = item.seerrMediaType;
    if (tmdb == null || mediaType == null) continue;
    if (!requestedKeys.contains(forYouKey(mediaType, tmdb))) continue;
    marked ??= List.of(items);
    marked[i] = AggregatedItem(
      id: item.id,
      serverId: item.serverId,
      rawData: {
        for (final entry in item.rawData.entries)
          if (entry.key != requestableFlag) entry.key: entry.value,
        'SeerrStatus': SeerrMediaStatus.pending,
      },
    );
  }
  return marked ?? items;
}
