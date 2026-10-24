import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../util/parental_filter.dart';
import '../../models/aggregated_item.dart';
import '../../models/home_row.dart';
import '../../utils/blocked_ratings.dart';

/// How old a viewer must be for a Seerr title, as TMDB knows it.
typedef AgeInfo = ({String? certification, List<int> genres});

/// Countries whose rating is read, first found wins: France, then the
/// boards TMDB fills most often.
const _ratingCountries = ['FR', 'US', 'GB', 'DE'];

/// TMDB genres a title with no rating may still be shown under: animation,
/// family, and kids' television.
const _childGenres = {16, 10751, 10762};

/// The rating and genres in a film's or a series' details from Seerr.
AgeInfo parseAgeInfo(Map<String, dynamic> details) {
  final byCountry = <String, String>{};
  void note(Object? country, Object? rating) {
    final value = rating?.toString().trim() ?? '';
    if (country is String && value.isNotEmpty) {
      byCountry.putIfAbsent(country, () => value);
    }
  }

  final releases = details['releases'];
  if (releases is Map && releases['results'] is List) {
    for (final country in releases['results'] as List) {
      if (country is! Map || country['release_dates'] is! List) continue;
      for (final release in country['release_dates'] as List) {
        if (release is Map) note(country['iso_3166_1'], release['certification']);
      }
    }
  }
  final ratings = details['contentRatings'];
  if (ratings is Map && ratings['results'] is List) {
    for (final entry in ratings['results'] as List) {
      if (entry is Map) note(entry['iso_3166_1'], entry['rating']);
    }
  }
  final genres = details['genres'];
  return (
    certification: [
      for (final country in _ratingCountries) ?byCountry[country],
    ].firstOrNull,
    genres: [
      if (genres is List)
        for (final genre in genres)
          if (genre is Map && genre['id'] is int) genre['id'] as int,
    ],
  );
}

/// Whether a viewer under [filter] may see a title with [info]. A title
/// with no rating passes only as a children's genre: on a child's profile
/// a gap in TMDB shouldn't let anything through.
bool ageAllows(ParentalFilter filter, AgeInfo info) {
  final rating = info.certification;
  if (rating == null) return info.genres.any(_childGenres.contains);
  return !filter.isBlockedRating(rating);
}

/// Keeps titles from Seerr, which carry no rating, behind the ratings the
/// viewer blocked: their rating is looked up once, and until it is known
/// the title stays hidden.
class SeerrAgeGate extends ChangeNotifier {
  SeerrAgeGate(this._lookup);

  final Future<AgeInfo> Function(String mediaType, int tmdbId) _lookup;

  final Map<String, AgeInfo> _known = {};
  final Set<String> _pending = {};

  /// Bumped whenever a lookup lands, for whoever caches what passed.
  int get version => _version;
  int _version = 0;

  /// Lookups running at once.
  static const _concurrency = 4;
  final List<(String, int)> _queue = [];
  int _running = 0;

  /// Whether the title may show. Null while its rating is being looked up.
  bool? allows(String mediaType, int tmdbId, {ParentalFilter? filter}) {
    final active = filter ?? activeParentalFilter;
    if (!active.isActive) return true;
    final info = _known['$mediaType:$tmdbId'];
    if (info != null) return ageAllows(active, info);
    _request(mediaType, tmdbId);
    return null;
  }

  void _request(String mediaType, int tmdbId) {
    if (!_pending.add('$mediaType:$tmdbId')) return;
    _queue.add((mediaType, tmdbId));
    _drain();
  }

  void _drain() {
    while (_running < _concurrency && _queue.isNotEmpty) {
      final (mediaType, tmdbId) = _queue.removeAt(0);
      _running++;
      _lookup(mediaType, tmdbId)
          .then((info) => _known['$mediaType:$tmdbId'] = info)
          .catchError((Object e) {
            // Left hidden for the session rather than asked about forever.
            debugPrint('[AgeGate] No rating for $mediaType $tmdbId: $e');
            return (certification: null, genres: const <int>[]);
          })
          .whenComplete(() {
            _running--;
            _settled();
            _drain();
          });
    }
  }

  Timer? _notify;

  /// One rebuild for a burst of lookups rather than one each.
  void _settled() {
    _notify?.cancel();
    _notify = Timer(const Duration(milliseconds: 250), () {
      _version++;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _notify?.cancel();
    super.dispose();
  }
}

/// [rows] without the Seerr titles [allows] doesn't let through, or isn't
/// sure about yet. A row left with nothing goes too.
List<HomeRow> withAgeGate(
  List<HomeRow> rows,
  bool? Function(String mediaType, int tmdbId) allows,
) {
  final result = <HomeRow>[];
  for (final row in rows) {
    final items = [
      for (final item in row.items)
        if (item.serverId != 'seerr' || _passes(item, allows)) item,
    ];
    if (items.length == row.items.length) {
      result.add(row);
    } else if (items.isNotEmpty) {
      result.add(row.copyWith(items: items, totalCount: items.length));
    }
  }
  return result;
}

bool _passes(
  AggregatedItem item,
  bool? Function(String mediaType, int tmdbId) allows,
) {
  final id = int.tryParse(item.id);
  if (id == null) return false;
  final type = item.rawData['SeerrMediaType'] ??
      (item.rawData['Type'] == 'Series' ? 'tv' : 'movie');
  return allows(type == 'tv' ? 'tv' : 'movie', id) ?? false;
}
