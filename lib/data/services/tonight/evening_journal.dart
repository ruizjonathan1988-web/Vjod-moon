import 'dart:convert';

import '../seerr/taste_profile.dart';
import 'tonight_models.dart';

/// One sitting with one title: when it started, what it was, how much of it
/// was watched, and in what company.
///
/// Several episodes of a series in a row are one sitting, so a binge counts
/// as one evening rather than outweighing everything else.
class JournalEntry {
  /// Local time the sitting started.
  final DateTime at;

  /// The library item: the movie, or the series an episode belongs to.
  final String itemId;

  /// `movie` or `tv`.
  final String mediaType;
  final int? tmdbId;
  final String title;
  final Set<TasteGenre> genres;

  /// The movie's length, or one episode's.
  final int? runtimeMinutes;
  final int? year;

  /// The library's community rating, out of 10.
  final double? rating;

  /// Minutes actually watched over the sitting.
  final int watchedMinutes;

  /// Episodes started in the sitting. One for a movie.
  final int episodes;

  /// Watched to the end, or close enough (credits aside).
  final bool finished;
  final TonightCompany? company;
  final TonightDevice? device;

  /// Started from the Tonight screen.
  final bool fromTonight;

  /// Rebuilt from the server's play history rather than seen live, so only
  /// the date and the title are known for sure.
  final bool backfilled;

  const JournalEntry({
    required this.at,
    required this.itemId,
    required this.mediaType,
    required this.title,
    this.tmdbId,
    this.genres = const {},
    this.runtimeMinutes,
    this.year,
    this.rating,
    this.watchedMinutes = 0,
    this.episodes = 1,
    this.finished = false,
    this.company,
    this.device,
    this.fromTonight = false,
    this.backfilled = false,
  });

  String? get tmdbKey => tmdbId == null ? null : '$mediaType:$tmdbId';

  TonightSlot get slot => TonightSlot.of(at);

  /// How the sitting went, from -1 (dropped early) to 1 (watched through).
  double get outcome {
    if (finished) return 1;
    if (backfilled) return 1;
    if (watchedMinutes < 15) return -1;
    // A long sitting, or a few episodes, says it held the viewer.
    if (episodes >= 2 || watchedMinutes >= 45) return 0.6;
    return 0.1;
  }

  /// Dropped within the first quarter of an hour.
  bool get abandoned => !finished && !backfilled && watchedMinutes < 15;

  JournalEntry copyWith({
    int? watchedMinutes,
    int? episodes,
    bool? finished,
    TonightCompany? company,
    bool? fromTonight,
    Set<TasteGenre>? genres,
    int? tmdbId,
    int? runtimeMinutes,
    int? year,
    double? rating,
  }) => JournalEntry(
    at: at,
    itemId: itemId,
    mediaType: mediaType,
    title: title,
    tmdbId: tmdbId ?? this.tmdbId,
    genres: genres ?? this.genres,
    runtimeMinutes: runtimeMinutes ?? this.runtimeMinutes,
    year: year ?? this.year,
    rating: rating ?? this.rating,
    watchedMinutes: watchedMinutes ?? this.watchedMinutes,
    episodes: episodes ?? this.episodes,
    finished: finished ?? this.finished,
    company: company ?? this.company,
    device: device,
    fromTonight: fromTonight ?? this.fromTonight,
    backfilled: backfilled,
  );

  Map<String, dynamic> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'id': itemId,
    'type': mediaType,
    'title': title,
    'tmdb': ?tmdbId,
    if (genres.isNotEmpty) 'genres': [for (final g in genres) g.name],
    'runtime': ?runtimeMinutes,
    'year': ?year,
    'rating': ?rating,
    'watched': watchedMinutes,
    if (episodes != 1) 'episodes': episodes,
    if (finished) 'finished': true,
    'company': ?company?.name,
    'device': ?device?.name,
    if (fromTonight) 'tonight': true,
    if (backfilled) 'backfilled': true,
  };

  static JournalEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    final id = json['id'];
    final type = json['type'];
    if (at == null || id is! String || (type != 'movie' && type != 'tv')) {
      return null;
    }
    return JournalEntry(
      at: at.toLocal(),
      itemId: id,
      mediaType: type as String,
      title: json['title'] as String? ?? '',
      tmdbId: (json['tmdb'] as num?)?.toInt(),
      genres: {
        if (json['genres'] case final List list)
          for (final name in list)
            if (name is String)
              if (TasteGenre.byName(name) case final genre?) genre,
      },
      runtimeMinutes: (json['runtime'] as num?)?.toInt(),
      year: (json['year'] as num?)?.toInt(),
      rating: (json['rating'] as num?)?.toDouble(),
      watchedMinutes: (json['watched'] as num?)?.toInt() ?? 0,
      episodes: (json['episodes'] as num?)?.toInt() ?? 1,
      finished: json['finished'] == true,
      company: TonightCompany.values.asNameMap()[json['company']],
      device: TonightDevice.values.asNameMap()[json['device']],
      fromTonight: json['tonight'] == true,
      backfilled: json['backfilled'] == true,
    );
  }
}

/// Every sitting kept, oldest first.
class EveningJournal {
  final List<JournalEntry> entries;

  const EveningJournal(this.entries);

  static const empty = EveningJournal([]);

  /// Sittings kept. Older ones fall off past this.
  static const maxEntries = 400;

  /// How long after a series sitting the next episode still belongs to it.
  static const sittingGap = Duration(hours: 4);

  /// Adds a sitting, or folds it into the one it continues: the same series
  /// picked up again within a few hours.
  EveningJournal record(JournalEntry entry) {
    final list = [...entries];
    if (entry.mediaType == 'tv') {
      for (var i = list.length - 1; i >= 0; i--) {
        final previous = list[i];
        if (entry.at.difference(previous.at) > sittingGap) break;
        if (previous.itemId != entry.itemId || previous.backfilled) continue;
        list[i] = previous.copyWith(
          watchedMinutes: previous.watchedMinutes + entry.watchedMinutes,
          episodes: previous.episodes + 1,
          finished: previous.finished || entry.finished,
          company: previous.company ?? entry.company,
          fromTonight: previous.fromTonight || entry.fromTonight,
        );
        return EveningJournal(list);
      }
    }
    list.add(entry);
    list.sort((a, b) => a.at.compareTo(b.at));
    return EveningJournal(
      list.length > maxEntries ? list.sublist(list.length - maxEntries) : list,
    );
  }

  /// Adds plays rebuilt from the server's history, skipping any already
  /// known: the same item on the same day.
  EveningJournal backfill(Iterable<JournalEntry> past) {
    String dayKey(JournalEntry e) =>
        '${e.itemId}@${e.at.year}-${e.at.month}-${e.at.day}';
    final known = {for (final e in entries) dayKey(e)};
    var journal = this;
    for (final entry in past) {
      if (known.add(dayKey(entry))) {
        final list = [...journal.entries, entry]
          ..sort((a, b) => a.at.compareTo(b.at));
        journal = EveningJournal(
          list.length > maxEntries
              ? list.sublist(list.length - maxEntries)
              : list,
        );
      }
    }
    return journal;
  }

  /// TMDB keys of everything watched, so nothing seen is suggested again.
  Set<String> get watchedTmdbKeys => {
    for (final e in entries)
      if (e.tmdbKey case final key? when e.finished || e.backfilled) key,
  };

  String encode() => jsonEncode([for (final e in entries) e.toJson()]);

  static EveningJournal decode(String? source) {
    if (source == null || source.isEmpty) return empty;
    try {
      final json = jsonDecode(source);
      if (json is! List) return empty;
      final list = [
        for (final raw in json)
          if (JournalEntry.fromJson(raw) case final entry?) entry,
      ]..sort((a, b) => a.at.compareTo(b.at));
      return EveningJournal(list);
    } catch (_) {
      return empty;
    }
  }
}
