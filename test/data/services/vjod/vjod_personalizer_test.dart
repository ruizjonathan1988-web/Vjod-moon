import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/seed_recommendations.dart';
import 'package:moonfin/data/services/seerr/taste_profile.dart';
import 'package:moonfin/data/services/tonight/evening_journal.dart';
import 'package:moonfin/data/services/tonight/tonight_models.dart';
import 'package:moonfin/data/services/vjod/vjod_collections.dart';
import 'package:moonfin/data/services/vjod/vjod_personalizer.dart';
import 'package:moonfin/data/services/vjod/vjod_votes.dart';

VjodCandidate<String> c(String id, Set<TasteGenre> genres, {double taste = 1}) =>
    VjodCandidate(item: id, key: 'movie:$id', genres: genres, taste: taste);

void main() {
  final now = DateTime(2026, 10, 26, 21);

  JournalEntry watched(String title, Set<TasteGenre> genres, int daysAgo) =>
      JournalEntry(
        at: now.subtract(Duration(days: daysAgo)),
        itemId: title,
        mediaType: 'movie',
        title: title,
        genres: genres,
        watchedMinutes: 110,
        finished: true,
      );

  // Oldest first, as the journal keeps them.
  final comedyBinge = EveningJournal([
    for (var i = 5; i >= 0; i--)
      watched('Comédie $i', {TasteGenre.comedy}, 1 + i),
  ]);

  test('off, a row keeps the catalogue order', () {
    final placed = VjodPersonalizer.arrange([
      c('a', {TasteGenre.horror}),
      c('b', {TasteGenre.comedy}),
    ], VjodSignals.off);
    expect([for (final p in placed) p.item], ['a', 'b']);
    expect(placed.every((p) => p.why == null), isTrue);
  });

  test('a third of a personalized row lies outside the habits', () {
    final signals = VjodSignals.build(
      enabled: true,
      journal: comedyBinge,
      profile: TasteProfile.empty,
      now: now,
    );
    final candidates = [
      for (var i = 0; i < 12; i++) c('comedy$i', {TasteGenre.comedy}),
      for (var i = 0; i < 6; i++) c('docu$i', {TasteGenre.documentary}),
    ];
    final placed = VjodPersonalizer.arrange(candidates, signals, seed: 1);
    final firstNine = placed.take(9).toList();
    final discoveries = firstNine.where((p) => p.why == VjodWhy.discovery);
    expect(discoveries, hasLength(3));
    expect(
      discoveries.every((p) => p.item.startsWith('docu')),
      isTrue,
    );
  });

  test('a preference lowers, it never removes; an explicit no does', () {
    final signals = VjodSignals.build(
      enabled: true,
      journal: comedyBinge,
      profile: TasteProfile.empty,
      mood: TonightMood.laugh,
      now: now,
    );
    final placed = VjodPersonalizer.arrange([
      c('horror', {TasteGenre.horror}),
      c('comedy', {TasteGenre.comedy}),
      c('banned', {TasteGenre.war}, taste: 0),
    ], signals);
    final ids = [for (final p in placed) p.item];
    expect(ids, contains('horror'));
    expect(ids, isNot(contains('banned')));
    expect(ids.first, 'comedy');
  });

  test('recent sittings explain a pick, and fade within weeks', () {
    final signals = VjodSignals.build(
      enabled: true,
      journal: comedyBinge,
      profile: TasteProfile.empty,
      now: now,
    );
    final placed = VjodPersonalizer.arrange([
      c('comedy', {TasteGenre.comedy}),
    ], signals);
    expect(placed.single.why, VjodWhy.recent);
    expect(placed.single.because, 'Comédie 0');

    final later = VjodSignals.build(
      enabled: true,
      journal: comedyBinge,
      profile: TasteProfile.empty,
      now: now.add(const Duration(days: 40)),
    );
    expect(later.recent, isEmpty);
  });

  test('a mood lasts the evening, not the next day', () {
    final stored = VjodMoodStore.write(TonightMood.chills, now: now);
    expect(VjodMoodStore.read(stored, now: now), TonightMood.chills);
    expect(
      VjodMoodStore.read(stored, now: now.add(const Duration(hours: 4))),
      TonightMood.chills,
    );
    expect(
      VjodMoodStore.read(stored, now: now.add(const Duration(days: 1))),
      isNull,
    );
  });

  test('votes tilt genres and teach which source to trust', () {
    var votes = VjodVotes.empty.noteSuggested({
      'movie:1': 'trakt',
      'movie:2': 'trakt',
      'movie:3': 'tmdb',
    });
    VjodVote vote(String key, bool liked, Set<TasteGenre> g) => VjodVote(
      key: key,
      title: key,
      genres: g,
      liked: liked,
      at: now,
    );
    votes = votes
        .record(vote('movie:1', true, {TasteGenre.scifi}))
        .record(vote('movie:2', true, {TasteGenre.scifi}))
        .record(vote('movie:3', false, {TasteGenre.romance}));
    final weights = VjodVotes.decode(votes.encode()).sourceWeights();
    expect(weights['trakt'], greaterThan(1));
    expect(weights['tmdb'], lessThan(1));
    final bias = votes.genreBias(now: now);
    expect(bias[TasteGenre.scifi], greaterThan(0));
    expect(bias[TasteGenre.romance], lessThan(0));
    expect(
      VjodVotes.factorFor({TasteGenre.romance}, bias),
      inInclusiveRange(0.7, 1),
    );
  });

  test('MDBList agreement moves a pick a little, one source says nothing', () {
    expect(VjodPersonalizer.ratingsFactor(null), 1);
    expect(VjodPersonalizer.ratingsFactor({'imdb': 8.5}), 1);
    expect(
      VjodPersonalizer.ratingsFactor({'imdb': 8.6, 'tomatoes': 95}),
      greaterThan(1.1),
    );
    expect(
      VjodPersonalizer.ratingsFactor({'imdb': 4.1, 'metacritic': 30}),
      0.8,
    );
  });

  test('what two communities both name comes first', () {
    expect(mergeCommunities([1, 2, 3], [3, 4, 1]), [1, 3, 2, 4]);
  });

  test('every collection has a title and a sound query', () {
    final ids = <String>{};
    for (final collection in vjodCollections) {
      expect(ids.add(collection.id), isTrue, reason: collection.id);
      expect(collection.title(true), isNotEmpty);
      expect(['movie', 'tv'], contains(collection.query.mediaType));
    }
    expect(vjodThemeOfDay(now), isNotNull);
  });
}
