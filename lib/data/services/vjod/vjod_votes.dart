import 'dart:convert';
import 'dart:math' as math;

import '../seerr/taste_profile.dart';

/// One "J'ai aimé" or "Bof" given at the end credits.
class VjodVote {
  /// `movie:<tmdb id>`, or `jellyfin:<item id>` when TMDB doesn't know it.
  final String key;
  final String title;
  final Set<TasteGenre> genres;
  final bool liked;
  final DateTime at;

  /// The source that put the title in front of the viewer, when VJOD knows:
  /// `trakt`, `tmdb`, `vjod`, `tonight`.
  final String? source;

  const VjodVote({
    required this.key,
    required this.title,
    required this.genres,
    required this.liked,
    required this.at,
    this.source,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title,
    'genres': [for (final g in genres) g.name],
    'liked': liked,
    'at': at.toUtc().toIso8601String(),
    if (source != null) 'source': source,
  };

  static VjodVote? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (key is! String || at == null) return null;
    return VjodVote(
      key: key,
      title: json['title'] as String? ?? '',
      genres: {
        if (json['genres'] case final List list)
          for (final name in list)
            if (name is String)
              if (TasteGenre.byName(name) case final genre?) genre,
      },
      liked: json['liked'] == true,
      at: at.toLocal(),
      source: json['source'] as String?,
    );
  }
}

/// Every vote kept, and the titles each source suggested lately, so a vote
/// can teach VJOD which source to trust.
class VjodVotes {
  final List<VjodVote> votes;

  /// Title key to the source that last suggested it.
  final Map<String, String> suggested;

  const VjodVotes({this.votes = const [], this.suggested = const {}});

  static const empty = VjodVotes();

  static const maxVotes = 300;
  static const maxSuggested = 400;

  /// How long a vote keeps half its weight on genres.
  static const halfLife = Duration(days: 120);

  VjodVote? voteFor(String key) {
    for (final v in votes.reversed) {
      if (v.key == key) return v;
    }
    return null;
  }

  VjodVotes record(VjodVote vote) {
    final withSource = vote.source != null || suggested[vote.key] == null
        ? vote
        : VjodVote(
            key: vote.key,
            title: vote.title,
            genres: vote.genres,
            liked: vote.liked,
            at: vote.at,
            source: suggested[vote.key],
          );
    final list = [
      for (final v in votes)
        if (v.key != vote.key) v,
      withSource,
    ];
    return VjodVotes(
      votes: list.length > maxVotes
          ? list.sublist(list.length - maxVotes)
          : list,
      suggested: suggested,
    );
  }

  /// Remembers which source showed these titles, newest last.
  VjodVotes noteSuggested(Map<String, String> bySource) {
    if (bySource.isEmpty) return this;
    final map = <String, String>{
      for (final e in suggested.entries)
        if (!bySource.containsKey(e.key)) e.key: e.value,
      ...bySource,
    };
    final excess = map.length - maxSuggested;
    if (excess > 0) {
      final keys = map.keys.take(excess).toList();
      keys.forEach(map.remove);
    }
    return VjodVotes(votes: votes, suggested: map);
  }

  /// What the votes say about each genre, -1 to 1, fading with age. A genre
  /// voted on once or twice stays near neutral.
  Map<TasteGenre, double> genreBias({DateTime? now}) {
    final at = now ?? DateTime.now();
    final sum = <TasteGenre, double>{};
    final weight = <TasteGenre, double>{};
    for (final v in votes) {
      final days = at.difference(v.at).inHours / 24;
      final w = math.pow(0.5, days / halfLife.inDays).toDouble();
      for (final g in v.genres) {
        sum[g] = (sum[g] ?? 0) + (v.liked ? w : -w);
        weight[g] = (weight[g] ?? 0) + w;
      }
    }
    const prior = 2.0;
    return {
      for (final g in sum.keys) g: (sum[g]! / (weight[g]! + prior)).clamp(-1.0, 1.0),
    };
  }

  /// How much to trust each source, from the votes on what it suggested:
  /// 1 when nothing is known, between 0.7 and 1.4 otherwise.
  Map<String, double> sourceWeights() {
    final up = <String, int>{};
    final down = <String, int>{};
    for (final v in votes) {
      final s = v.source;
      if (s == null) continue;
      if (v.liked) {
        up[s] = (up[s] ?? 0) + 1;
      } else {
        down[s] = (down[s] ?? 0) + 1;
      }
    }
    return {
      for (final s in {...up.keys, ...down.keys})
        s: ((2 + (up[s] ?? 0)) / (2 + (down[s] ?? 0))).clamp(0.7, 1.4),
    };
  }

  /// A factor for a title of [genres]: a little up for genres liked lately,
  /// a little down for "bof" ones, never to zero.
  static double factorFor(
    Set<TasteGenre> genres,
    Map<TasteGenre, double> bias,
  ) {
    if (genres.isEmpty || bias.isEmpty) return 1;
    var total = 0.0;
    for (final g in genres) {
      total += bias[g] ?? 0;
    }
    final mean = total / genres.length;
    return (1 + 0.35 * mean).clamp(0.7, 1.35);
  }

  String encode() => jsonEncode({
    'votes': [for (final v in votes) v.toJson()],
    'suggested': suggested,
  });

  static VjodVotes decode(String? source) {
    if (source == null || source.isEmpty) return empty;
    try {
      final json = jsonDecode(source);
      if (json is! Map) return empty;
      return VjodVotes(
        votes: [
          if (json['votes'] case final List list)
            for (final raw in list)
              if (VjodVote.fromJson(raw) case final vote?) vote,
        ],
        suggested: {
          if (json['suggested'] case final Map map)
            for (final e in map.entries)
              if (e.key is String && e.value is String)
                e.key as String: e.value as String,
        },
      );
    } catch (_) {
      return empty;
    }
  }
}
