// What a film or an episode watched from the IPTV provider teaches VJOD, once
// it stops: a sitting in the evening journal (Home and Tonight learn from it
// like from a library film), and on Trakt when the profile linked an account
// and it was watched to the end. Every step fails quietly.
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../../repositories/seerr_repository.dart';
import '../seerr/taste_profile.dart';
import '../tonight/tonight_service.dart';
import '../trakt/trakt_account.dart';
import 'iptv_progress.dart';

class IptvLearning {
  IptvLearning._();

  /// Genres and year of a TMDB title, kept for the run of the app.
  static final Map<String, Future<({Set<TasteGenre> genres, int? year, double? rating})>> _facts = {};

  static Future<({Set<TasteGenre> genres, int? year, double? rating})> facts(String mediaType, int tmdbId) =>
      _facts.putIfAbsent('$mediaType:$tmdbId', () async {
        const none = (genres: <TasteGenre>{}, year: null, rating: null);
        try {
          final repo = await GetIt.instance.getAsync<SeerrRepository>();
          if (mediaType == 'tv') {
            final d = await repo.getTvDetails(tmdbId);
            return (
              genres: TasteGenre.fromNames(d.genres.map((g) => g.name)),
              year: int.tryParse((d.firstAirDate ?? '').split('-').first),
              rating: d.voteAverage,
            );
          }
          final d = await repo.getMovieDetails(tmdbId);
          return (
            genres: TasteGenre.fromNames(d.genres.map((g) => g.name)),
            year: int.tryParse((d.releaseDate ?? '').split('-').first),
            rating: d.voteAverage,
          );
        } catch (e) {
          debugPrint('[IPTV] No TMDB facts for $mediaType:$tmdbId: $e');
          _facts.remove('$mediaType:$tmdbId');
          return none;
        }
      });

  /// A playback of [watch] that started at [startedAt] and stopped at
  /// [position] of [duration], [watched] being the time actually played.
  static Future<void> record({
    required IptvWatch watch,
    required DateTime startedAt,
    required Duration position,
    required Duration duration,
    required Duration watched,
  }) async {
    if (watched.inSeconds < 60) return;
    final mediaType = watch.isSeries ? 'tv' : 'movie';
    final tmdb = int.tryParse(watch.tmdb);
    final finished = _finished(watch.isSeries, position, duration);
    final f = tmdb == null
        ? (genres: <TasteGenre>{}, year: null, rating: null)
        : await facts(mediaType, tmdb);
    try {
      await TonightService.instance.recordIptvSitting(
        startedAt: startedAt,
        // The same key whether a title comes from the library or the
        // provider, so both count as one title.
        itemId: tmdb != null ? 'tmdb:$mediaType:$tmdb' : 'iptv:${watch.kind}:${watch.id}',
        mediaType: mediaType,
        title: watch.name,
        tmdbId: tmdb,
        genres: f.genres,
        runtimeMinutes: duration.inMinutes > 0 ? duration.inMinutes : null,
        year: f.year,
        rating: f.rating,
        watchedMinutes: watched.inMinutes,
        finished: finished,
      );
    } catch (e) {
      debugPrint('[IPTV] Journal: $e');
    }
    if (finished && tmdb != null && GetIt.instance.isRegistered<TraktAccount>()) {
      await GetIt.instance<TraktAccount>().markWatched(
        mediaType: mediaType,
        tmdbId: tmdb,
        season: watch.isSeries && watch.season > 0 ? watch.season : null,
        episode: watch.isSeries && watch.episode > 0 ? watch.episode : null,
      );
    }
  }

  /// Watched to the credits, the way Ma TV decides it.
  static bool _finished(bool episode, Duration position, Duration duration) {
    if (duration.inSeconds <= 0) return false;
    final left = duration - position;
    final ratio = position.inSeconds / duration.inSeconds;
    return episode
        ? ratio >= 0.85 || left.inMinutes <= 3
        : ratio >= 0.9 || left.inMinutes <= 8;
  }
}
