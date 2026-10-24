import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/for_you_ranker.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/services/seerr/taste_profile.dart';

SeerrDiscoverItem _item(
  int id, {
  List<int> genres = const [],
  String? language,
  String mediaType = 'movie',
}) => SeerrDiscoverItem(
  id: id,
  mediaType: mediaType,
  title: 'Title $id',
  posterPath: '/p.jpg',
  releaseDate: '2020-01-01',
  voteAverage: 7.5,
  voteCount: 2000,
  genreIds: genres,
  originalLanguage: language,
);

void main() {
  group('TasteGenre', () {
    test('reads movie and series ids apart', () {
      expect(TasteGenre.of([28, 35], 'movie'), {
        TasteGenre.action,
        TasteGenre.comedy,
      });
      // Series fold action and adventure into one id.
      expect(TasteGenre.of([10759], 'tv'), {
        TasteGenre.action,
        TasteGenre.adventure,
      });
      expect(TasteGenre.of([10764], 'tv'), {TasteGenre.reality});
      expect(TasteGenre.of([10764], 'movie'), isEmpty);
    });
  });

  group('TasteProfile', () {
    test('survives a round trip', () {
      final profile = TasteProfile(
        mediaPref: TasteMediaPref.series,
        era: TasteEra.classic,
        liked: {TasteGenre.crime, TasteGenre.drama},
        avoided: {TasteGenre.reality},
        languages: {'fr', 'ru'},
        favorites: const [
          TastePick(tmdbId: 60574, mediaType: 'tv', title: 'Peaky Blinders'),
        ],
        updatedAt: DateTime.utc(2026, 10, 20),
      );
      final back = TasteProfile.decode(profile.encode());
      expect(back.mediaPref, TasteMediaPref.series);
      expect(back.era, TasteEra.classic);
      expect(back.liked, profile.liked);
      expect(back.avoided, profile.avoided);
      expect(back.languages, profile.languages);
      expect(back.favorites.single.title, 'Peaky Blinders');
      expect(back.answered, isTrue);
    });

    test('anything unreadable is an empty profile', () {
      expect(TasteProfile.decode(null).answered, isFalse);
      expect(TasteProfile.decode('not json').answered, isFalse);
      expect(TasteProfile.decode('{"liked":["nope"]}').liked, isEmpty);
    });
  });

  group('TasteMood', () {
    test('moods share no genre, so one is chosen when all its genres are', () {
      final seen = <TasteGenre>{};
      for (final mood in TasteMood.values) {
        for (final genre in mood.genres) {
          expect(seen.add(genre), isTrue, reason: '$genre is in two moods');
        }
      }
    });
  });

  group('TasteFeedback', () {
    test('remembers what was turned down, and counts its genres', () {
      final feedback = TasteFeedback.empty
          .notInterested('tv:1', {TasteGenre.reality})
          .notInterested('tv:2', {TasteGenre.reality, TasteGenre.comedy});
      final back = TasteFeedback.decode(feedback.encode());
      expect(back.hiddenKeys, {'tv:1', 'tv:2'});
      expect(back.genrePenalties[TasteGenre.reality], 2);
      expect(back.genrePenalties[TasteGenre.comedy], 1);
    });

    test('keeps only the latest hidden titles', () {
      var feedback = TasteFeedback.empty;
      for (var i = 0; i < TasteFeedback.maxHidden + 5; i++) {
        feedback = feedback.notInterested('movie:$i', const {});
      }
      expect(feedback.hidden, hasLength(TasteFeedback.maxHidden));
      expect(feedback.hidden.last, 'movie:${TasteFeedback.maxHidden + 4}');
    });
  });

  group('tasteFactor', () {
    double factor(
      SeerrDiscoverItem item, {
      TasteProfile profile = TasteProfile.empty,
      TasteFeedback feedback = TasteFeedback.empty,
      String mediaType = 'movie',
    }) => tasteFactor(item, mediaType, profile, feedback);

    test('nothing said changes nothing', () {
      expect(factor(_item(1, genres: [28])), 1.0);
    });

    test('an avoided genre is never shown', () {
      final profile = TasteProfile(avoided: {TasteGenre.reality});
      expect(
        factor(_item(1, genres: [10764]), profile: profile, mediaType: 'tv'),
        0,
      );
    });

    test('a liked genre lifts, a miss sinks a little', () {
      final profile = TasteProfile(liked: {TasteGenre.crime});
      expect(factor(_item(1, genres: [80]), profile: profile), greaterThan(1));
      expect(factor(_item(2, genres: [35]), profile: profile), lessThan(1));
    });

    test('languages and media type nudge without excluding', () {
      final profile = TasteProfile(
        languages: {'fr'},
        mediaPref: TasteMediaPref.movies,
      );
      expect(factor(_item(1, language: 'fr'), profile: profile), greaterThan(1));
      final english = factor(_item(2, language: 'en'), profile: profile);
      expect(english, lessThan(1));
      expect(english, greaterThan(0));
      final series = factor(
        _item(3, mediaType: 'tv'),
        profile: profile,
        mediaType: 'tv',
      );
      expect(series, lessThan(1));
      expect(series, greaterThan(0));
    });

    test('the era lifts recent or older titles without excluding any', () {
      final now = DateTime(2026, 10, 20);
      SeerrDiscoverItem dated(String date) => SeerrDiscoverItem(
        id: 1,
        mediaType: 'movie',
        title: 'T',
        releaseDate: date,
      );
      double factorFor(TasteEra era, String date) => tasteFactor(
        dated(date),
        'movie',
        TasteProfile(era: era),
        TasteFeedback.empty,
        now: now,
      );
      expect(factorFor(TasteEra.recent, '2025-05-01'), greaterThan(1));
      expect(factorFor(TasteEra.recent, '1994-05-01'), lessThan(1));
      expect(factorFor(TasteEra.classic, '1994-05-01'), greaterThan(1));
      expect(factorFor(TasteEra.classic, '2025-05-01'), lessThan(1));
      expect(factorFor(TasteEra.classic, '2025-05-01'), greaterThan(0));
      expect(factorFor(TasteEra.any, '1994-05-01'), 1.0);
    });

    test('turned-down genres sink, never below the floor', () {
      var feedback = TasteFeedback.empty;
      for (var i = 0; i < 20; i++) {
        feedback = feedback.notInterested('tv:$i', {TasteGenre.reality});
      }
      final value = factor(
        _item(1, genres: [10764], mediaType: 'tv'),
        feedback: feedback,
        mediaType: 'tv',
      );
      expect(value, closeTo(0.3, 1e-9));
    });
  });

  group('ranking with taste', () {
    test('an avoided genre leaves both kinds of rows', () {
      final seed = TasteSeed(
        tmdbId: 1,
        mediaType: 'tv',
        title: 'L\'Arène',
        weight: 1,
      );
      final recs = {
        seed.key: [
          for (var i = 0; i < 6; i++)
            _item(100 + i, genres: [10764], mediaType: 'tv'),
          for (var i = 0; i < 6; i++)
            _item(200 + i, genres: [80], mediaType: 'tv'),
        ],
      };
      final profile = TasteProfile(avoided: {TasteGenre.reality});
      double weigh(SeerrDiscoverItem item, String type) =>
          tasteFactor(item, type, profile, TasteFeedback.empty);

      final picks = ForYouRanker.rank(
        seeds: [seed],
        recommendationsBySeed: recs,
        weigh: weigh,
        now: DateTime(2026, 10, 20),
      );
      expect(picks.every((p) => p.item.id >= 200), isTrue);

      final rows = ForYouRanker.becauseRows(
        seeds: [seed],
        recommendationsBySeed: recs,
        weigh: weigh,
        now: DateTime(2026, 10, 20),
      );
      expect(rows.single.items.every((i) => i.item.id >= 200), isTrue);
    });

    test('a seed only picked reads as liked, a watched one wins', () {
      final seeds = ForYouRanker.buildSeeds(
        recent: const [TasteSignal(tmdbId: 1, mediaType: 'movie', title: 'A')],
        picked: const [
          TasteSignal(tmdbId: 1, mediaType: 'movie', title: 'A'),
          TasteSignal(tmdbId: 2, mediaType: 'movie', title: 'B'),
        ],
        requested: const [
          TasteSignal(tmdbId: 3, mediaType: 'movie', title: ''),
        ],
      );
      final byId = {for (final s in seeds) s.tmdbId: s};
      expect(byId[1]!.source, TasteSource.watched);
      expect(byId[2]!.source, TasteSource.picked);
      expect(byId[3]!.source, TasteSource.requested);
      // Watched and picked add up.
      expect(byId[1]!.weight, greaterThan(byId[2]!.weight));
    });

    test('a seed without a title gets no Because row', () {
      const seed = TasteSeed(
        tmdbId: 3,
        mediaType: 'movie',
        title: '',
        weight: 1,
      );
      final rows = ForYouRanker.becauseRows(
        seeds: [seed],
        recommendationsBySeed: {
          seed.key: [for (var i = 0; i < 8; i++) _item(300 + i)],
        },
        now: DateTime(2026, 10, 20),
      );
      expect(rows, isEmpty);
    });
  });
}
