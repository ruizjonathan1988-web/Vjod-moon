import 'seerr_api_models.dart';

/// The next film of a saga the viewer started.
class SagaPick {
  final SeerrDiscoverItem item;

  /// The film watched last in that saga, to say "after X".
  final String afterTitle;
  final String collectionName;

  const SagaPick({
    required this.item,
    required this.afterTitle,
    required this.collectionName,
  });

  String get key => 'movie:${item.id}';
}

/// A watched film, newest first, with its TMDB id.
typedef WatchedFilm = ({int tmdbId, String title});

/// For every saga a recently watched film belongs to, the first film after
/// the last one watched, in release order.
///
/// A saga shows once, led by the most recent film watched in it. Films not
/// out yet, without a poster, blocked, or in [exclude] are skipped, so the
/// next one that is out takes their place.
List<SagaPick> nextInSagas({
  required List<WatchedFilm> watched,
  required Map<int, int> collectionOfFilm,
  required Map<int, SeerrCollection> collections,
  Set<String> exclude = const {},
  bool blockAdult = true,
  DateTime? now,
  int limit = 15,
}) {
  final today = now ?? DateTime.now();
  final watchedIds = {for (final film in watched) film.tmdbId};
  final done = <int>{};
  final picks = <SagaPick>[];

  for (final film in watched) {
    if (picks.length >= limit) break;
    final collectionId = collectionOfFilm[film.tmdbId];
    if (collectionId == null || !done.add(collectionId)) continue;
    final collection = collections[collectionId];
    if (collection == null || collection.parts.length < 2) continue;

    final parts = [...collection.parts]..sort(_byRelease);
    var last = -1;
    for (var i = 0; i < parts.length; i++) {
      if (watchedIds.contains(parts[i].id)) last = i;
    }
    if (last < 0) continue;

    for (var i = last + 1; i < parts.length; i++) {
      final part = parts[i];
      if (watchedIds.contains(part.id)) continue;
      if (!_isOffered(part, blockAdult: blockAdult, now: today)) continue;
      if (exclude.contains('movie:${part.id}')) continue;
      picks.add(
        SagaPick(
          item: part,
          afterTitle: parts[last].displayTitle,
          collectionName: collection.name ?? '',
        ),
      );
      break;
    }
  }
  return picks;
}

bool _isOffered(
  SeerrDiscoverItem item, {
  required bool blockAdult,
  required DateTime now,
}) {
  if (blockAdult && item.adult) return false;
  final poster = item.posterPath;
  if (poster == null || poster.isEmpty) return false;
  if (item.mediaInfo?.status == SeerrMediaStatus.blocklisted) return false;
  final released = DateTime.tryParse(item.releaseDate ?? '');
  if (released == null || released.isAfter(now)) return false;
  return true;
}

int _byRelease(SeerrDiscoverItem a, SeerrDiscoverItem b) {
  final ad = DateTime.tryParse(a.releaseDate ?? '');
  final bd = DateTime.tryParse(b.releaseDate ?? '');
  if (ad == null && bd == null) return 0;
  if (ad == null) return 1;
  if (bd == null) return -1;
  return ad.compareTo(bd);
}
