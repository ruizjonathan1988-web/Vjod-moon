import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../../preference/seerr_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../models/aggregated_item.dart';
import '../../repositories/seerr_repository.dart';
import '../media_server_client_factory.dart';
import '../row_data_source.dart';
import '../seerr/for_you_ranker.dart';
import '../seerr/for_you_service.dart';
import '../seerr/seerr_api_models.dart';
import '../seerr/seerr_error.dart';
import '../seerr/taste_extras.dart';
import '../seerr/seed_recommendations.dart';
import '../seerr/taste_profile.dart';
import 'evening_journal.dart';
import 'habit_model.dart';
import 'tonight_engine.dart';
import 'tonight_models.dart';

const _tmdbPoster = 'https://image.tmdb.org/t/p/w500';
const _tmdbBackdrop = 'https://image.tmdb.org/t/p/w1280';

/// One evening's suggestions, ready to show.
class TonightView {
  final TonightResult result;
  final TonightAnswers answers;

  /// Share of past sittings the engine would have suggested, once there is
  /// enough history to say.
  final double? precision;

  /// A request made from Tonight that hasn't landed after a good while.
  final TonightPending? stalled;

  const TonightView({
    required this.result,
    required this.answers,
    this.precision,
    this.stalled,
  });
}

/// A request made from Tonight, followed until the title is on the server.
class TonightPending {
  final String key;
  final String title;
  final String mediaType;
  final int tmdbId;
  final DateTime at;

  const TonightPending({
    required this.key,
    required this.title,
    required this.mediaType,
    required this.tmdbId,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title,
    'type': mediaType,
    'tmdb': tmdbId,
    'at': at.toUtc().toIso8601String(),
  };

  static TonightPending? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    final tmdb = json['tmdb'];
    if (at == null || tmdb is! int) return null;
    return TonightPending(
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      mediaType: json['type'] as String? ?? 'movie',
      tmdbId: tmdb,
      at: at.toLocal(),
    );
  }
}

/// How a request from Tonight went.
enum TonightRequestOutcome { sent, alreadyThere, failed }

/// Tonight: keeps the journal of evenings, gathers what could be watched,
/// asks the engine, and learns from what the viewer does with its picks.
class TonightService {
  TonightService._();

  static final TonightService instance = TonightService._();

  /// How long answers given in the sheet describe the evening.
  static const answersLifetime = Duration(hours: 5);

  /// How long after a launch from Tonight a play still counts as it.
  static const launchWindow = Duration(hours: 8);

  /// A request older than this that hasn't landed gets an alternative.
  static const stallAfter = Duration(minutes: 45);

  static const _libraryLifetime = Duration(minutes: 15);
  static const _discoverLifetime = Duration(minutes: 30);
  static const _rejectionMemory = Duration(days: 7);

  SeerrPreferences get _prefs => GetIt.instance<SeerrPreferences>();

  final Map<String, ({DateTime at, List<TonightCandidate> items})> _library =
      {};
  final Map<String, ({DateTime at, List<TonightCandidate> items})> _discover =
      {};
  final Map<int, int> _movieRuntimes = {};
  final Map<String, _Live> _live = {};

  /// The last evening's picks and the one launched, to learn from.
  _Session? _session;

  TonightDevice get device =>
      PlatformDetection.isTV ? TonightDevice.tv : TonightDevice.phone;

  // ---------------------------------------------------------------------
  // Journal

  EveningJournal get journal => EveningJournal.decode(_prefs.tonightJournalJson);

  Future<void> _saveJournal(EveningJournal journal) =>
      _prefs.setTonightJournalJson(journal.encode());

  /// Fills the journal from the server's play history the first time, so
  /// habits don't start from nothing.
  Future<void> ensureBackfilled(RowDataSource source, String serverId) async {
    if (_prefs.tonightBackfilled) return;
    try {
      final history = await source.loadTasteHistory(serverId);
      final past = <JournalEntry>[];
      for (final item in history.recent) {
        final played = _lastPlayed(item);
        if (played == null) continue;
        final type = item.type == 'Series' ? 'tv' : 'movie';
        past.add(
          JournalEntry(
            at: played,
            itemId: item.id,
            mediaType: type,
            title: item.name,
            tmdbId: int.tryParse(item.tmdbId ?? ''),
            genres: TasteGenre.fromNames(item.genres),
            runtimeMinutes: item.runtime?.inMinutes,
            year: item.productionYear,
            rating: item.communityRating,
            finished: true,
            backfilled: true,
          ),
        );
      }
      await _saveJournal(journal.backfill(past));
      await _prefs.setTonightBackfilled(true);
    } catch (e) {
      debugPrint('[Tonight] Backfill failed: $e');
    }
  }

  static DateTime? _lastPlayed(AggregatedItem item) {
    final raw = item.rawData['UserData'];
    if (raw is! Map) return null;
    final value = raw['LastPlayedDate'] as String?;
    return value == null ? null : DateTime.tryParse(value)?.toLocal();
  }

  /// Playback started: note when and where from.
  void onPlaybackStarted(dynamic mediaItem, {int? positionTicks}) {
    if (mediaItem is! AggregatedItem) return;
    if (mediaItem.type != 'Movie' && mediaItem.type != 'Episode') return;
    _live[mediaItem.id] = _Live(
      item: mediaItem,
      startedAt: DateTime.now(),
      startTicks: positionTicks ?? mediaItem.playbackPositionTicks ?? 0,
    );
  }

  /// Playback stopped: write the sitting down, and learn from it if it came
  /// from Tonight.
  Future<void> onPlaybackStopped(dynamic mediaItem, Duration position) async {
    if (mediaItem is! AggregatedItem) return;
    final live = _live.remove(mediaItem.id);
    if (live == null) return;
    try {
      await _recordSitting(live, position);
    } catch (e) {
      debugPrint('[Tonight] Could not journal ${mediaItem.name}: $e');
    }
  }

  Future<void> _recordSitting(_Live live, Duration position) async {
    final item = live.item;
    final start = Duration(microseconds: live.startTicks ~/ 10);
    final watched = position - start;
    if (watched.inSeconds < 60) return;

    final isEpisode = item.type == 'Episode';
    final runtime = item.runtime;
    final bool finished;
    if (runtime == null || runtime.inSeconds <= 0) {
      finished = false;
    } else {
      final left = runtime - position;
      final ratio = position.inSeconds / runtime.inSeconds;
      finished = isEpisode
          ? ratio >= 0.85 || left.inMinutes <= 3
          : ratio >= 0.9 || left.inMinutes <= 8;
    }

    // An episode stands for its series; either way the genres and TMDB id
    // come from the movie or series itself.
    final client =
        GetIt.instance<MediaServerClientFactory>().getClientIfExists(
          item.serverId,
        ) ??
        GetIt.instance<MediaServerClient>();
    final source = RowDataSource(client);
    final subjectId = isEpisode ? (item.seriesId ?? item.id) : item.id;
    final subject =
        (isEpisode || item.tmdbId == null || item.genres.isEmpty)
        ? await source.loadItemWithProviders(item.serverId, subjectId) ?? item
        : item;

    final answers = TonightAnswers.decode(_prefs.tonightAnswersJson);
    final company =
        answers != null && live.startedAt.difference(answers.at) < answersLifetime
        ? answers.company
        : null;

    final session = _session ?? _Session.decode(_prefs.tonightSessionJson);
    final launched = session?.launched;
    final fromTonight =
        launched != null &&
        live.startedAt.difference(launched.at) < launchWindow &&
        (launched.playItemId == item.id ||
            launched.libraryItemId == subjectId ||
            (launched.tmdbKey != null &&
                launched.tmdbKey == _tmdbKeyOf(subject)));

    final entry = JournalEntry(
      at: live.startedAt,
      itemId: subjectId,
      mediaType: isEpisode ? 'tv' : 'movie',
      title: isEpisode ? (item.seriesName ?? subject.name) : item.name,
      tmdbId: int.tryParse(subject.tmdbId ?? ''),
      genres: TasteGenre.fromNames(subject.genres),
      runtimeMinutes: runtime?.inMinutes,
      year: subject.productionYear,
      rating: subject.communityRating,
      watchedMinutes: watched.inMinutes,
      finished: finished,
      company: company,
      device: device,
      fromTonight: fromTonight,
    );
    await _saveJournal(journal.record(entry));

    if (fromTonight) {
      final reward = finished ? 1.0 : (entry.abandoned ? -1.0 : 0.2);
      await _learn(launched.features, reward: reward);
      // One verdict per launch.
      _session = session!.withLaunched(null);
      await _prefs.setTonightSessionJson(_session!.encode());
    }
  }

  /// A film or an episode watched from the IPTV provider, outside the
  /// library: it counts like a library sitting, so Home and Tonight learn
  /// from it too. [itemId] stands for the film or the series.
  Future<void> recordIptvSitting({
    required DateTime startedAt,
    required String itemId,
    required String mediaType,
    required String title,
    int? tmdbId,
    Set<TasteGenre> genres = const {},
    int? runtimeMinutes,
    int? year,
    double? rating,
    required int watchedMinutes,
    required bool finished,
  }) async {
    if (watchedMinutes < 1) return;
    final answers = TonightAnswers.decode(_prefs.tonightAnswersJson);
    final company =
        answers != null && startedAt.difference(answers.at) < answersLifetime
        ? answers.company
        : null;
    final entry = JournalEntry(
      at: startedAt,
      itemId: itemId,
      mediaType: mediaType,
      title: title,
      tmdbId: tmdbId,
      genres: genres,
      runtimeMinutes: runtimeMinutes,
      year: year,
      rating: rating,
      watchedMinutes: watchedMinutes,
      finished: finished,
      company: company,
      device: device,
    );
    await _saveJournal(journal.record(entry));
  }

  static String? _tmdbKeyOf(AggregatedItem item) {
    final id = int.tryParse(item.tmdbId ?? '');
    if (id == null) return null;
    return '${item.type == 'Series' ? 'tv' : 'movie'}:$id';
  }

  // ---------------------------------------------------------------------
  // Answers

  /// What to preselect in the sheet: tonight's answers if given lately,
  /// otherwise the usual company for this slot and the last mood.
  TonightAnswers suggestAnswers({DateTime? now}) {
    final at = now ?? DateTime.now();
    final last = TonightAnswers.decode(_prefs.tonightAnswersJson);
    if (last != null && at.difference(last.at) < answersLifetime) {
      return last.copyWith(at: at);
    }
    final slot = TonightSlot.of(at);
    final habits = HabitModel.build(journal.entries, now: at);
    final company =
        habits.suggestCompany(slot, device) ??
        last?.company ??
        TonightCompany.alone;
    final lateWeekday =
        slot.day == DayKind.weekday && slot.band == DayBand.late;
    return TonightAnswers(
      company: company,
      time: lateWeekday ? TonightTime.short : (last?.time ?? TonightTime.evening),
      mood: last?.mood ?? TonightMood.surprise,
      kidsAge: last?.kidsAge ?? KidsAge.from7to12,
      at: at,
    );
  }

  Future<void> saveAnswers(TonightAnswers answers) async {
    await _prefs.setTonightAnswersJson(answers.encode());
    answersChanged.value++;
  }

  /// Counts the answers saved, for what shows tonight's picks elsewhere.
  final ValueNotifier<int> answersChanged = ValueNotifier(0);

  // ---------------------------------------------------------------------
  // Suggestions

  /// Gathers what could be watched and ranks it for [answers].
  ///
  /// [libraryOnly] ranks only what the server can play now, and
  /// [requestableOnly] only what it can't, for the home banner. Their picks
  /// aren't remembered as shown: the Tonight sheet's are what the engine
  /// learns from.
  Future<TonightView> load(
    TonightAnswers answers, {
    Set<String> exclude = const {},
    bool forceRefresh = false,
    bool libraryOnly = false,
    bool requestableOnly = false,
  }) async {
    final client = GetIt.instance<MediaServerClient>();
    final serverId = client.baseUrl;
    final source = RowDataSource(client);
    await ensureBackfilled(source, serverId);

    final now = DateTime.now();
    final currentJournal = journal;
    final profile = TasteProfile.decode(_prefs.tasteProfileJson);
    final feedback = TasteFeedback.decode(_prefs.tasteFeedbackJson);
    final blockAdult = _prefs.blockNsfw;

    SeerrRepository? repo;
    try {
      final r = await GetIt.instance.getAsync<SeerrRepository>();
      await r.ensureInitialized();
      if (r.isAvailable) repo = r;
    } catch (e) {
      debugPrint('[Tonight] Seerr unavailable: $e');
    }

    final seerr = repo;
    Future<Object?> forYou() async {
      if (seerr == null) return null;
      try {
        return await _forYouRaw(seerr, source, serverId, profile);
      } catch (e) {
        debugPrint('[Tonight] For You signals failed: $e');
        return null;
      }
    }

    Future<Object?> discover() async {
      if (seerr == null) return const <TonightCandidate>[];
      return _discoverCandidates(seerr, answers, forceRefresh);
    }

    Future<Object?> libraryPool() async {
      try {
        return await _libraryCandidates(
          source,
          serverId,
          client.imageApi,
          forceRefresh,
        );
      } catch (e) {
        debugPrint('[Tonight] Library failed: $e');
        return const <TonightCandidate>[];
      }
    }

    Future<Object?> pastPlays() async {
      try {
        return await source.loadTasteHistory(serverId);
      } catch (e) {
        debugPrint('[Tonight] History failed: $e');
        return (
          recent: const <AggregatedItem>[],
          favorites: const <AggregatedItem>[],
          abandoned: const <AggregatedItem>[],
        );
      }
    }

    final results = await Future.wait<Object?>([
      libraryPool(),
      forYou(),
      discover(),
      pastPlays(),
    ]);
    final library = results[0] as List<TonightCandidate>;
    final raw =
        results[1]
            as ({
              List<TasteSeed> seeds,
              Map<String, List<SeerrDiscoverItem>> recommendations,
              Set<String> exclude,
            })?;
    final discovered = results[2] as List<TonightCandidate>;
    final history =
        results[3] as TasteHistory;

    // Library first, so its copy of a title wins the merge.
    final pool = <String, TonightCandidate>{};
    void add(TonightCandidate c) {
      final existing = pool[c.key];
      pool[c.key] = existing == null ? c : existing.mergedWith(c);
    }

    library.forEach(add);
    if (raw != null) {
      for (final entry in raw.recommendations.entries) {
        final seedType = entry.key.split(':').first;
        for (final item in entry.value) {
          final type = item.mediaType ?? seedType;
          if (type != 'movie' && type != 'tv') continue;
          add(_fromSeerr(item, type));
        }
      }
    }
    discovered.forEach(add);

    final watched = <String>{
      ...currentJournal.watchedTmdbKeys,
      ...profile.seenKeys,
      for (final item in history.recent)
        if (_tmdbKeyOf(item) case final key?
            when item.type == 'Movie' || _isPlayed(item))
          key,
    };

    final rejections = _recentRejections(now);
    final weights = TonightWeights.decode(_prefs.tonightWeightsJson);
    final habits = HabitModel.build(currentJournal.entries, now: now);

    TonightInput input(List<TonightCandidate> candidates) => TonightInput(
      candidates: candidates,
      answers: answers,
      now: now,
      device: device,
      habits: habits,
      journal: currentJournal.entries,
      profile: profile,
      feedback: feedback,
      seeds: raw?.seeds ?? const [],
      recommendations: raw?.recommendations ?? const {},
      rejections: rejections,
      exclude: {...exclude, ...?raw?.exclude},
      watched: watched,
      weights: weights,
      blockAdult: blockAdult,
    );

    var candidates = [
      for (final candidate in pool.values)
        if ((!libraryOnly ||
                candidate.availability == TonightAvailability.inLibrary) &&
            (!requestableOnly ||
                candidate.availability == TonightAvailability.requestable))
          _withKnownRuntime(candidate),
    ];
    var result = TonightEngine.rank(input(candidates));
    if (libraryOnly || requestableOnly) {
      return TonightView(result: result, answers: answers);
    }

    // Seerr doesn't say how long a film runs until asked about it. Ask for
    // the ones in the running, then rank again with their real length.
    if (repo != null) {
      final unknown = result.picks.isEmpty
          ? const <TonightCandidate>[]
          : _contenders(candidates, input, result);
      if (unknown.isNotEmpty) {
        await _fetchRuntimes(repo, unknown);
        candidates = candidates.map(_withKnownRuntime).toList();
        result = TonightEngine.rank(input(candidates));
      }
    }

    double? precision;
    try {
      precision = TonightEngine.selfCheck(
        journal: currentJournal.entries,
        pool: candidates,
        profile: profile,
        feedback: feedback,
        weights: weights,
      );
    } catch (e) {
      debugPrint('[Tonight] Self check failed: $e');
    }

    _session = _Session(
      at: now,
      shown: [
        for (final pick in result.picks)
          _Shown(key: pick.candidate.key, features: pick.features),
      ],
      launched: (_session ?? _Session.decode(_prefs.tonightSessionJson))
          ?.launched,
    );
    unawaited(_prefs.setTonightSessionJson(_session!.encode()));

    return TonightView(
      result: result,
      answers: answers,
      precision: precision,
      stalled: await _stalledRequest(source, serverId),
    );
  }

  static bool _isPlayed(AggregatedItem item) {
    final raw = item.rawData['UserData'];
    return raw is Map && raw['Played'] == true;
  }

  /// Seerr movies near the top whose length isn't known yet.
  List<TonightCandidate> _contenders(
    List<TonightCandidate> candidates,
    TonightInput Function(List<TonightCandidate>) input,
    TonightResult result,
  ) {
    // A loose ranking without the time rule, so films that may turn out too
    // long are still looked at.
    final loose = TonightEngine.rank(
      input([
        for (final c in candidates)
          if (c.isMovie && c.runtimeMinutes == null) c,
      ]),
    );
    final seen = <String>{};
    return [
      for (final pick in [...result.picks, ...loose.picks])
        if (pick.candidate.isMovie &&
            pick.candidate.runtimeMinutes == null &&
            pick.candidate.tmdbId != null &&
            seen.add(pick.candidate.key))
          pick.candidate,
      for (final c in candidates)
        if (c.isMovie &&
            c.runtimeMinutes == null &&
            c.tmdbId != null &&
            seen.length < 30 &&
            seen.add(c.key))
          c,
    ].take(30).toList();
  }

  Future<void> _fetchRuntimes(
    SeerrRepository repo,
    List<TonightCandidate> movies,
  ) async {
    const concurrency = 6;
    final todo = [
      for (final c in movies)
        if (!_movieRuntimes.containsKey(c.tmdbId)) c.tmdbId!,
    ];
    for (var start = 0; start < todo.length; start += concurrency) {
      await Future.wait(
        todo.skip(start).take(concurrency).map((id) async {
          try {
            final details = await repo
                .getMovieDetails(id)
                .timeout(const Duration(seconds: 6));
            final runtime = details.runtime;
            if (runtime != null && runtime > 0) _movieRuntimes[id] = runtime;
          } catch (e) {
            debugPrint('[Tonight] No runtime for $id: $e');
          }
        }),
      );
    }
  }

  TonightCandidate _withKnownRuntime(TonightCandidate c) {
    if (c.runtimeMinutes != null || !c.isMovie || c.tmdbId == null) return c;
    final runtime = _movieRuntimes[c.tmdbId];
    return runtime == null ? c : c.copyWith(runtimeMinutes: runtime);
  }

  Future<List<TonightCandidate>> _libraryCandidates(
    RowDataSource source,
    String serverId,
    ImageApi images,
    bool forceRefresh,
  ) async {
    final cached = _library[serverId];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.at) < _libraryLifetime) {
      return cached.items;
    }
    final lib = await source.loadTonightLibrary(serverId);
    final items = <TonightCandidate>[
      for (final next in lib.nextUp)
        _fromLibrary(next.series, images, episode: next.episode),
      for (final movie in lib.movies) _fromLibrary(movie, images),
      for (final series in lib.series) _fromLibrary(series, images),
      for (final favorite in lib.favorites)
        if (_isPlayed(favorite)) _fromLibrary(favorite, images, rewatch: true),
    ];
    _library[serverId] = (at: DateTime.now(), items: items);
    return items;
  }

  Future<
    ({
      List<TasteSeed> seeds,
      Map<String, List<SeerrDiscoverItem>> recommendations,
      Set<String> exclude,
    })
  >
  _forYouRaw(
    SeerrRepository repo,
    RowDataSource source,
    String serverId,
    TasteProfile profile,
  ) => ForYouService.instance.loadRaw(
    serverId: serverId,
    loadHistory: () => source.loadTasteHistory(serverId),
    fetchRecommendations: (seed) => seedRecommendations(repo, seed),
    loadExtras: () => loadTasteExtras(repo, profile),
  );

  /// TMDB genres each mood asks Seerr for, movies then series. A bar joins
  /// them as "any of".
  static const _moodQueries = <TonightMood, (String?, String?)>{
    TonightMood.laugh: ('35|16|10751', '35|16|10751'),
    TonightMood.chills: ('27|53|9648', '9648|80'),
    TonightMood.escape: ('14|878|12', '10765|10759'),
    TonightMood.think: ('99|18|36', '99|18'),
    TonightMood.comfort: ('35|10751|10749|16', '35|10751'),
    TonightMood.surprise: (null, null),
  };

  Future<List<TonightCandidate>> _discoverCandidates(
    SeerrRepository repo,
    TonightAnswers answers,
    bool forceRefresh,
  ) async {
    final family = answers.company == TonightCompany.family;
    final budget = answers.time.budgetMinutes;
    final cacheKey = '${answers.mood.name}|$budget|$family';
    final cached = _discover[cacheKey];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.at) < _discoverLifetime) {
      return cached.items;
    }

    var (movieGenres, tvGenres) = _moodQueries[answers.mood]!;
    if (family) {
      movieGenres = '10751|16';
      tvGenres = '10751|16|10762';
    }
    final surprise = answers.mood == TonightMood.surprise;
    // A different page each time keeps a surprise a surprise.
    final page = surprise ? 1 + math.Random().nextInt(5) : 1;

    Future<List<TonightCandidate>> fetch(
      Future<SeerrDiscoverPage> Function() call,
      String type,
    ) async {
      try {
        final result = await call().timeout(const Duration(seconds: 8));
        return [for (final item in result.results) _fromSeerr(item, type)];
      } catch (e) {
        debugPrint('[Tonight] Discover $type failed: $e');
        return const [];
      }
    }

    final lists = await Future.wait([
      fetch(
        () => repo.discoverMovies(
          page: page,
          sortBy: surprise ? 'vote_average.desc' : 'popularity.desc',
          genre: movieGenres,
          voteCountGte: surprise ? 1500 : 300,
          voteAverageGte: 6.3,
          withRuntimeLte: budget,
        ),
        'movie',
      ),
      fetch(
        () => repo.discoverMovies(
          page: surprise ? page + 1 : 2,
          sortBy: 'vote_average.desc',
          genre: movieGenres,
          voteCountGte: 1000,
          voteAverageGte: 7,
          withRuntimeLte: budget,
        ),
        'movie',
      ),
      fetch(
        () => repo.discoverTv(
          page: page,
          sortBy: surprise ? 'vote_average.desc' : 'popularity.desc',
          genre: tvGenres,
          voteCountGte: surprise ? 500 : 150,
          voteAverageGte: 6.5,
        ),
        'tv',
      ),
    ]);
    final items = [for (final list in lists) ...list];
    _discover[cacheKey] = (at: DateTime.now(), items: items);
    return items;
  }

  static TonightCandidate _fromLibrary(
    AggregatedItem item,
    ImageApi images, {
    AggregatedItem? episode,
    bool rewatch = false,
  }) {
    final type = item.type == 'Series' ? 'tv' : 'movie';
    final tmdbId = int.tryParse(item.tmdbId ?? '');
    final created = item.dateCreated;
    final backdropTags = item.backdropImageTags;
    final episodeLabel = episode == null
        ? null
        : [
            if (episode.parentIndexNumber != null)
              'S${episode.parentIndexNumber}',
            if (episode.indexNumber != null) 'E${episode.indexNumber}',
          ].join(' · ');
    return TonightCandidate(
      key: tmdbId != null ? '$type:$tmdbId' : 'lib:${item.id}',
      mediaType: type,
      tmdbId: tmdbId,
      title: item.name,
      genres: TasteGenre.fromNames(item.genres),
      runtimeMinutes: (episode?.runtime ?? item.runtime)?.inMinutes,
      year: item.productionYear,
      rating: item.communityRating,
      ratingAge: ratingAge(item.officialRating),
      availability: TonightAvailability.inLibrary,
      inProgress: episode != null,
      rewatch: rewatch,
      freshlyAdded:
          created != null &&
          DateTime.now().difference(created) < const Duration(days: 14),
      libraryItemId: item.id,
      playItemId: episode?.id ?? item.id,
      posterUrl: images.getPrimaryImageUrl(
        item.id,
        maxHeight: 600,
        tag: item.primaryImageTag,
      ),
      backdropUrl: backdropTags.isEmpty
          ? null
          : images.getBackdropImageUrl(
              item.id,
              maxWidth: 1280,
              tag: backdropTags.first,
            ),
      overview: item.overview,
      nextEpisodeLabel: episodeLabel,
      seasonCount: type == 'tv'
          ? (item.rawData['ChildCount'] as num?)?.toInt()
          : null,
    );
  }

  static TonightCandidate _fromSeerr(SeerrDiscoverItem item, String type) {
    final genres = TasteGenre.of(item.genreIds, type);
    final status = item.mediaInfo?.status;
    final availability = SeerrMediaStatus.isAvailable(status)
        ? TonightAvailability.inLibrary
        : status == SeerrMediaStatus.pending ||
              status == SeerrMediaStatus.processing
        ? TonightAvailability.requested
        : TonightAvailability.requestable;
    final date = type == 'tv' ? item.firstAirDate : item.releaseDate;
    final poster = item.posterPath;
    final backdrop = item.backdropPath;
    return TonightCandidate(
      key: '$type:${item.id}',
      mediaType: type,
      tmdbId: item.id,
      title: item.displayTitle,
      genres: genres,
      // Seerr lists don't carry a length. Episodes are guessed from the
      // genre; films are looked up when they get close to the top.
      runtimeMinutes: type == 'tv'
          ? (genres.contains(TasteGenre.comedy) ||
                    genres.contains(TasteGenre.animation)
                ? 25
                : 45)
          : null,
      year: date != null && date.length >= 4
          ? int.tryParse(date.substring(0, 4))
          : null,
      rating: item.voteAverage,
      voteCount: item.voteCount,
      language: item.originalLanguage,
      adult: item.adult,
      availability: availability,
      libraryItemId: item.mediaInfo?.jellyfinMediaId,
      posterUrl: poster == null || poster.isEmpty ? null : '$_tmdbPoster$poster',
      backdropUrl: backdrop == null || backdrop.isEmpty
          ? null
          : '$_tmdbBackdrop$backdrop',
      overview: item.overview,
    );
  }

  // ---------------------------------------------------------------------
  // Learning

  Future<void> _learn(
    Map<String, double> chosen, {
    Map<String, double>? over,
    required double reward,
  }) async {
    final weights = TonightWeights.decode(_prefs.tonightWeightsJson);
    await _prefs.setTonightWeightsJson(
      weights.learn(chosen, over: over, reward: reward).encode(),
    );
  }

  Map<String, int> _recentRejections(DateTime now) {
    final all = _decodeRejections();
    return {
      for (final e in all.entries)
        if (e.value.where((t) => now.difference(t) < _rejectionMemory).length
            case final n when n > 0)
          e.key: n,
    };
  }

  Map<String, List<DateTime>> _decodeRejections() {
    try {
      final json = jsonDecode(_prefs.tonightRejectionsJson ?? '{}');
      if (json is! Map) return {};
      return {
        for (final e in json.entries)
          if (e.value is List)
            '${e.key}': [
              for (final t in e.value as List)
                if (t is String)
                  if (DateTime.tryParse(t) case final d?) d.toLocal(),
            ],
      };
    } catch (_) {
      return {};
    }
  }

  /// "Another idea": the pick was passed over.
  Future<void> rejected(TonightPick pick) async {
    final now = DateTime.now();
    final all = _decodeRejections();
    final times = [
      ...?all[pick.candidate.key],
      now,
    ].where((t) => now.difference(t) < _rejectionMemory).toList();
    all[pick.candidate.key] = times;
    // Forget what is long past.
    all.removeWhere(
      (_, list) => list.every((t) => now.difference(t) >= _rejectionMemory),
    );
    await _prefs.setTonightRejectionsJson(
      jsonEncode({
        for (final e in all.entries)
          e.key: [for (final t in e.value) t.toUtc().toIso8601String()],
      }),
    );
    await _learn(pick.features, reward: -0.3);
  }

  /// The viewer chose [pick], over the picks shown before it.
  Future<void> launched(TonightPick pick, {List<TonightPick> over = const []}) async {
    if (over.isEmpty) {
      await _learn(pick.features, reward: 0.5);
    } else {
      for (final passed in over) {
        await _learn(pick.features, over: passed.features, reward: 0.5);
      }
    }
    final session = _session ?? _Session.decode(_prefs.tonightSessionJson);
    final c = pick.candidate;
    _session = (session ?? _Session(at: DateTime.now(), shown: const []))
        .withLaunched(
          _Launch(
            at: DateTime.now(),
            key: c.key,
            tmdbKey: c.tmdbKey,
            libraryItemId: c.libraryItemId,
            playItemId: c.playItemId,
            features: pick.features,
          ),
        );
    await _prefs.setTonightSessionJson(_session!.encode());
  }

  // ---------------------------------------------------------------------
  // Requests

  /// Asks Seerr for [candidate]: the film, or a series' first season.
  Future<TonightRequestOutcome> request(TonightCandidate candidate) async {
    final tmdbId = candidate.tmdbId;
    if (tmdbId == null) return TonightRequestOutcome.failed;
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.createRequest(
        mediaId: tmdbId,
        mediaType: candidate.mediaType,
        seasons: candidate.isMovie ? null : const [1],
      );
      ForYouService.instance.markRequested(candidate.mediaType, tmdbId);
      await _addPending(candidate);
      return TonightRequestOutcome.sent;
    } on SeerrRequestException catch (e) {
      if (e.kind == SeerrRequestErrorKind.duplicate) {
        await _addPending(candidate);
        return TonightRequestOutcome.alreadyThere;
      }
      debugPrint('[Tonight] Request refused: $e');
      return TonightRequestOutcome.failed;
    } catch (e) {
      debugPrint('[Tonight] Request failed: $e');
      return TonightRequestOutcome.failed;
    }
  }

  List<TonightPending> _pending() {
    try {
      final json = jsonDecode(_prefs.tonightPendingJson ?? '[]');
      if (json is! List) return [];
      return [
        for (final raw in json)
          if (TonightPending.fromJson(raw) case final p?) p,
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _savePending(List<TonightPending> list) =>
      _prefs.setTonightPendingJson(
        jsonEncode([for (final p in list) p.toJson()]),
      );

  Future<void> _addPending(TonightCandidate c) async {
    final list = _pending().where((p) => p.key != c.key).toList()
      ..add(
        TonightPending(
          key: c.key,
          title: c.title,
          mediaType: c.mediaType,
          tmdbId: c.tmdbId!,
          at: DateTime.now(),
        ),
      );
    await _savePending(list);
  }

  /// The library copy of [candidate], once it is there.
  Future<AggregatedItem?> findInLibrary(TonightCandidate candidate) async {
    final tmdbId = candidate.tmdbId;
    if (tmdbId == null) return null;
    final client = GetIt.instance<MediaServerClient>();
    return RowDataSource(client).findByTmdb(
      client.baseUrl,
      mediaType: candidate.mediaType,
      tmdbId: tmdbId,
    );
  }

  /// A request from Tonight that is taking too long, if any. Requests that
  /// landed, or are days old, are let go.
  Future<TonightPending?> _stalledRequest(
    RowDataSource source,
    String serverId,
  ) async {
    final now = DateTime.now();
    final list = _pending();
    if (list.isEmpty) return null;
    final keep = <TonightPending>[];
    TonightPending? stalled;
    for (final pending in list) {
      if (now.difference(pending.at) > const Duration(hours: 48)) continue;
      if (now.difference(pending.at) < stallAfter) {
        keep.add(pending);
        continue;
      }
      final found = await source.findByTmdb(
        serverId,
        mediaType: pending.mediaType,
        tmdbId: pending.tmdbId,
      );
      if (found != null) continue;
      keep.add(pending);
      stalled ??= pending;
    }
    if (keep.length != list.length) await _savePending(keep);
    return stalled;
  }

  @visibleForTesting
  void reset() {
    _library.clear();
    _discover.clear();
    _movieRuntimes.clear();
    _live.clear();
    _session = null;
  }
}

class _Live {
  final AggregatedItem item;
  final DateTime startedAt;
  final int startTicks;

  const _Live({
    required this.item,
    required this.startedAt,
    required this.startTicks,
  });
}

class _Shown {
  final String key;
  final Map<String, double> features;

  const _Shown({required this.key, required this.features});

  Map<String, dynamic> toJson() => {'key': key, 'f': features};

  static _Shown? fromJson(Object? json) {
    if (json is! Map) return null;
    return _Shown(key: json['key'] as String? ?? '', features: _features(json['f']));
  }
}

class _Launch {
  final DateTime at;
  final String key;
  final String? tmdbKey;
  final String? libraryItemId;
  final String? playItemId;
  final Map<String, double> features;

  const _Launch({
    required this.at,
    required this.key,
    required this.features,
    this.tmdbKey,
    this.libraryItemId,
    this.playItemId,
  });

  Map<String, dynamic> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'key': key,
    'tmdb': ?tmdbKey,
    'lib': ?libraryItemId,
    'play': ?playItemId,
    'f': features,
  };

  static _Launch? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (at == null) return null;
    return _Launch(
      at: at.toLocal(),
      key: json['key'] as String? ?? '',
      tmdbKey: json['tmdb'] as String?,
      libraryItemId: json['lib'] as String?,
      playItemId: json['play'] as String?,
      features: _features(json['f']),
    );
  }
}

Map<String, double> _features(Object? raw) => {
  if (raw is Map)
    for (final e in raw.entries)
      if (e.value is num) '${e.key}': (e.value as num).toDouble(),
};

class _Session {
  final DateTime at;
  final List<_Shown> shown;
  final _Launch? launched;

  const _Session({required this.at, required this.shown, this.launched});

  _Session withLaunched(_Launch? launch) =>
      _Session(at: at, shown: shown, launched: launch);

  String encode() => jsonEncode({
    'at': at.toUtc().toIso8601String(),
    'shown': [for (final s in shown) s.toJson()],
    'launched': ?launched?.toJson(),
  });

  static _Session? decode(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      final json = jsonDecode(source);
      if (json is! Map) return null;
      final at = DateTime.tryParse(json['at'] as String? ?? '');
      if (at == null) return null;
      return _Session(
        at: at.toLocal(),
        shown: [
          if (json['shown'] case final List list)
            for (final raw in list)
              if (_Shown.fromJson(raw) case final s?) s,
        ],
        launched: _Launch.fromJson(json['launched']),
      );
    } catch (_) {
      return null;
    }
  }
}
