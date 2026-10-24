import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/for_you_ranker.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/services/seerr/taste_profile.dart';
import 'package:moonfin/data/services/tonight/evening_journal.dart';
import 'package:moonfin/data/services/tonight/habit_model.dart';
import 'package:moonfin/data/services/tonight/tonight_engine.dart';
import 'package:moonfin/data/services/tonight/tonight_models.dart';

// A Friday, 21:00.
final _friday = DateTime(2026, 10, 16, 21);

TonightCandidate _c(
  int id, {
  Set<TasteGenre> genres = const {TasteGenre.drama},
  String type = 'movie',
  int? runtime = 110,
  double rating = 7.2,
  int votes = 3000,
  int? ratingAge,
  bool inProgress = false,
  bool rewatch = false,
  TonightAvailability availability = TonightAvailability.requestable,
}) => TonightCandidate(
  key: '$type:$id',
  mediaType: type,
  tmdbId: id,
  title: 'T$id',
  genres: genres,
  runtimeMinutes: runtime,
  year: 2018,
  rating: rating,
  voteCount: votes,
  ratingAge: ratingAge,
  inProgress: inProgress,
  rewatch: rewatch,
  availability: availability,
);

TonightAnswers _answers({
  TonightCompany company = TonightCompany.alone,
  TonightTime time = TonightTime.any,
  TonightMood mood = TonightMood.surprise,
  KidsAge kids = KidsAge.from7to12,
}) => TonightAnswers(
  company: company,
  time: time,
  mood: mood,
  kidsAge: kids,
  at: _friday,
);

JournalEntry _entry(
  DateTime at, {
  String id = 'a',
  Set<TasteGenre> genres = const {TasteGenre.crime},
  String type = 'movie',
  bool finished = true,
  int watched = 100,
  TonightCompany? company,
  TonightDevice? device,
  int? tmdb,
  int runtime = 110,
}) => JournalEntry(
  at: at,
  itemId: id,
  mediaType: type,
  title: id,
  tmdbId: tmdb,
  genres: genres,
  runtimeMinutes: runtime,
  watchedMinutes: watched,
  finished: finished,
  company: company,
  device: device,
);

List<TonightCandidate> _pool() => [
  for (var i = 0; i < 10; i++) _c(100 + i, genres: {TasteGenre.comedy}),
  for (var i = 0; i < 10; i++) _c(200 + i, genres: {TasteGenre.horror}),
  for (var i = 0; i < 10; i++)
    _c(300 + i, genres: {TasteGenre.drama, TasteGenre.crime}),
  for (var i = 0; i < 10; i++)
    _c(400 + i, genres: {TasteGenre.scifi, TasteGenre.adventure}),
  for (var i = 0; i < 6; i++)
    _c(500 + i, genres: {TasteGenre.family, TasteGenre.animation}, runtime: 90),
];

void main() {
  group('TonightSlot', () {
    test('reads the kind of day and the part of it', () {
      expect(TonightSlot.of(DateTime(2026, 10, 16, 21)).key, 'friday_evening');
      expect(TonightSlot.of(DateTime(2026, 10, 14, 14)).key, 'weekday_daytime');
      expect(TonightSlot.of(DateTime(2026, 10, 17, 23)).key, 'saturday_late');
    });

    test('past midnight still belongs to the night before', () {
      // 01:00 on Saturday is Friday night.
      expect(TonightSlot.of(DateTime(2026, 10, 17, 1)).key, 'friday_late');
    });
  });

  group('ratingAge', () {
    test('reads French, US and UK ratings', () {
      expect(ratingAge('FR-12'), 12);
      expect(ratingAge('Tous publics'), 0);
      expect(ratingAge('PG-13'), 13);
      expect(ratingAge('TV-Y7'), 7);
      expect(ratingAge('TV-MA'), 17);
      expect(ratingAge('R'), 17);
      expect(ratingAge('12A'), 12);
      expect(ratingAge('U'), 0);
      expect(ratingAge(null), isNull);
      expect(ratingAge('NR'), isNull);
    });
  });

  group('TasteGenre.fromNames', () {
    test('reads English and French TMDB names, split or whole', () {
      expect(TasteGenre.fromNames(['Science-Fiction & Fantastique']), {
        TasteGenre.scifi,
        TasteGenre.fantasy,
      });
      expect(TasteGenre.fromNames(['Action & Adventure', 'Comédie']), {
        TasteGenre.action,
        TasteGenre.adventure,
        TasteGenre.comedy,
      });
      expect(TasteGenre.fromNames(['Drame', 'Policier']), {
        TasteGenre.drama,
        TasteGenre.crime,
      });
      expect(TasteGenre.fromNames(['Sci-Fi & Fantasy']), {
        TasteGenre.scifi,
        TasteGenre.fantasy,
      });
    });
  });

  group('EveningJournal', () {
    test('folds episodes of one sitting together', () {
      var journal = EveningJournal.empty;
      journal = journal.record(
        _entry(_friday, id: 's', type: 'tv', watched: 40, finished: true),
      );
      journal = journal.record(
        _entry(
          _friday.add(const Duration(minutes: 45)),
          id: 's',
          type: 'tv',
          watched: 42,
        ),
      );
      expect(journal.entries, hasLength(1));
      expect(journal.entries.single.episodes, 2);
      expect(journal.entries.single.watchedMinutes, 82);

      // The next day is a new sitting.
      journal = journal.record(
        _entry(
          _friday.add(const Duration(days: 1)),
          id: 's',
          type: 'tv',
          watched: 40,
        ),
      );
      expect(journal.entries, hasLength(2));
    });

    test('survives a round trip', () {
      final journal = EveningJournal.empty.record(
        _entry(
          _friday,
          company: TonightCompany.couple,
          device: TonightDevice.tv,
          tmdb: 42,
        ),
      );
      final back = EveningJournal.decode(journal.encode());
      final entry = back.entries.single;
      expect(entry.company, TonightCompany.couple);
      expect(entry.device, TonightDevice.tv);
      expect(entry.tmdbKey, 'movie:42');
      expect(entry.genres, {TasteGenre.crime});
      expect(entry.at, _friday);
    });

    test('a backfill skips what is already known', () {
      final journal = EveningJournal.empty.record(_entry(_friday, id: 'x'));
      final filled = journal.backfill([
        _entry(_friday.add(const Duration(hours: 1)), id: 'x'),
        _entry(_friday.add(const Duration(hours: 2)), id: 'y'),
      ]);
      expect(filled.entries.map((e) => e.itemId), ['x', 'y']);
    });

    test('dropping early reads as a bad sitting', () {
      final dropped = _entry(_friday, finished: false, watched: 8);
      expect(dropped.abandoned, isTrue);
      expect(dropped.outcome, lessThan(0));
    });
  });

  group('HabitModel', () {
    test('learns what each slot holds and leans on the rest', () {
      final entries = [
        // Friday nights: crime, as a couple.
        for (var w = 0; w < 6; w++)
          _entry(
            _friday.subtract(Duration(days: 7 * (w + 1))),
            id: 'f$w',
            genres: {TasteGenre.crime},
            company: TonightCompany.couple,
            device: TonightDevice.tv,
          ),
        // Weekday afternoons: animation with the family.
        for (var d = 0; d < 6; d++)
          _entry(
            DateTime(2026, 10, 7 - d, 15),
            id: 'w$d',
            genres: {TasteGenre.animation},
            company: TonightCompany.family,
          ),
      ];
      final model = HabitModel.build(entries, now: _friday);
      final friday = model.forContext(slot: TonightSlot.of(_friday));
      expect(
        friday.genreFit({TasteGenre.crime}),
        greaterThan(friday.genreFit({TasteGenre.animation})),
      );
      final family = model.forContext(
        slot: TonightSlot.of(_friday),
        company: TonightCompany.family,
      );
      expect(
        family.genreFit({TasteGenre.animation}),
        greaterThan(family.genreFit({TasteGenre.crime})),
      );
      expect(
        model.suggestCompany(TonightSlot.of(_friday), TonightDevice.tv),
        TonightCompany.couple,
      );
    });

    test('what was dropped counts against its genres', () {
      final entries = [
        for (var i = 0; i < 5; i++)
          _entry(
            _friday.subtract(Duration(days: i + 1)),
            id: 'h$i',
            genres: {TasteGenre.horror},
            finished: false,
            watched: 5,
          ),
        for (var i = 0; i < 5; i++)
          _entry(
            _friday.subtract(Duration(days: i + 1, hours: 2)),
            id: 'c$i',
            genres: {TasteGenre.comedy},
          ),
      ];
      final model = HabitModel.build(entries, now: _friday);
      expect(
        model.global.genreFit({TasteGenre.horror}),
        lessThan(model.global.genreFit({TasteGenre.comedy})),
      );
    });
  });

  group('TonightEngine', () {
    TonightResult rank({
      List<TonightCandidate>? candidates,
      TonightAnswers? answers,
      HabitModel habits = HabitModel.empty,
      List<JournalEntry> journal = const [],
      Map<String, int> rejections = const {},
      Set<String> exclude = const {},
      Set<String> watched = const {},
      TasteProfile profile = TasteProfile.empty,
      List<TasteSeed> seeds = const [],
      Map<String, List<SeerrDiscoverItem>> recommendations = const {},
    }) => TonightEngine.rank(
      TonightInput(
        candidates: candidates ?? _pool(),
        answers: answers ?? _answers(),
        now: _friday,
        habits: habits,
        journal: journal,
        rejections: rejections,
        exclude: exclude,
        watched: watched,
        profile: profile,
        seeds: seeds,
        recommendations: recommendations,
      ),
    );

    test('offers six picks, the last a joker', () {
      final result = rank();
      expect(result.picks, hasLength(TonightEngine.pickCount));
      expect(result.picks.where((p) => p.isJoker), hasLength(1));
      expect(result.picks.last.isJoker, isTrue);
      expect(result.picks.map((p) => p.candidate.key).toSet(), hasLength(6));
    });

    test('a mood keeps to its genres', () {
      final laugh = rank(answers: _answers(mood: TonightMood.laugh));
      for (final pick in laugh.picks) {
        expect(
          pick.candidate.genres.any(
            {TasteGenre.comedy, TasteGenre.animation, TasteGenre.family}
                .contains,
          ),
          isTrue,
          reason: pick.candidate.title,
        );
        expect(pick.candidate.genres.contains(TasteGenre.horror), isFalse);
      }
      final chills = rank(answers: _answers(mood: TonightMood.chills));
      expect(chills.picks.first.candidate.genres, contains(TasteGenre.horror));
    });

    test('a strict mood loosens when too little fits', () {
      final few = [
        _c(1, genres: {TasteGenre.comedy}),
        for (var i = 0; i < 12; i++) _c(10 + i, genres: {TasteGenre.drama}),
      ];
      final result = rank(
        candidates: few,
        answers: _answers(mood: TonightMood.laugh),
      );
      expect(result.relaxedMood, isTrue);
      expect(result.picks.first.candidate.key, 'movie:1');
    });

    test('the time left rules out what is too long', () {
      final candidates = [
        ..._pool(),
        _c(900, genres: {TasteGenre.comedy}, runtime: 160, rating: 9),
      ];
      final result = rank(
        candidates: candidates,
        answers: _answers(time: TonightTime.short),
      );
      for (final pick in result.picks) {
        final runtime = pick.candidate.runtimeMinutes;
        if (runtime != null) expect(runtime, lessThanOrEqualTo(100));
      }
    });

    test('a family evening keeps to what suits the kids', () {
      final candidates = [
        ..._pool(),
        _c(600, genres: {TasteGenre.comedy}, ratingAge: 16),
        _c(601, genres: {TasteGenre.adventure}, ratingAge: 6),
      ];
      final result = rank(
        candidates: candidates,
        answers: _answers(
          company: TonightCompany.family,
          mood: TonightMood.surprise,
        ),
      );
      final keys = result.picks.map((p) => p.candidate.key).toSet();
      expect(keys, isNot(contains('movie:600')));
      for (final pick in result.picks) {
        final c = pick.candidate;
        final age = c.ratingAge;
        if (age != null) {
          expect(age, lessThanOrEqualTo(KidsAge.from7to12.maxRatingAge));
        } else {
          expect(c.genres.contains(TasteGenre.horror), isFalse);
          expect(
            c.genres.any(
              {TasteGenre.family, TasteGenre.animation, TasteGenre.kids}
                  .contains,
            ),
            isTrue,
          );
        }
      }
    });

    test('habits of the slot lead when the evening says nothing', () {
      final journal = [
        for (var w = 0; w < 10; w++)
          _entry(
            _friday.subtract(Duration(days: 7 * (w + 1))),
            id: 'f$w',
            genres: {TasteGenre.scifi, TasteGenre.adventure},
          ),
      ];
      // Comfort asks for none of these genres, so habits decide.
      final result = rank(
        habits: HabitModel.build(journal, now: _friday),
        journal: journal,
        answers: _answers(mood: TonightMood.comfort),
        candidates: [
          for (var i = 0; i < 8; i++) _c(300 + i, genres: {TasteGenre.drama}),
          for (var i = 0; i < 8; i++) _c(400 + i, genres: {TasteGenre.scifi}),
        ],
      );
      expect(
        result.picks.first.candidate.genres,
        contains(TasteGenre.scifi),
      );
    });

    test('a title turned down sinks, and an excluded one is gone', () {
      final first = rank(answers: _answers(mood: TonightMood.chills));
      final top = first.picks.first.candidate.key;
      final again = rank(
        answers: _answers(mood: TonightMood.chills),
        rejections: {top: 3},
      );
      expect(again.picks.first.candidate.key, isNot(top));
      final excluded = rank(
        answers: _answers(mood: TonightMood.chills),
        exclude: {top},
      );
      expect(
        excluded.picks.map((p) => p.candidate.key),
        isNot(contains(top)),
      );
    });

    test('what was watched is not offered, except to rewatch', () {
      final candidates = [
        _c(1, genres: {TasteGenre.comedy}, rating: 9.5),
        _c(2, genres: {TasteGenre.comedy}, rating: 9.5, rewatch: true),
        for (var i = 0; i < 10; i++) _c(10 + i, genres: {TasteGenre.comedy}),
      ];
      final normal = rank(candidates: candidates, watched: {'movie:1'});
      final keys = normal.picks.map((p) => p.candidate.key);
      expect(keys, isNot(contains('movie:1')));
      expect(keys, isNot(contains('movie:2')));
      final comfort = rank(
        candidates: candidates,
        watched: {'movie:1'},
        answers: _answers(mood: TonightMood.comfort),
      );
      expect(comfort.picks.map((p) => p.candidate.key), contains('movie:2'));
    });

    test('a series in progress is offered to resume, with that reason', () {
      final candidates = [
        ..._pool(),
        _c(
          700,
          type: 'tv',
          genres: {TasteGenre.drama},
          runtime: 45,
          inProgress: true,
          availability: TonightAvailability.inLibrary,
        ),
      ];
      final result = rank(
        candidates: candidates,
        answers: _answers(mood: TonightMood.comfort),
      );
      final resume = result.picks.where((p) => p.candidate.key == 'tv:700');
      expect(resume, isNotEmpty);
      expect(resume.first.reason.kind, TonightReasonKind.resume);
    });

    test('a favourite title pulls its neighbours up, and says so', () {
      const seed = TasteSeed(
        tmdbId: 1,
        mediaType: 'movie',
        title: 'Heat',
        weight: 2,
      );
      final recs = {
        seed.key: [
          for (var i = 0; i < 3; i++)
            SeerrDiscoverItem(id: 300 + i, mediaType: 'movie'),
        ],
      };
      final result = rank(seeds: [seed], recommendations: recs);
      expect(result.picks.first.candidate.key, startsWith('movie:30'));
      expect(result.picks.first.reason.kind, TonightReasonKind.because);
      expect(result.picks.first.reason.seedTitle, 'Heat');
    });

    test('requestable and library titles are scored alike', () {
      final twins = [
        _c(1, genres: {TasteGenre.comedy}),
        _c(
          2,
          genres: {TasteGenre.comedy},
          availability: TonightAvailability.inLibrary,
        ),
        for (var i = 0; i < 4; i++) _c(10 + i, genres: {TasteGenre.drama}),
      ];
      // Six candidates for six picks: both twins are in.
      final result = rank(candidates: twins);
      final scores = {
        for (final p in result.picks) p.candidate.key: p.score,
      };
      expect(scores['movie:1'], closeTo(scores['movie:2']!, 1e-9));
    });
  });

  group('TonightWeights', () {
    test('move towards what was chosen, and survive a round trip', () {
      const weights = TonightWeights();
      final learned = weights.learn(
        {TonightFeature.quality: 2, TonightFeature.habit: -1},
        reward: 1,
      );
      expect(
        learned[TonightFeature.quality],
        greaterThan(weights[TonightFeature.quality]),
      );
      expect(
        learned[TonightFeature.habit],
        lessThan(weights[TonightFeature.habit]),
      );
      // The rule for turned-down titles doesn't drift.
      final rejected = weights.learn(
        {TonightFeature.rejected: 2},
        reward: 1,
      );
      expect(
        rejected[TonightFeature.rejected],
        weights[TonightFeature.rejected],
      );
      final back = TonightWeights.decode(learned.encode());
      expect(back[TonightFeature.quality], learned[TonightFeature.quality]);
      expect(back.lessons, 1);
    });
  });

  group('selfCheck', () {
    test('says how often the past would have been in the picks', () {
      final journal = [
        for (var i = 0; i < 20; i++)
          _entry(
            _friday.subtract(Duration(days: 40 - i * 2)),
            id: 'p$i',
            tmdb: 800 + i,
            genres: {TasteGenre.scifi},
          ),
      ];
      final rate = TonightEngine.selfCheck(journal: journal, pool: _pool());
      expect(rate, isNotNull);
      expect(rate, greaterThanOrEqualTo(0));
      expect(rate, lessThanOrEqualTo(1));
    });

    test('stays quiet with too little history', () {
      expect(
        TonightEngine.selfCheck(
          journal: [_entry(_friday, id: 'one')],
          pool: _pool(),
        ),
        isNull,
      );
    });
  });
}
