import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/row_data_source.dart';
import '../../../data/services/seerr/for_you_service.dart';
import '../../../data/services/seerr/taste_profile.dart';
import '../../../data/services/seerr/taste_quiz.dart';
import '../../../data/services/seerr/taste_quiz_loader.dart';
import '../../../l10n/app_localizations.dart';
import '../../../preference/seerr_preferences.dart';
import '../../layout/screen_form.dart';
import '../../widgets/seerr/seerr_image_urls.dart';

/// Opens the taste questionnaire. Returns true once the viewer saved
/// answers, so the caller can refresh what it suggests.
Future<bool> openTasteQuestionnaire(BuildContext context) async {
  final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const TasteQuestionnaireScreen(),
    ),
  );
  return saved == true;
}

/// The questionnaire's screens, in order.
enum _Screen {
  welcome,
  context,
  format,
  pivots,
  grid,
  duels,
  limits,
  cinemas,
  recap,
}

/// The quick path keeps what says most: who, the favourites, one page of
/// posters and the limits.
const _quick = [
  _Screen.welcome,
  _Screen.context,
  _Screen.pivots,
  _Screen.grid,
  _Screen.limits,
  _Screen.recap,
];

const _full = _Screen.values;

enum _Verdict { liked, meh, disliked }

/// The cinemas offered, each standing for original languages.
enum _Cinema {
  france({'fr'}),
  english({'en'}),
  korea({'ko'}),
  japan({'ja'}),
  anime({}),
  spanish({'es'}),
  italy({'it'}),
  nordic({'sv', 'da', 'no', 'fi', 'is'}),
  india({'hi', 'ta', 'te'}),
  surprise({});

  final Set<String> languages;

  const _Cinema(this.languages);
}

/// Learns the viewer's taste in nine short screens, or six on the quick
/// path: who they watch with, what format, their all-time favourites,
/// posters to rate, duels between two posters, their limits, the cinemas
/// that draw them, and a summary they can correct.
///
/// Every screen can be skipped, and after the posters the whole thing can
/// be finished early. Answers to screens not reached are kept as they were.
class TasteQuestionnaireScreen extends StatefulWidget {
  const TasteQuestionnaireScreen({super.key});

  @override
  State<TasteQuestionnaireScreen> createState() =>
      _TasteQuestionnaireScreenState();
}

class _TasteQuestionnaireScreenState extends State<TasteQuestionnaireScreen> {
  static const maxPivots = 3;
  static const gridPageSize = 8;

  final _prefs = GetIt.instance<SeerrPreferences>();
  late final TasteProfile _previous;

  List<_Screen> _sequence = _full;
  int _index = 0;
  bool _saving = false;

  // Answers.
  late Set<String> _contexts;
  String? _kidsAge;
  late TasteMediaPref _mediaPref;
  late TasteMovieLength _movieLength;
  late TasteSeriesFormat _seriesFormat;
  final Map<String, QuizTitle> _pivots = {};
  final Map<String, _Verdict> _verdicts = {};
  final Map<String, QuizTitle> _rated = {};
  late Map<TasteAxis, double> _axes;
  late Set<TasteGenre> _avoided;
  late TasteViolence _violence;
  late TasteSubtitles _subtitles;
  late Set<_Cinema> _cinemas;
  late TasteEra _era;

  // Material.
  SeerrRepository? _repo;
  List<QuizTitle>? _pool;
  bool _poolFailed = false;
  List<QuizTitle> _libraryFavorites = const [];

  // Posters to rate.
  final List<List<QuizTitle>> _pages = [];
  int _page = 0;
  bool _pageLoading = false;
  final Map<String, List<QuizTitle>> _recsOfLiked = {};

  // Duels.
  final List<QuizDuel> _duels = [];
  int _duel = 0;

  // Search for favourites.
  final _searchController = TextEditingController();
  List<QuizTitle>? _searchResults;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    final p = TasteProfile.decode(_prefs.tasteProfileJson);
    _previous = p;
    _contexts = {...p.contexts};
    _kidsAge = p.kidsAge;
    _mediaPref = p.mediaPref;
    _movieLength = p.movieLength;
    _seriesFormat = p.seriesFormat;
    _axes = {...p.axes};
    _avoided = {...p.avoided};
    _violence = p.violence;
    _subtitles = p.subtitles;
    _era = p.era;
    _cinemas = {
      for (final cinema in _Cinema.values)
        if (cinema.languages.isNotEmpty &&
            cinema.languages.every(p.languages.contains))
          cinema,
      if (p.anime) _Cinema.anime,
      if (p.surpriseMe) _Cinema.surprise,
    };
    for (final pick in p.pivots) {
      _pivots[pick.key] = _fromPick(pick);
    }
    _loadMaterial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static QuizTitle _fromPick(TastePick pick) => QuizTitle(
    tmdbId: pick.tmdbId,
    mediaType: pick.mediaType,
    title: pick.title,
    posterPath: pick.posterPath,
    genres: pick.genres,
  );

  Future<void> _loadMaterial() async {
    try {
      final repo = await GetIt.instance.getAsync<SeerrRepository>();
      await repo.ensureInitialized();
      _repo = repo;
      final results = await Future.wait([
        loadQuizPool(repo),
        _loadLibraryFavorites(),
      ]);
      if (!mounted) return;
      setState(() {
        _pool = results[0];
        _libraryFavorites = results[1];
        _poolFailed = results[0].isEmpty;
      });
    } catch (e) {
      debugPrint('[Taste] Material failed: $e');
      if (!mounted) return;
      setState(() {
        _pool = const [];
        _poolFailed = true;
      });
    }
  }

  /// What the viewer watched most lately and favourited, as the first
  /// candidates for all-time favourites.
  Future<List<QuizTitle>> _loadLibraryFavorites() async {
    try {
      final client = GetIt.instance<MediaServerClient>();
      final history = await RowDataSource(
        client,
      ).loadTasteHistory(client.baseUrl);
      final seen = <String>{};
      final titles = <QuizTitle>[];
      for (final item in [...history.favorites, ...history.recent]) {
        final id = int.tryParse(item.tmdbId ?? '');
        if (id == null) continue;
        final type = item.type == 'Series' ? 'tv' : 'movie';
        if (!seen.add('$type:$id')) continue;
        titles.add(
          QuizTitle(
            tmdbId: id,
            mediaType: type,
            title: item.name,
            genres: TasteGenre.fromNames(item.genres),
            year: item.productionYear,
            imageUrl: client.imageApi.getPrimaryImageUrl(
              item.id,
              maxHeight: 450,
              tag: item.primaryImageTag,
            ),
          ),
        );
      }
      return titles.take(16).toList();
    } catch (e) {
      debugPrint('[Taste] Library favourites failed: $e');
      return const [];
    }
  }

  _Screen get _screen => _sequence[_index];

  bool get _isQuick => identical(_sequence, _quick);

  int get _gridPageCount => _isQuick ? 1 : 3;

  void _start(bool quick) {
    setState(() {
      _sequence = quick ? _quick : _full;
      _index = 1;
    });
  }

  Future<void> _next() async {
    if (_screen == _Screen.grid && _page < _gridPageCount - 1) {
      await _nextGridPage();
      return;
    }
    if (_index >= _sequence.length - 1) {
      await _finish();
      return;
    }
    setState(() => _index++);
    _prepare();
  }

  void _back() {
    if (_screen == _Screen.grid && _page > 0) {
      setState(() => _page--);
      return;
    }
    if (_screen == _Screen.duels && _duel > 0) {
      setState(() => _duel--);
      return;
    }
    if (_index > 0) setState(() => _index--);
  }

  void _jumpTo(_Screen screen) {
    final at = _sequence.indexOf(screen);
    setState(() {
      if (at >= 0) {
        _index = at;
      } else {
        // The quick path skipped it: carry on along the full path there.
        _sequence = _full;
        _index = _full.indexOf(screen);
      }
    });
    _prepare();
  }

  /// Readies what the new screen needs once the pool is there.
  void _prepare() {
    if (_screen == _Screen.grid && _pages.isEmpty) _buildFirstPage();
    if (_screen == _Screen.duels && _duels.isEmpty) _buildDuels();
  }

  void _buildFirstPage() {
    final pool = _pool;
    if (pool == null || pool.isEmpty) return;
    final page = pickGridPage(
      pool: pool,
      count: gridPageSize,
      exclude: _pivots.keys.toSet(),
      mediaPref: _mediaPref,
      avoided: _avoided,
      random: math.Random(),
    );
    setState(() {
      _pages.add(page);
      _page = 0;
    });
  }

  QuizSoFar get _soFar {
    final shown = [for (final page in _pages) ...page];
    List<QuizTitle> withVerdict(_Verdict v) => [
      for (final t in shown)
        if (_verdicts[t.key] == v) t,
    ];
    return QuizSoFar(
      liked: withVerdict(_Verdict.liked),
      meh: withVerdict(_Verdict.meh),
      disliked: withVerdict(_Verdict.disliked),
      unseen: shown.where((t) => !_verdicts.containsKey(t.key)).length,
    );
  }

  Future<void> _nextGridPage() async {
    if (_page < _pages.length - 1) {
      setState(() => _page++);
      return;
    }
    final pool = _pool;
    final repo = _repo;
    if (pool == null) return;
    setState(() => _pageLoading = true);
    final soFar = _soFar;
    if (repo != null) {
      final todo = [
        for (final liked in soFar.liked)
          if (!_recsOfLiked.containsKey(liked.key)) liked,
      ].take(4);
      await Future.wait(
        todo.map((liked) async {
          _recsOfLiked[liked.key] = await loadQuizRecommendations(repo, liked);
        }),
      );
    }
    if (!mounted) return;
    final page = pickGridPage(
      pool: pool,
      count: gridPageSize,
      exclude: {
        ..._pivots.keys,
        for (final p in _pages)
          for (final t in p) t.key,
      },
      mediaPref: _mediaPref,
      avoided: _avoided,
      soFar: soFar,
      recommendationsOfLiked: _recsOfLiked,
      random: math.Random(),
    );
    setState(() {
      _pageLoading = false;
      if (page.isNotEmpty) {
        _pages.add(page);
        _page = _pages.length - 1;
      } else {
        _index++;
      }
    });
    _prepare();
  }

  void _buildDuels() {
    final pool = _pool;
    if (pool == null || pool.isEmpty) return;
    final used = <String>{
      ..._pivots.keys,
      for (final p in _pages)
        for (final t in p) t.key,
    };
    final duels = <QuizDuel>[];
    for (final axis in TasteAxis.values) {
      final duel = buildDuel(axis, pool: pool, used: used, avoided: _avoided);
      if (duel == null) continue;
      used
        ..add(duel.left.key)
        ..add(duel.right.key);
      duels.add(duel);
    }
    setState(() {
      _duels
        ..clear()
        ..addAll(duels);
      _duel = 0;
    });
  }

  void _answerDuel(QuizDuel duel, double value) {
    HapticFeedback.selectionClick();
    setState(() {
      if (value == 0) {
        _axes.remove(duel.axis);
      } else {
        _axes[duel.axis] = value;
      }
      if (_duel < _duels.length - 1) {
        _duel++;
      } else {
        _index++;
      }
    });
  }

  void _cycleVerdict(QuizTitle title) {
    HapticFeedback.selectionClick();
    setState(() {
      final next = switch (_verdicts[title.key]) {
        null => _Verdict.liked,
        _Verdict.liked => _Verdict.meh,
        _Verdict.meh => _Verdict.disliked,
        _Verdict.disliked => null,
      };
      if (next == null) {
        _verdicts.remove(title.key);
        _rated.remove(title.key);
      } else {
        _verdicts[title.key] = next;
        _rated[title.key] = title;
      }
    });
  }

  void _togglePivot(QuizTitle title) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_pivots.remove(title.key) == null && _pivots.length < maxPivots) {
        _pivots[title.key] = title;
      }
    });
  }

  Future<void> _search() async {
    final repo = _repo;
    if (repo == null) return;
    setState(() => _searching = true);
    final results = await searchQuizTitles(repo, _searchController.text);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searchResults = results;
    });
  }

  TasteProfile _draft() {
    List<TastePick> merged(_Verdict verdict, List<TastePick> before) => [
      // Earlier answers stay unless the title was rated again.
      for (final p in before)
        if (!_verdicts.containsKey(p.key)) p,
      for (final e in _verdicts.entries)
        if (e.value == verdict) _rated[e.key]!.toPick(),
    ];

    final languages = <String>{
      for (final cinema in _cinemas) ...cinema.languages,
    };
    final draft = _previous.copyWith(
      mediaPref: _mediaPref,
      era: _era,
      avoided: _avoided,
      languages: languages,
      favorites: merged(_Verdict.liked, _previous.favorites),
      meh: merged(_Verdict.meh, _previous.meh),
      disliked: merged(_Verdict.disliked, _previous.disliked),
      pivots: _pivots.isEmpty
          ? _previous.pivots
          : [for (final t in _pivots.values) t.toPick()],
      contexts: _contexts,
      kidsAge: _kidsAge,
      movieLength: _movieLength,
      seriesFormat: _seriesFormat,
      axes: _axes,
      violence: _violence,
      subtitles: _subtitles,
      anime: _cinemas.contains(_Cinema.anime),
      surpriseMe: _cinemas.contains(_Cinema.surprise),
    );
    // Genres clearly liked, read from the titles rated.
    final liked = {
      for (final e in draft.genreAffinity.entries)
        if (e.value >= 0.4) e.key,
    }..removeAll(_avoided);
    return draft.copyWith(liked: liked);
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    final profile = _draft().copyWith(updatedAt: DateTime.now());
    await _prefs.setTasteProfileJson(profile.encode());
    await _prefs.setTastePromptedAt(DateTime.now().millisecondsSinceEpoch);
    ForYouService.instance.clearCache();
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _later() async {
    await _prefs.setTastePromptedAt(DateTime.now().millisecondsSinceEpoch);
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onBg = AppColorScheme.onBackground;
    final step = _index;
    final total = _sequence.length - 1;

    final (title, hint) = switch (_screen) {
      _Screen.welcome => (l10n.quizWelcomeTitle, l10n.quizWelcomeHint),
      _Screen.context => (l10n.quizContextTitle, l10n.quizContextHint),
      _Screen.format => (l10n.quizFormatTitle, l10n.quizFormatHint),
      _Screen.pivots => (l10n.quizPivotsTitle, l10n.quizPivotsHint(maxPivots)),
      _Screen.grid => (l10n.quizGridTitle, l10n.quizGridHint),
      _Screen.duels => (l10n.quizDuelsTitle, l10n.quizDuelsHint),
      _Screen.limits => (l10n.quizLimitsTitle, l10n.quizLimitsHint),
      _Screen.cinemas => (l10n.quizCinemasTitle, l10n.quizCinemasHint),
      _Screen.recap => (l10n.quizRecapTitle, l10n.quizRecapHint),
    };

    final form = ScreenForm.of(context);
    final compact = form == ScreenForm.cover;

    final header = <Widget>[
      Row(
        children: [
          Icon(Icons.tune_rounded, color: AppColorScheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.tasteTitle,
              style: TextStyle(
                color: onBg,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (step > 0)
            Text(
              l10n.tasteStepOf(step, total),
              style: TextStyle(color: onBg.withValues(alpha: 0.6), fontSize: 13),
            ),
        ],
      ),
      SizedBox(height: compact ? 8 : 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: total == 0 ? 0 : step / total,
          minHeight: 4,
          color: AppColorScheme.accent,
          backgroundColor: onBg.withValues(alpha: 0.12),
        ),
      ),
      SizedBox(height: compact ? 12 : 18),
      Text(
        title,
        style: TextStyle(
          color: onBg,
          fontSize: compact ? 21 : 25,
          fontWeight: FontWeight.w800,
          height: 1.15,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        hint,
        // A cover screen is short: the hint gives way to the posters.
        maxLines: compact ? 2 : null,
        overflow: compact ? TextOverflow.ellipsis : null,
        style: TextStyle(
          color: onBg.withValues(alpha: 0.7),
          fontSize: compact ? 13.5 : 14.5,
          height: 1.35,
        ),
      ),
    ];
    final screen = FocusTraversalGroup(
      key: ValueKey('${_screen.name}-$_page-$_duel'),
      child: _buildScreen(l10n),
    );

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColorScheme.background,
        body: SafeArea(
          child: Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(16, 10, 16, 10)
                : const EdgeInsets.fromLTRB(24, 16, 24, 14),
            // An opened foldable held sideways keeps the questions in a
            // column the eye can follow instead of running them across the
            // whole width.
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: form == ScreenForm.unfolded
                      ? 760
                      : double.infinity,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...header,
                    SizedBox(height: compact ? 10 : 16),
                    Expanded(child: screen),
                    const SizedBox(height: 10),
                    _buildFooter(l10n),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScreen(AppLocalizations l10n) {
    switch (_screen) {
      case _Screen.welcome:
        return _scroll([
          _ModeCard(
            title: l10n.quizQuick,
            subtitle: l10n.quizQuickSub,
            icon: Icons.bolt_rounded,
            autofocus: true,
            onTap: () => _start(true),
          ),
          const SizedBox(height: 12),
          _ModeCard(
            title: l10n.quizFull,
            subtitle: l10n.quizFullSub,
            icon: Icons.auto_awesome_rounded,
            onTap: () => _start(false),
          ),
        ]);
      case _Screen.context:
        return _scroll([
          _section(l10n.quizContextWho, [
            for (final (i, c) in _contextKeys.indexed)
              _Chip(
                label: _contextLabel(l10n, c),
                icon: switch (c) {
                  'alone' => Icons.person_rounded,
                  'couple' => Icons.favorite_rounded,
                  'family' => Icons.family_restroom_rounded,
                  _ => Icons.groups_rounded,
                },
                selected: _contexts.contains(c),
                autofocus: i == 0,
                onTap: () => setState(() {
                  if (!_contexts.remove(c)) _contexts.add(c);
                }),
              ),
          ]),
          if (_contexts.contains('family'))
            _section(l10n.quizContextKids, [
              for (final age in const ['under7', 'from7to12', 'teen'])
                _Chip(
                  label: switch (age) {
                    'under7' => l10n.tonightKidsUnder7,
                    'from7to12' => l10n.tonightKids7to12,
                    _ => l10n.tonightKidsTeen,
                  },
                  selected: _kidsAge == age,
                  onTap: () => setState(() => _kidsAge = age),
                ),
            ]),
        ]);
      case _Screen.format:
        return _scroll([
          _section(l10n.tasteMediaQuestion, [
            for (final (i, pref) in TasteMediaPref.values.indexed)
              _Chip(
                label: switch (pref) {
                  TasteMediaPref.both => l10n.tasteMediaBoth,
                  TasteMediaPref.movies => l10n.tasteMediaMovies,
                  TasteMediaPref.series => l10n.tasteMediaSeries,
                },
                selected: _mediaPref == pref,
                autofocus: i == 0,
                onTap: () => setState(() => _mediaPref = pref),
              ),
          ]),
          _section(l10n.quizLengthQuestion, [
            for (final length in TasteMovieLength.values)
              _Chip(
                label: _lengthLabel(l10n, length),
                selected: _movieLength == length,
                onTap: () => setState(() => _movieLength = length),
              ),
          ]),
          _section(l10n.quizSeriesQuestion, [
            for (final format in TasteSeriesFormat.values)
              _Chip(
                label: _seriesLabel(l10n, format),
                selected: _seriesFormat == format,
                onTap: () => setState(() => _seriesFormat = format),
              ),
          ]),
        ]);
      case _Screen.pivots:
        return _buildPivots(l10n);
      case _Screen.grid:
        return _buildGrid(l10n);
      case _Screen.duels:
        return _buildDuel(l10n);
      case _Screen.limits:
        return _scroll([
          _section(l10n.tasteAvoidedQuestion, [
            for (final (i, genre) in TasteGenre.values.indexed)
              _Chip(
                label: tasteGenreLabel(l10n, genre),
                selected: _avoided.contains(genre),
                danger: true,
                autofocus: i == 0,
                onTap: () => setState(() {
                  if (!_avoided.remove(genre)) _avoided.add(genre);
                }),
              ),
          ]),
          _section(l10n.quizViolenceQuestion, [
            for (final v in TasteViolence.values)
              _Chip(
                label: switch (v) {
                  TasteViolence.none => l10n.quizViolenceNone,
                  TasteViolence.justified => l10n.quizViolenceJustified,
                  TasteViolence.fine => l10n.quizViolenceFine,
                },
                selected: _violence == v,
                onTap: () => setState(() => _violence = v),
              ),
          ]),
          _section(l10n.quizSubtitlesQuestion, [
            for (final s in TasteSubtitles.values)
              _Chip(
                label: switch (s) {
                  TasteSubtitles.never => l10n.quizSubtitlesNever,
                  TasteSubtitles.depends => l10n.quizSubtitlesDepends,
                  TasteSubtitles.gladly => l10n.quizSubtitlesGladly,
                },
                selected: _subtitles == s,
                onTap: () => setState(() => _subtitles = s),
              ),
          ]),
        ]);
      case _Screen.cinemas:
        return _scroll([
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (i, cinema) in _Cinema.values.indexed)
                _Chip(
                  label: _cinemaLabel(l10n, cinema),
                  icon: cinema == _Cinema.surprise
                      ? Icons.casino_rounded
                      : null,
                  selected: _cinemas.contains(cinema),
                  autofocus: i == 0,
                  onTap: () => setState(() {
                    if (!_cinemas.remove(cinema)) _cinemas.add(cinema);
                  }),
                ),
            ],
          ),
        ]);
      case _Screen.recap:
        return _buildRecap(l10n);
    }
  }

  static const _contextKeys = ['alone', 'couple', 'family', 'friends'];

  static String _contextLabel(AppLocalizations l10n, String c) => switch (c) {
    'alone' => l10n.tonightWhoAlone,
    'couple' => l10n.tonightWhoCouple,
    'family' => l10n.quizContextFamily,
    _ => l10n.tonightWhoFriends,
  };

  Widget _buildPivots(AppLocalizations l10n) {
    final onBg = AppColorScheme.onBackground;
    final pool = _pool;
    final famous = pool == null
        ? const <QuizTitle>[]
        : ([...pool]..sort((a, b) => b.votes.compareTo(a.votes))).take(40);
    final seen = <String>{};
    final tiles = [
      for (final t in [
        ..._pivots.values,
        ...?_searchResults,
        ..._libraryFavorites,
        ...famous,
      ])
        if (seen.add(t.key)) t,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                style: TextStyle(color: onBg),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n.quizSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _Chip(
              label: l10n.quizSearch,
              icon: Icons.search_rounded,
              selected: false,
              onTap: _search,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.quizPivotsCount(_pivots.length, maxPivots),
          style: TextStyle(
            color: AppColorScheme.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _searching || (pool == null && _libraryFavorites.isEmpty)
              ? const Center(child: CircularProgressIndicator())
              : _posterGrid(
                  tiles,
                  badge: (t) => _pivots.containsKey(t.key)
                      ? const _Badge(Icons.star_rounded, Color(0xFFFFB300))
                      : null,
                  onTap: _togglePivot,
                ),
        ),
      ],
    );
  }

  Widget _buildGrid(AppLocalizations l10n) {
    if (_pool == null || _pageLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pages.isEmpty) {
      if (_poolFailed) return _failed(l10n);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.isEmpty && _screen == _Screen.grid) {
          _buildFirstPage();
        }
      });
      return const Center(child: CircularProgressIndicator());
    }
    final page = _pages[_page.clamp(0, _pages.length - 1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.quizGridPage(_page + 1, _gridPageCount),
          style: TextStyle(
            color: AppColorScheme.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _posterGrid(
            page,
            badge: (t) => switch (_verdicts[t.key]) {
              _Verdict.liked => const _Badge(
                Icons.thumb_up_rounded,
                Color(0xFF43A047),
              ),
              _Verdict.meh => const _Badge(
                Icons.sentiment_neutral_rounded,
                Color(0xFFFFA000),
              ),
              _Verdict.disliked => const _Badge(
                Icons.thumb_down_rounded,
                Color(0xFFE53935),
              ),
              null => null,
            },
            onTap: _cycleVerdict,
          ),
        ),
      ],
    );
  }

  Widget _buildDuel(AppLocalizations l10n) {
    if (_pool == null) return const Center(child: CircularProgressIndicator());
    if (_duels.isEmpty) {
      if (_poolFailed) return _failed(l10n);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _duels.isEmpty && _screen == _Screen.duels) {
          _buildDuels();
        }
      });
      return const Center(child: CircularProgressIndicator());
    }
    final duel = _duels[_duel.clamp(0, _duels.length - 1)];
    final onBg = AppColorScheme.onBackground;
    Widget side(QuizTitle title, double value, {bool autofocus = false}) =>
        Expanded(
          child: _DuelPoster(
            title: title,
            autofocus: autofocus,
            selected: (_axes[duel.axis] ?? 0) == value,
            onTap: () => _answerDuel(duel, value),
          ),
        );
    return Column(
      children: [
        Text(
          l10n.quizDuelCount(_duel + 1, _duels.length),
          style: TextStyle(
            color: AppColorScheme.accent,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              side(duel.left, -1, autofocus: true),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Text(
                    l10n.quizOr,
                    style: TextStyle(
                      color: onBg.withValues(alpha: 0.6),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              side(duel.right, 1),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Chip(
          label: l10n.quizNeither,
          selected: false,
          onTap: () => _answerDuel(duel, 0),
        ),
      ],
    );
  }

  Widget _buildRecap(AppLocalizations l10n) {
    final draft = _draft();
    final lines = <(String, _Screen)>[];

    if (draft.contexts.isNotEmpty) {
      final who = [
        for (final c in _contextKeys)
          if (draft.contexts.contains(c)) _contextLabel(l10n, c).toLowerCase(),
      ].join(', ');
      lines.add((l10n.quizRecapContext(who), _Screen.context));
    }

    final format = [
      switch (draft.mediaPref) {
        TasteMediaPref.both => l10n.tasteMediaBoth,
        TasteMediaPref.movies => l10n.tasteMediaMovies,
        TasteMediaPref.series => l10n.tasteMediaSeries,
      },
      if (draft.movieLength != TasteMovieLength.any)
        _lengthLabel(l10n, draft.movieLength).toLowerCase(),
      if (draft.seriesFormat != TasteSeriesFormat.any)
        _seriesLabel(l10n, draft.seriesFormat).toLowerCase(),
    ].join(', ');
    lines.add((format, _Screen.format));

    final affinity = draft.genreAffinity.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final loved = [
      for (final e in affinity)
        if (e.value > 0.15) tasteGenreLabel(l10n, e.key).toLowerCase(),
    ].take(3).toList();
    final less = [
      for (final e in affinity.reversed)
        if (e.value < -0.1) tasteGenreLabel(l10n, e.key).toLowerCase(),
    ].take(2).toList();
    if (loved.isNotEmpty) {
      lines.add((l10n.quizRecapLoves(loved.join(', ')), _Screen.grid));
    }
    if (less.isNotEmpty) {
      lines.add((l10n.quizRecapLess(less.join(', ')), _Screen.grid));
    }

    final leanings = [
      for (final axis in TasteAxis.values)
        if (draft.axes[axis] case final v? when v != 0)
          _axisLabel(l10n, axis, v),
    ];
    if (leanings.isNotEmpty) {
      lines.add((l10n.quizRecapLeanings(leanings.join(', ')), _Screen.duels));
    }

    if (draft.avoided.isNotEmpty) {
      lines.add((
        l10n.quizRecapNever(
          draft.avoided
              .map((g) => tasteGenreLabel(l10n, g).toLowerCase())
              .join(', '),
        ),
        _Screen.limits,
      ));
    }
    switch (draft.violence) {
      case TasteViolence.none:
        lines.add((l10n.quizRecapNoViolence, _Screen.limits));
      case TasteViolence.justified:
        lines.add((l10n.quizRecapSomeViolence, _Screen.limits));
      case TasteViolence.fine:
        break;
    }
    switch (draft.subtitles) {
      case TasteSubtitles.never:
        lines.add((l10n.quizRecapNoSubtitles, _Screen.limits));
      case TasteSubtitles.gladly:
        lines.add((l10n.quizRecapSubtitles, _Screen.limits));
      case TasteSubtitles.depends:
        break;
    }

    if (_cinemas.isNotEmpty) {
      lines.add((
        l10n.quizRecapCinemas(
          _cinemas.map((c) => _cinemaLabel(l10n, c).toLowerCase()).join(', '),
        ),
        _Screen.cinemas,
      ));
    }

    final niche = _axes[TasteAxis.popularNiche] ?? 0;
    return _scroll([
      for (final (i, line) in lines.indexed)
        _RecapLine(
          text: line.$1,
          autofocus: i == 0,
          onTap: () => _jumpTo(line.$2),
        ),
      const SizedBox(height: 14),
      _section(l10n.quizRecapKnown, [
        _Chip(
          label: l10n.quizMoreKnown,
          selected: niche < -0.5,
          onTap: () => setState(() => _axes[TasteAxis.popularNiche] = -1.5),
        ),
        _Chip(
          label: l10n.quizBalanced,
          selected: niche.abs() <= 0.5,
          onTap: () => setState(() => _axes.remove(TasteAxis.popularNiche)),
        ),
        _Chip(
          label: l10n.quizMoreNiche,
          selected: niche > 0.5,
          onTap: () => setState(() => _axes[TasteAxis.popularNiche] = 1.5),
        ),
      ]),
      _section(l10n.quizRecapEra, [
        _Chip(
          label: l10n.quizMoreRecent,
          selected: _era == TasteEra.recent,
          onTap: () => setState(() => _era = TasteEra.recent),
        ),
        _Chip(
          label: l10n.tasteEraAny,
          selected: _era == TasteEra.any,
          onTap: () => setState(() => _era = TasteEra.any),
        ),
        _Chip(
          label: l10n.quizMoreClassic,
          selected: _era == TasteEra.classic,
          onTap: () => setState(() => _era = TasteEra.classic),
        ),
      ]),
    ]);
  }

  Widget _failed(AppLocalizations l10n) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.tastePicksEmpty,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColorScheme.onBackground.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        _Chip(
          label: l10n.tastePicksRetry,
          icon: Icons.refresh_rounded,
          selected: false,
          autofocus: true,
          onTap: () {
            setState(() {
              _pool = null;
              _poolFailed = false;
            });
            _loadMaterial();
          },
        ),
      ],
    ),
  );

  Widget _posterGrid(
    List<QuizTitle> titles, {
    required _Badge? Function(QuizTitle) badge,
    required void Function(QuizTitle) onTap,
  }) => GridView.builder(
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 150,
      childAspectRatio: 2 / 3.35,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
    ),
    itemCount: titles.length,
    itemBuilder: (context, index) {
      final t = titles[index];
      return _PosterTile(
        key: ValueKey(t.key),
        title: t.title,
        year: t.year,
        imageUrl: _imageOf(t),
        badge: badge(t),
        autofocus: index == 0,
        onTap: () => onTap(t),
      );
    },
  );

  static String? _imageOf(QuizTitle t) {
    if (t.imageUrl != null) return t.imageUrl;
    final poster = t.posterPath;
    return poster == null || poster.isEmpty ? null : '$seerrPosterBase$poster';
  }

  Widget _scroll(List<Widget> children) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _section(String title, List<Widget> chips) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColorScheme.onBackground.withValues(alpha: 0.8),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: chips),
      ],
    ),
  );

  Widget _buildFooter(AppLocalizations l10n) {
    if (_screen == _Screen.welcome) {
      return Row(
        children: [
          TextButton(
            onPressed: _saving ? null : _later,
            child: Text(l10n.tasteLater),
          ),
        ],
      );
    }
    final last = _index == _sequence.length - 1;
    final gridHasMore = _screen == _Screen.grid && _page < _gridPageCount - 1;
    final canFinishEarly = !last && _index >= _sequence.indexOf(_Screen.grid);
    final back = TextButton(
      onPressed: _saving ? null : _back,
      child: Text(l10n.tasteBack),
    );
    final finishNow = TextButton(
      onPressed: _saving ? null : _finish,
      child: Text(l10n.quizFinishNow),
    );
    final next = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppColorScheme.accent,
        foregroundColor: AppColorScheme.onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
      onPressed: _saving || _pageLoading ? null : _next,
      icon: Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded),
      label: Text(
        last
            ? l10n.tasteFinish
            : gridHasMore
            ? l10n.quizNextPage
            : (_screen == _Screen.duels ? l10n.quizSkip : l10n.tasteNext),
      ),
    );
    return Row(
      children: [
        back,
        const Spacer(),
        if (canFinishEarly) ...[finishNow, const SizedBox(width: 8)],
        next,
      ],
    );
  }

  static String _lengthLabel(AppLocalizations l10n, TasteMovieLength l) =>
      switch (l) {
        TasteMovieLength.short => l10n.quizLengthShort,
        TasteMovieLength.medium => l10n.quizLengthMedium,
        TasteMovieLength.long => l10n.quizLengthLong,
        TasteMovieLength.any => l10n.tasteEraAny,
      };

  static String _seriesLabel(AppLocalizations l10n, TasteSeriesFormat f) =>
      switch (f) {
        TasteSeriesFormat.mini => l10n.quizSeriesMini,
        TasteSeriesFormat.few => l10n.quizSeriesFew,
        TasteSeriesFormat.long => l10n.quizSeriesLong,
        TasteSeriesFormat.any => l10n.tasteEraAny,
      };

  static String _cinemaLabel(AppLocalizations l10n, _Cinema c) => switch (c) {
    _Cinema.france => l10n.quizCinemaFrance,
    _Cinema.english => l10n.quizCinemaEnglish,
    _Cinema.korea => l10n.quizCinemaKorea,
    _Cinema.japan => l10n.quizCinemaJapan,
    _Cinema.anime => l10n.quizCinemaAnime,
    _Cinema.spanish => l10n.quizCinemaSpanish,
    _Cinema.italy => l10n.quizCinemaItaly,
    _Cinema.nordic => l10n.quizCinemaNordic,
    _Cinema.india => l10n.quizCinemaIndia,
    _Cinema.surprise => l10n.quizCinemaSurprise,
  };

  static String _axisLabel(AppLocalizations l10n, TasteAxis axis, double v) {
    final second = v > 0;
    return switch (axis) {
      TasteAxis.darkLight => second ? l10n.quizAxisLight : l10n.quizAxisDark,
      TasteAxis.realImaginary =>
        second ? l10n.quizAxisImaginary : l10n.quizAxisReal,
      TasteAxis.slowFast => second ? l10n.quizAxisFast : l10n.quizAxisSlow,
      TasteAxis.recentClassic =>
        second ? l10n.quizAxisClassic : l10n.quizAxisRecent,
      TasteAxis.popularNiche =>
        second ? l10n.quizAxisNiche : l10n.quizAxisPopular,
      TasteAxis.spectacleIntimate =>
        second ? l10n.quizAxisIntimate : l10n.quizAxisSpectacle,
    };
  }
}

class _Badge {
  final IconData icon;
  final Color color;

  const _Badge(this.icon, this.color);
}

/// A pill that shows clearly when a remote is on it, and when it is chosen.
class _Chip extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final bool danger;
  final bool autofocus;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.danger = false,
    this.autofocus = false,
  });

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onBg = AppColorScheme.onBackground;
    final tint = widget.danger ? const Color(0xFFE53935) : AppColorScheme.accent;
    final fill = widget.selected
        ? tint.withValues(alpha: 0.9)
        : onBg.withValues(alpha: 0.08);
    final text = widget.selected ? Colors.white : onBg;
    return InkWell(
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(24),
      onFocusChange: (f) => setState(() => _focused = f),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _focused ? onBg : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.selected)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  widget.danger ? Icons.block_rounded : Icons.check_rounded,
                  size: 18,
                  color: text,
                ),
              )
            else if (widget.icon != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(widget.icon, size: 18, color: text),
              ),
            Text(
              widget.label,
              style: TextStyle(
                color: text,
                fontSize: 15,
                fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool autofocus;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onBg = AppColorScheme.onBackground;
    return InkWell(
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(16),
      onFocusChange: (f) => setState(() => _focused = f),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: onBg.withValues(alpha: _focused ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _focused ? onBg : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(widget.icon, color: AppColorScheme.accent, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: onBg,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      color: onBg.withValues(alpha: 0.7),
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecapLine extends StatefulWidget {
  final String text;
  final bool autofocus;
  final VoidCallback onTap;

  const _RecapLine({
    required this.text,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_RecapLine> createState() => _RecapLineState();
}

class _RecapLineState extends State<_RecapLine> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onBg = AppColorScheme.onBackground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        autofocus: widget.autofocus,
        borderRadius: BorderRadius.circular(12),
        onFocusChange: (f) => setState(() => _focused = f),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: onBg.withValues(alpha: _focused ? 0.14 : 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? onBg : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: AppColorScheme.accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.text,
                  style: TextStyle(color: onBg, fontSize: 15.5),
                ),
              ),
              Icon(
                Icons.edit_rounded,
                size: 18,
                color: onBg.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DuelPoster extends StatefulWidget {
  final QuizTitle title;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  const _DuelPoster({
    required this.title,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_DuelPoster> createState() => _DuelPosterState();
}

class _DuelPosterState extends State<_DuelPoster> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onBg = AppColorScheme.onBackground;
    final t = widget.title;
    final url = _TasteQuestionnaireScreenState._imageOf(t);
    return InkWell(
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(14),
      onFocusChange: (f) => setState(() => _focused = f),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _focused ? 1.03 : 1,
        duration: const Duration(milliseconds: 120),
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: widget.selected
                          ? AppColorScheme.accent
                          : (_focused ? Colors.white : Colors.transparent),
                      width: 3,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: url == null
                        ? Container(color: onBg.withValues(alpha: 0.08))
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Container(color: onBg.withValues(alpha: 0.08)),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.year == null ? t.title : '${t.title} (${t.year})',
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onBg,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterTile extends StatefulWidget {
  final String title;
  final int? year;
  final String? imageUrl;
  final _Badge? badge;
  final bool autofocus;
  final VoidCallback onTap;

  const _PosterTile({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.onTap,
    this.year,
    this.badge,
    this.autofocus = false,
  });

  @override
  State<_PosterTile> createState() => _PosterTileState();
}

class _PosterTileState extends State<_PosterTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onBg = AppColorScheme.onBackground;
    final url = widget.imageUrl;
    final badge = widget.badge;
    final fallback = Container(
      color: Colors.white10,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        widget.title,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
    return InkWell(
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(10),
      onFocusChange: (f) => setState(() => _focused = f),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _focused ? 1.05 : 1,
        duration: const Duration(milliseconds: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: badge != null
                        ? badge.color
                        : (_focused ? Colors.white : Colors.transparent),
                    width: 3,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (url != null)
                        Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => fallback,
                        )
                      else
                        fallback,
                      if (badge != null)
                        Container(
                          color: Colors.black.withValues(alpha: 0.35),
                          alignment: Alignment.center,
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: badge.color,
                            child: Icon(
                              badge.icon,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.year == null
                  ? widget.title
                  : '${widget.title} · ${widget.year}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onBg.withValues(alpha: _focused ? 1 : 0.75),
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A questionnaire genre, as the viewer reads it.
String tasteGenreLabel(AppLocalizations l10n, TasteGenre genre) =>
    switch (genre) {
      TasteGenre.action => l10n.tasteGenreAction,
      TasteGenre.adventure => l10n.tasteGenreAdventure,
      TasteGenre.animation => l10n.tasteGenreAnimation,
      TasteGenre.comedy => l10n.tasteGenreComedy,
      TasteGenre.crime => l10n.tasteGenreCrime,
      TasteGenre.documentary => l10n.tasteGenreDocumentary,
      TasteGenre.drama => l10n.tasteGenreDrama,
      TasteGenre.family => l10n.tasteGenreFamily,
      TasteGenre.fantasy => l10n.tasteGenreFantasy,
      TasteGenre.history => l10n.tasteGenreHistory,
      TasteGenre.horror => l10n.tasteGenreHorror,
      TasteGenre.kids => l10n.tasteGenreKids,
      TasteGenre.music => l10n.tasteGenreMusic,
      TasteGenre.mystery => l10n.tasteGenreMystery,
      TasteGenre.reality => l10n.tasteGenreReality,
      TasteGenre.romance => l10n.tasteGenreRomance,
      TasteGenre.scifi => l10n.tasteGenreScifi,
      TasteGenre.talk => l10n.tasteGenreTalk,
      TasteGenre.thriller => l10n.tasteGenreThriller,
      TasteGenre.war => l10n.tasteGenreWar,
      TasteGenre.western => l10n.tasteGenreWestern,
    };

/// An original language the questionnaire offers, as the viewer reads it.
String tasteLanguageLabel(AppLocalizations l10n, String code) =>
    switch (code) {
      'fr' => l10n.tasteLangFr,
      'en' => l10n.tasteLangEn,
      'ru' => l10n.tasteLangRu,
      'uk' => l10n.tasteLangUk,
      'es' => l10n.tasteLangEs,
      'it' => l10n.tasteLangIt,
      'de' => l10n.tasteLangDe,
      'ja' => l10n.tasteLangJa,
      'ko' => l10n.tasteLangKo,
      _ => code,
    };
