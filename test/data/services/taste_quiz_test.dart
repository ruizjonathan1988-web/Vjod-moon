import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/taste_profile.dart';
import 'package:moonfin/data/services/seerr/taste_quiz.dart';

final _now = DateTime(2026, 10, 21);

QuizTitle _t(
  int id, {
  Set<TasteGenre> genres = const {TasteGenre.drama},
  String type = 'movie',
  int year = 2015,
  double rating = 7.5,
  int votes = 8000,
  String language = 'en',
}) => QuizTitle(
  tmdbId: id,
  mediaType: type,
  title: 'T$id',
  posterPath: '/p$id.jpg',
  genres: genres,
  year: year,
  rating: rating,
  votes: votes,
  language: language,
);

List<QuizTitle> _pool() => [
  for (var i = 0; i < 10; i++)
    _t(100 + i, genres: {TasteGenre.action}, votes: 30000 - i),
  for (var i = 0; i < 6; i++)
    _t(200 + i, genres: {TasteGenre.comedy}, votes: 20000 - i, rating: 6.8),
  _t(300, genres: {TasteGenre.drama}, year: 1994, votes: 25000, rating: 8.7),
  _t(301, genres: {TasteGenre.comedy}, language: 'fr', votes: 9000),
  _t(302, genres: {TasteGenre.thriller}, language: 'ko', votes: 15000),
  _t(303, genres: {TasteGenre.animation, TasteGenre.family}, votes: 18000),
  _t(304, type: 'tv', genres: {TasteGenre.crime}, votes: 9000),
  _t(305, type: 'tv', genres: {TasteGenre.comedy}, votes: 7000),
  _t(306, genres: {TasteGenre.scifi}, year: 2023, votes: 12000),
  _t(307, genres: {TasteGenre.horror}, year: 2008, votes: 11000, rating: 6.5),
  _t(308, genres: {TasteGenre.romance, TasteGenre.drama}, votes: 900, rating: 7.6),
  _t(309, genres: {TasteGenre.drama}, year: 1960, votes: 4000, rating: 8.2),
];

void main() {
  group('pickGridPage', () {
    test('the first page covers ground', () {
      final page = pickGridPage(pool: _pool(), now: _now);
      expect(page, hasLength(8));
      expect(page.map((t) => t.key).toSet(), hasLength(8));
      expect(page.any((t) => t.year! < 2000), isTrue);
      expect(page.any((t) => t.language == 'fr'), isTrue);
      expect(
        page.any((t) => t.language != 'en' && t.language != 'fr'),
        isTrue,
      );
      expect(page.any((t) => t.genres.contains(TasteGenre.animation)), isTrue);
      expect(page.where((t) => !t.isMovie), hasLength(2));
      final genres = {for (final t in page) ...t.genres};
      expect(genres.length, greaterThanOrEqualTo(6));
    });

    test('keeps to the media wanted and away from avoided genres', () {
      final page = pickGridPage(
        pool: _pool(),
        mediaPref: TasteMediaPref.movies,
        avoided: {TasteGenre.horror},
        now: _now,
      );
      expect(page.every((t) => t.isMovie), isTrue);
      expect(page.any((t) => t.genres.contains(TasteGenre.horror)), isFalse);
    });

    test('later pages follow what was liked, and drop genres disliked twice',
        () {
      final liked = _t(300, genres: {TasteGenre.drama}, year: 1994);
      final page = pickGridPage(
        pool: _pool(),
        exclude: {'movie:300'},
        soFar: QuizSoFar(
          liked: [liked],
          disliked: [
            _t(100, genres: {TasteGenre.action}),
            _t(101, genres: {TasteGenre.action}),
          ],
          unseen: 2,
        ),
        recommendationsOfLiked: {
          liked.key: [
            _t(900, genres: {TasteGenre.drama}, year: 1995),
            _t(901, genres: {TasteGenre.history}, year: 1993),
          ],
        },
        now: _now,
      );
      expect(page.first.key, 'movie:901');
      expect(page.any((t) => t.genres.contains(TasteGenre.action)), isFalse);
    });

    test('shows only famous titles to someone who has seen few', () {
      final page = pickGridPage(
        pool: _pool(),
        soFar: const QuizSoFar(unseen: 7, liked: []),
        now: _now,
      );
      expect(page.every((t) => t.votes >= 5000 || !t.isMovie), isTrue);
    });

    test('shuffles only when asked', () {
      final a = pickGridPage(pool: _pool(), now: _now);
      final b = pickGridPage(pool: _pool(), now: _now);
      expect(a.map((t) => t.key), b.map((t) => t.key));
      final shuffled = pickGridPage(
        pool: _pool(),
        now: _now,
        random: math.Random(1),
      );
      expect(shuffled.map((t) => t.key).toSet(), a.map((t) => t.key).toSet());
    });
  });

  group('buildDuel', () {
    test('opposes the two poles of each axis', () {
      final pool = _pool();
      final dark = buildDuel(TasteAxis.darkLight, pool: pool, now: _now)!;
      expect(dark.left.genres.any({TasteGenre.horror, TasteGenre.thriller,
          TasteGenre.crime, TasteGenre.war}.contains), isTrue);
      expect(dark.right.genres.any({TasteGenre.comedy, TasteGenre.family,
          TasteGenre.animation}.contains), isTrue);

      final era = buildDuel(TasteAxis.recentClassic, pool: pool, now: _now)!;
      expect(era.left.year, greaterThanOrEqualTo(2021));
      expect(era.right.year, lessThanOrEqualTo(1996));

      final niche = buildDuel(TasteAxis.popularNiche, pool: pool, now: _now)!;
      expect(niche.left.votes, greaterThanOrEqualTo(15000));
      expect(niche.right.votes, lessThanOrEqualTo(2500));
    });

    test('skips used titles and gives up when a side is missing', () {
      final pool = _pool();
      final first = buildDuel(TasteAxis.darkLight, pool: pool, now: _now)!;
      final second = buildDuel(
        TasteAxis.darkLight,
        pool: pool,
        used: {first.left.key, first.right.key},
        now: _now,
      )!;
      expect(second.left.key, isNot(first.left.key));
      expect(
        buildDuel(
          TasteAxis.realImaginary,
          pool: [_t(1, genres: {TasteGenre.drama})],
          now: _now,
        ),
        isNull,
      );
    });
  });

  group('TasteProfile v2', () {
    test('survives a round trip with every answer', () {
      final profile = TasteProfile(
        pivots: const [
          TastePick(
            tmdbId: 1,
            mediaType: 'movie',
            title: 'Heat',
            genres: {TasteGenre.crime},
          ),
        ],
        disliked: const [
          TastePick(tmdbId: 2, mediaType: 'movie', title: 'X'),
        ],
        contexts: {'couple', 'family'},
        kidsAge: 'from7to12',
        movieLength: TasteMovieLength.medium,
        seriesFormat: TasteSeriesFormat.mini,
        axes: {TasteAxis.darkLight: -1, TasteAxis.popularNiche: 2},
        violence: TasteViolence.justified,
        subtitles: TasteSubtitles.gladly,
        anime: true,
        surpriseMe: true,
        updatedAt: DateTime.utc(2026, 10, 21),
      );
      final back = TasteProfile.decode(profile.encode());
      expect(back.pivots.single.genres, {TasteGenre.crime});
      expect(back.disliked.single.title, 'X');
      expect(back.contexts, {'couple', 'family'});
      expect(back.kidsAge, 'from7to12');
      expect(back.movieLength, TasteMovieLength.medium);
      expect(back.seriesFormat, TasteSeriesFormat.mini);
      expect(back.axes[TasteAxis.darkLight], -1);
      expect(back.axes[TasteAxis.popularNiche], 2);
      expect(back.violence, TasteViolence.justified);
      expect(back.subtitles, TasteSubtitles.gladly);
      expect(back.anime, isTrue);
      expect(back.surpriseMe, isTrue);
      expect(back.seenKeys, {'movie:1', 'movie:2'});
    });

    test('rated titles shape genre affinity', () {
      final profile = TasteProfile(
        pivots: [
          for (var i = 0; i < 3; i++)
            TastePick(
              tmdbId: i,
              mediaType: 'movie',
              title: '',
              genres: const {TasteGenre.crime},
            ),
        ],
        disliked: [
          for (var i = 0; i < 3; i++)
            TastePick(
              tmdbId: 10 + i,
              mediaType: 'movie',
              title: '',
              genres: const {TasteGenre.horror},
            ),
        ],
      );
      final affinity = profile.genreAffinity;
      expect(affinity[TasteGenre.crime], greaterThan(0.5));
      expect(affinity[TasteGenre.horror], lessThan(0));
      double factor(Set<TasteGenre> genres) => tasteFactorFor(
        genres: genres,
        mediaType: 'movie',
        profile: profile,
        feedback: TasteFeedback.empty,
      );
      expect(factor({TasteGenre.crime}), greaterThan(1));
      expect(factor({TasteGenre.horror}), lessThan(1));
    });

    test('limits rule out what they say, duels only nudge', () {
      const noGore = TasteProfile(violence: TasteViolence.none);
      double factor(
        TasteProfile p,
        Set<TasteGenre> genres, {
        String? language,
        int? votes,
      }) => tasteFactorFor(
        genres: genres,
        mediaType: 'movie',
        profile: p,
        feedback: TasteFeedback.empty,
        language: language,
        voteCount: votes,
        now: _now,
      );
      expect(factor(noGore, {TasteGenre.horror}), 0);
      const noSubs = TasteProfile(subtitles: TasteSubtitles.never);
      expect(factor(noSubs, {TasteGenre.drama}, language: 'ko'), 0);
      expect(factor(noSubs, {TasteGenre.drama}, language: 'fr'), 1);

      const darkLover = TasteProfile(axes: {TasteAxis.darkLight: -2});
      expect(factor(darkLover, {TasteGenre.thriller}), greaterThan(1));
      expect(factor(darkLover, {TasteGenre.comedy}), lessThan(1));
      expect(factor(darkLover, {TasteGenre.comedy}), greaterThan(0.7));

      const niche = TasteProfile(axes: {TasteAxis.popularNiche: 2});
      expect(
        factor(niche, {TasteGenre.drama}, votes: 800),
        greaterThan(factor(niche, {TasteGenre.drama}, votes: 50000)),
      );
    });
  });
}
