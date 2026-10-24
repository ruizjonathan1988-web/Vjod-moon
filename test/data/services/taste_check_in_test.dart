import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/taste_check_in.dart';
import 'package:moonfin/data/services/seerr/taste_profile.dart';
import 'package:moonfin/data/services/tonight/evening_journal.dart';

final _now = DateTime(2026, 10, 21, 20);

JournalEntry _e(
  String id, {
  int daysAgo = 2,
  bool finished = true,
  int watched = 100,
  int runtime = 110,
  int? tmdb = 1,
  bool backfilled = false,
}) => JournalEntry(
  at: _now.subtract(Duration(days: daysAgo)),
  itemId: id,
  mediaType: 'movie',
  title: id,
  tmdbId: tmdb,
  genres: const {TasteGenre.thriller},
  runtimeMinutes: runtime,
  watchedMinutes: watched,
  finished: finished,
  backfilled: backfilled,
);

void main() {
  test('asks about the latest film finished and the latest dropped', () {
    final journal = [
      _e('old', daysAgo: 60, tmdb: 9),
      _e('done', daysAgo: 5, tmdb: 2),
      _e('dropped', daysAgo: 3, finished: false, watched: 12, tmdb: 3),
      _e('done-later', daysAgo: 1, tmdb: 4),
    ];
    final s = checkInSittings(
      journal: journal,
      profile: TasteProfile.empty,
      now: _now,
    );
    expect(s.finished?.itemId, 'done-later');
    expect(s.dropped?.itemId, 'dropped');
  });

  test('never asks twice, nor about what was rated or rebuilt', () {
    final done = _e('done', tmdb: 2);
    final rebuilt = _e('rebuilt', daysAgo: 1, tmdb: 5, backfilled: true);
    final rated = _e('rated', daysAgo: 1, tmdb: 6);
    final s = checkInSittings(
      journal: [done, rebuilt, rated],
      profile: const TasteProfile(
        favorites: [TastePick(tmdbId: 6, mediaType: 'movie', title: '')],
      ),
      asked: {checkInKey(done)},
      now: _now,
    );
    expect(s.finished, isNull);
  });

  test('a verdict files the title where it belongs', () {
    final entry = _e('x', tmdb: 7);
    var p = applyVerdict(TasteProfile.empty, entry, CheckInVerdict.loved);
    expect(p.pivots.single.tmdbId, 7);
    p = applyVerdict(p, entry, CheckInVerdict.disliked);
    expect(p.disliked.single.genres, {TasteGenre.thriller});
  });

  test('why something was dropped moves the right dial', () {
    final entry = _e('x', finished: false, watched: 10);
    final slow = applyDropReason(TasteProfile.empty, entry, DropReason.tooSlow);
    expect(slow.axes[TasteAxis.slowFast], 0.5);
    final dark = applyDropReason(TasteProfile.empty, entry, DropReason.tooDark);
    expect(dark.violence, TasteViolence.justified);
    final genre = applyDropReason(
      TasteProfile.empty,
      entry,
      DropReason.notMyGenre,
    );
    expect(genre.disliked, hasLength(1));
    expect(
      applyDropReason(TasteProfile.empty, entry, DropReason.notNow).encode(),
      TasteProfile.empty.encode(),
    );
  });

  test('a past choice can be let go', () {
    const profile = TasteProfile(
      avoided: {TasteGenre.horror},
      subtitles: TasteSubtitles.never,
    );
    final question = stillTrueQuestion(profile);
    expect(question, isA<StillAvoided>());
    final released = releaseChoice(profile, question!);
    expect(released.avoided, isEmpty);
    expect(stillTrueQuestion(released), isA<StillNoSubtitles>());
  });
}
