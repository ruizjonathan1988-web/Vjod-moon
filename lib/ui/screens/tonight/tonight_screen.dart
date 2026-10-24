import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/services/tonight/tonight_engine.dart';
import '../../../data/services/tonight/tonight_models.dart';
import '../../../data/services/tonight/tonight_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../layout/screen_form.dart';
import '../../navigation/destinations.dart';
import '../../widgets/bounded_network_image.dart';
import '../taste/taste_questionnaire_screen.dart';

/// Opens Tonight. Whatever the viewer picks to play or read about opens
/// once Tonight has closed.
Future<void> showTonight(BuildContext context) async {
  final router = GoRouter.of(context);
  final destination = await Navigator.of(context, rootNavigator: true)
      .push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const TonightScreen(),
        ),
      );
  if (destination == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    router.push(destination);
  });
}

/// Helps choose what to watch tonight instead of scrolling: three quick
/// answers, then one clear suggestion and five others.
class TonightScreen extends StatefulWidget {
  const TonightScreen({super.key});

  @override
  State<TonightScreen> createState() => _TonightScreenState();
}

enum _Phase { questions, results }

/// How Tonight lays itself out on the screen it is on.
enum _Layout {
  /// A cover screen: short, so everything is tighter.
  compact,

  /// A regular phone: one column.
  phone,

  /// An opened foldable or a tablet: one roomy column, the other ideas in a
  /// single row across the width.
  open,

  /// TV and desktop: a wide banner with the details over the picture.
  wide;

  static _Layout of(BuildContext context) => switch (ScreenForm.of(context)) {
    ScreenForm.cover => compact,
    ScreenForm.phone => phone,
    ScreenForm.unfolded => open,
    ScreenForm.large => wide,
  };
}

enum _RequestState { requesting, requested, ready, failed }

class _TonightScreenState extends State<TonightScreen> {
  final _service = TonightService.instance;
  final _primaryFocus = FocusNode(debugLabel: 'TonightPrimary');

  _Phase _phase = _Phase.questions;
  late TonightAnswers _answers;

  TonightView? _view;
  bool _loading = false;
  bool _failed = false;

  /// The picks still on offer, the one on show first.
  List<TonightPick> _queue = [];
  int _hero = 0;

  /// Everything shown this evening, so another round brings new titles.
  final Set<String> _shown = {};

  /// Picks passed over with "Another idea".
  final List<TonightPick> _passed = [];

  final Map<String, _RequestState> _requests = {};
  final Map<String, String> _readyItems = {};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _answers = _service.suggestAnswers();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _primaryFocus.dispose();
    super.dispose();
  }

  String get _serverId => GetIt.instance<MediaServerClient>().baseUrl;

  Future<void> _go({bool more = false}) async {
    final answers = _answers.copyWith(at: DateTime.now());
    unawaited(_service.saveAnswers(answers));
    setState(() {
      _answers = answers;
      _phase = _Phase.results;
      _loading = true;
      _failed = false;
      if (!more) {
        _shown.clear();
        _passed.clear();
      }
    });
    try {
      final view = await _service.load(answers, exclude: {..._shown});
      if (!mounted) return;
      setState(() {
        _view = view;
        _queue = [...view.result.picks];
        _hero = 0;
        _shown.addAll(_queue.map((p) => p.candidate.key));
        _loading = false;
      });
      _focusPrimary();
    } catch (e) {
      debugPrint('[Tonight] Load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _focusPrimary() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _primaryFocus.canRequestFocus) {
        _primaryFocus.requestFocus();
      }
    });
  }

  TonightPick? get _current =>
      _queue.isEmpty ? null : _queue[_hero.clamp(0, _queue.length - 1)];

  Future<void> _another() async {
    final pick = _current;
    if (pick == null) return;
    unawaited(_service.rejected(pick));
    _passed.add(pick);
    setState(() {
      _queue.remove(pick);
      _hero = 0;
    });
    if (_queue.isEmpty) {
      await _go(more: true);
    } else {
      _focusPrimary();
    }
  }

  void _show(TonightPick pick) {
    setState(() => _hero = _queue.indexOf(pick));
    _focusPrimary();
  }

  List<TonightPick> _passedOver(TonightPick chosen) => [
    ..._passed,
    if (_queue.isNotEmpty && _queue.first != chosen) _queue.first,
  ];

  void _close(String destination) {
    Navigator.of(context).pop(destination);
  }

  Future<void> _primary(TonightPick pick) async {
    final c = pick.candidate;
    final ready = _readyItems[c.key];
    if (ready != null) {
      _close(Destinations.item(ready, serverId: _serverId, autoPlay: true));
      return;
    }
    final state = _requests[c.key];
    if (state == _RequestState.requesting || state == _RequestState.requested) {
      return;
    }

    if (c.availability == TonightAvailability.inLibrary) {
      var playId = c.playItemId ?? c.libraryItemId;
      if (playId == null) {
        final found = await _service.findInLibrary(c);
        playId = found?.id;
      }
      if (playId != null) {
        await _service.launched(pick, over: _passedOver(pick));
        if (mounted) {
          _close(Destinations.item(playId, serverId: _serverId, autoPlay: true));
        }
        return;
      }
    }

    if (c.availability == TonightAvailability.requested) {
      await _service.launched(pick, over: _passedOver(pick));
      setState(() => _requests[c.key] = _RequestState.requested);
      _startPolling();
      return;
    }

    setState(() => _requests[c.key] = _RequestState.requesting);
    final outcome = await _service.request(c);
    if (!mounted) return;
    if (outcome == TonightRequestOutcome.failed) {
      setState(() => _requests[c.key] = _RequestState.failed);
      return;
    }
    await _service.launched(pick, over: _passedOver(pick));
    setState(() => _requests[c.key] = _RequestState.requested);
    _startPolling();
  }

  /// Watches the requested titles until the server has them.
  void _startPolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 15), (_) => _checkReady());
  }

  Future<void> _checkReady() async {
    final waiting = [
      for (final pick in _queue)
        if (_requests[pick.candidate.key] == _RequestState.requested) pick,
    ];
    if (waiting.isEmpty) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    for (final pick in waiting) {
      final found = await _service.findInLibrary(pick.candidate);
      if (found == null || !mounted) continue;
      HapticFeedback.mediumImpact();
      setState(() {
        _readyItems[pick.candidate.key] = found.id;
        _requests[pick.candidate.key] = _RequestState.ready;
      });
    }
  }

  void _details(TonightPick pick) {
    final c = pick.candidate;
    final libraryId = c.libraryItemId;
    if (c.availability == TonightAvailability.inLibrary && libraryId != null) {
      _close(Destinations.item(libraryId, serverId: _serverId));
    } else if (c.tmdbId != null) {
      _close(
        Destinations.seerrMedia(
          '${c.tmdbId}',
          mediaType: c.mediaType,
          title: c.title,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: _phase == _Phase.questions,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _phase = _Phase.questions);
      },
      child: Scaffold(
        backgroundColor: AppColorScheme.background,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _phase == _Phase.questions
                ? _Questions(
                    key: const ValueKey('questions'),
                    answers: _answers,
                    onChanged: (a) => setState(() => _answers = a),
                    onGo: _go,
                  )
                : KeyedSubtree(
                    key: const ValueKey('results'),
                    child: _buildResults(context, l10n),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, AppLocalizations l10n) {
    final onBg = AppColorScheme.onBackground;
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              l10n.tonightLoading,
              style: TextStyle(color: onBg.withValues(alpha: 0.8), fontSize: 16),
            ),
          ],
        ),
      );
    }
    final pick = _current;
    if (_failed || pick == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.tonightNothing,
                textAlign: TextAlign.center,
                style: TextStyle(color: onBg, fontSize: 17),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _ActionButton(
                    label: l10n.tonightChangeAnswers,
                    icon: Icons.tune_rounded,
                    primary: true,
                    autofocus: true,
                    onTap: () => setState(() => _phase = _Phase.questions),
                  ),
                  _ActionButton(
                    label: l10n.tonightRetry,
                    icon: Icons.refresh_rounded,
                    onTap: () => _go(),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final view = _view;
    final others = [
      for (final p in _queue)
        if (p != pick) p,
    ].take(5).toList();
    final layout = _Layout.of(context);

    final hero = _Hero(
      pick: pick,
      answers: _answers,
      layout: layout,
      requestState: _requests[pick.candidate.key],
      ready: _readyItems.containsKey(pick.candidate.key),
      primaryFocus: _primaryFocus,
      onPrimary: () => _primary(pick),
      onAnother: _another,
      onDetails: () => _details(pick),
    );
    final header = <Widget>[
      _Header(
        answers: _answers,
        onChange: () => setState(() => _phase = _Phase.questions),
      ),
      if (view?.stalled case final stalled?)
        _Banner(
          icon: Icons.hourglass_bottom_rounded,
          text: l10n.tonightStalled(stalled.title),
        ),
      if (view?.result.relaxedMood ?? false)
        _Banner(icon: Icons.info_outline_rounded, text: l10n.tonightRelaxed),
    ];
    final othersTitle = Text(
      l10n.tonightOthers,
      style: TextStyle(color: onBg, fontSize: 18, fontWeight: FontWeight.w700),
    );
    final precision = view?.precision == null
        ? null
        : Text(
            l10n.tonightPrecision((view!.precision! * 100).round()),
            style: TextStyle(color: onBg.withValues(alpha: 0.55), fontSize: 12.5),
          );

    final posterWidth = switch (layout) {
      _Layout.wide => 140.0,
      _Layout.compact => 100.0,
      _ => 116.0,
    };
    const gap = 12.0;
    // Opened, the five ideas share the width instead of scrolling sideways.
    final Widget othersRow = layout == _Layout.open
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 5; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Expanded(
                  child: i < others.length
                      ? _PosterCard(
                          pick: others[i],
                          onTap: () => _show(others[i]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          )
        : SizedBox(
            // The poster, its title and the room a focused card grows into.
            height: posterWidth * 1.5 + 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: others.length,
              separatorBuilder: (_, _) => const SizedBox(width: gap),
              itemBuilder: (context, index) => SizedBox(
                width: posterWidth,
                child: _PosterCard(
                  pick: others[index],
                  onTap: () => _show(others[index]),
                ),
              ),
            ),
          );
    return FocusTraversalGroup(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: switch (layout) {
            _Layout.wide => 32,
            _Layout.open => 24,
            _Layout.compact => 12,
            _Layout.phone => 16,
          },
          vertical: layout == _Layout.compact ? 8 : 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...header,
            SizedBox(height: layout == _Layout.compact ? 8 : 12),
            hero,
            if (others.isNotEmpty) ...[
              SizedBox(height: layout == _Layout.compact ? 14 : 22),
              othersTitle,
              const SizedBox(height: 10),
              othersRow,
            ],
            if (precision != null) ...[const SizedBox(height: 18), precision],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// The three questions, preselected with the likeliest answers so the usual
/// evening is one press away.
class _Questions extends StatelessWidget {
  final TonightAnswers answers;
  final ValueChanged<TonightAnswers> onChanged;
  final VoidCallback onGo;

  const _Questions({
    super.key,
    required this.answers,
    required this.onChanged,
    required this.onGo,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onBg = AppColorScheme.onBackground;
    final layout = _Layout.of(context);
    final compact = layout == _Layout.compact;

    Widget section(String title, List<Widget> chips) => Padding(
      padding: EdgeInsets.only(bottom: compact ? 12 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: onBg.withValues(alpha: 0.75),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: chips),
        ],
      ),
    );

    // On a large screen the answers stay in a column a thumb can cover
    // instead of running across the whole width.
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.nights_stay_rounded, color: AppColorScheme.accent),
            const SizedBox(width: 10),
            Text(
              l10n.tonightTitle,
              style: TextStyle(
                color: AppColorScheme.accent,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.close_rounded, color: onBg),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l10n.tonightQuestionsTitle,
          style: TextStyle(
            color: onBg,
            fontSize: switch (layout) {
              _Layout.wide => 30,
              _Layout.open => 28,
              _Layout.compact => 21,
              _Layout.phone => 24,
            },
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.tonightQuestionsHint,
          style: TextStyle(color: onBg.withValues(alpha: 0.7), fontSize: 15),
        ),
        SizedBox(height: compact ? 14 : 22),
        section(l10n.tonightWhoQuestion, [
          for (final company in TonightCompany.values)
            _Choice(
              label: switch (company) {
                TonightCompany.alone => l10n.tonightWhoAlone,
                TonightCompany.couple => l10n.tonightWhoCouple,
                TonightCompany.family => l10n.tonightWhoFamily,
                TonightCompany.friends => l10n.tonightWhoFriends,
              },
              icon: switch (company) {
                TonightCompany.alone => Icons.person_rounded,
                TonightCompany.couple => Icons.favorite_rounded,
                TonightCompany.family => Icons.family_restroom_rounded,
                TonightCompany.friends => Icons.groups_rounded,
              },
              selected: answers.company == company,
              onTap: () => onChanged(answers.copyWith(company: company)),
            ),
        ]),
        if (answers.company == TonightCompany.family)
          section(l10n.tonightKidsQuestion, [
            for (final age in KidsAge.values)
              _Choice(
                label: switch (age) {
                  KidsAge.under7 => l10n.tonightKidsUnder7,
                  KidsAge.from7to12 => l10n.tonightKids7to12,
                  KidsAge.teen => l10n.tonightKidsTeen,
                },
                selected: answers.kidsAge == age,
                onTap: () => onChanged(answers.copyWith(kidsAge: age)),
              ),
          ]),
        section(l10n.tonightTimeQuestion, [
          for (final time in TonightTime.values)
            _Choice(
              label: switch (time) {
                TonightTime.short => l10n.tonightTimeShort,
                TonightTime.evening => l10n.tonightTimeEvening,
                TonightTime.any => l10n.tonightTimeAny,
              },
              icon: switch (time) {
                TonightTime.short => Icons.timer_outlined,
                TonightTime.evening => Icons.weekend_rounded,
                TonightTime.any => Icons.all_inclusive_rounded,
              },
              selected: answers.time == time,
              onTap: () => onChanged(answers.copyWith(time: time)),
            ),
        ]),
        section(l10n.tonightMoodQuestion, [
          for (final mood in TonightMood.values)
            _Choice(
              label: tonightMoodLabel(l10n, mood),
              icon: switch (mood) {
                TonightMood.laugh => Icons.sentiment_very_satisfied_rounded,
                TonightMood.chills => Icons.nightlight_round,
                TonightMood.escape => Icons.rocket_launch_rounded,
                TonightMood.think => Icons.psychology_rounded,
                TonightMood.comfort => Icons.local_cafe_rounded,
                TonightMood.surprise => Icons.casino_rounded,
              },
              selected: answers.mood == mood,
              onTap: () => onChanged(answers.copyWith(mood: mood)),
            ),
        ]),
        const SizedBox(height: 6),
        _ActionButton(
          label: l10n.tonightGo,
          icon: Icons.arrow_forward_rounded,
          primary: true,
          autofocus: true,
          large: true,
          onTap: onGo,
        ),
      ],
    );
    return FocusTraversalGroup(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: switch (layout) {
            _Layout.wide => 48,
            _Layout.open => 32,
            _Layout.compact => 16,
            _Layout.phone => 20,
          },
          vertical: compact ? 12 : 20,
        ),
        child: layout == _Layout.open
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: content,
                ),
              )
            : content,
      ),
    );
  }
}

String tonightMoodLabel(AppLocalizations l10n, TonightMood mood) => switch (mood) {
  TonightMood.laugh => l10n.tonightMoodLaugh,
  TonightMood.chills => l10n.tonightMoodChills,
  TonightMood.escape => l10n.tonightMoodEscape,
  TonightMood.think => l10n.tonightMoodThink,
  TonightMood.comfort => l10n.tonightMoodComfort,
  TonightMood.surprise => l10n.tonightMoodSurprise,
};

class _Header extends StatelessWidget {
  final TonightAnswers answers;
  final VoidCallback onChange;

  const _Header({required this.answers, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onBg = AppColorScheme.onBackground;
    final summary = [
      switch (answers.company) {
        TonightCompany.alone => l10n.tonightWhoAlone,
        TonightCompany.couple => l10n.tonightWhoCouple,
        TonightCompany.family => l10n.tonightWhoFamily,
        TonightCompany.friends => l10n.tonightWhoFriends,
      },
      switch (answers.time) {
        TonightTime.short => l10n.tonightTimeShort,
        TonightTime.evening => l10n.tonightTimeEvening,
        TonightTime.any => l10n.tonightTimeAny,
      },
      tonightMoodLabel(l10n, answers.mood),
    ].join('  ·  ');
    return Row(
      children: [
        Icon(Icons.nights_stay_rounded, color: AppColorScheme.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.tonightTitle,
                style: TextStyle(
                  color: onBg,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: onBg.withValues(alpha: 0.65)),
              ),
            ],
          ),
        ),
        _ActionButton(
          label: l10n.tonightChangeAnswers,
          icon: Icons.tune_rounded,
          compact: true,
          onTap: onChange,
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Banner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final onBg = AppColorScheme.onBackground;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: onBg.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColorScheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: onBg, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

/// The main suggestion: big picture, why it was picked, and what to do.
class _Hero extends StatelessWidget {
  final TonightPick pick;
  final TonightAnswers answers;
  final _Layout layout;
  final _RequestState? requestState;
  final bool ready;
  final FocusNode primaryFocus;
  final VoidCallback onPrimary;
  final VoidCallback onAnother;
  final VoidCallback onDetails;

  const _Hero({
    required this.pick,
    required this.answers,
    required this.layout,
    required this.requestState,
    required this.ready,
    required this.primaryFocus,
    required this.onPrimary,
    required this.onAnother,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onBg = AppColorScheme.onBackground;
    final c = pick.candidate;
    final image = c.backdropUrl ?? c.posterUrl;
    final wide = layout == _Layout.wide;
    final compact = layout == _Layout.compact;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _Pill(
              icon: switch (c.availability) {
                TonightAvailability.inLibrary => Icons.check_circle_rounded,
                TonightAvailability.requested => Icons.schedule_rounded,
                TonightAvailability.requestable => Icons.bolt_rounded,
              },
              label: switch (c.availability) {
                TonightAvailability.inLibrary => l10n.tonightInLibrary,
                TonightAvailability.requested => l10n.tonightAlreadyRequested,
                TonightAvailability.requestable => l10n.tonightRequestable,
              },
            ),
            if (pick.isJoker) ...[
              const SizedBox(width: 8),
              _Pill(icon: Icons.casino_rounded, label: l10n.tonightJoker),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          c.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: switch (layout) {
              _Layout.wide => 36,
              _Layout.open => 32,
              _Layout.compact => 22,
              _Layout.phone => 26,
            },
            fontWeight: FontWeight.w900,
            height: 1.1,
            shadows: const [Shadow(blurRadius: 12, color: Colors.black54)],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _meta(context, l10n, c),
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: AppColorScheme.accent,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tonightReasonText(context, l10n, pick, answers),
                style: TextStyle(
                  color: AppColorScheme.accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if ((c.overview ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            c.overview!,
            maxLines: compact ? 3 : (wide ? 4 : 5),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ActionButton(
              label: _primaryLabel(l10n, c),
              icon: _primaryIcon(c),
              primary: true,
              focusNode: primaryFocus,
              autofocus: true,
              busy:
                  requestState == _RequestState.requesting ||
                  (requestState == _RequestState.requested && !ready),
              onTap: onPrimary,
            ),
            _ActionButton(
              label: l10n.tonightAnother,
              icon: Icons.shuffle_rounded,
              onTap: onAnother,
            ),
            _ActionButton(
              label: l10n.tonightDetails,
              icon: Icons.info_outline_rounded,
              onTap: onDetails,
            ),
          ],
        ),
        if (requestState == _RequestState.requested && !ready) ...[
          const SizedBox(height: 10),
          Text(
            l10n.tonightRequested,
            style: TextStyle(color: onBg.withValues(alpha: 0.85)),
          ),
        ],
        if (requestState == _RequestState.failed) ...[
          const SizedBox(height: 10),
          Text(
            l10n.tonightRequestFailed,
            style: const TextStyle(color: Color(0xFFFF8A80)),
          ),
        ],
      ],
    );

    final picture = image == null
        ? Container(color: onBg.withValues(alpha: 0.08))
        : BoundedNetworkImage(
            key: ValueKey(image),
            imageUrl: image,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            fadeInDuration: const Duration(milliseconds: 250),
            maxWidth: 1600,
            errorBuilder: (_, _, _) =>
                Container(color: onBg.withValues(alpha: 0.08)),
          );

    if (wide) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 430,
          child: Stack(
            fit: StackFit.expand,
            children: [
              picture,
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xF2000000), Color(0x99000000), Color(0x00000000)],
                    stops: [0, 0.55, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(28),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.6,
                    child: details,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Positioned.fill(child: picture),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0xCC000000), Color(0xF5000000)],
                  stops: [0, 0.35, 0.7],
                ),
              ),
            ),
          ),
          Padding(
            // The room above the details is the picture you see.
            padding: switch (layout) {
              _Layout.compact => const EdgeInsets.fromLTRB(14, 72, 14, 14),
              _Layout.open => const EdgeInsets.fromLTRB(24, 240, 24, 22),
              _ => const EdgeInsets.fromLTRB(18, 120, 18, 18),
            },
            child: details,
          ),
        ],
      ),
    );
  }

  String _primaryLabel(AppLocalizations l10n, TonightCandidate c) {
    if (ready) return l10n.tonightReady;
    switch (requestState) {
      case _RequestState.requesting:
        return l10n.tonightRequesting;
      case _RequestState.requested:
        return l10n.tonightAlreadyRequested;
      default:
        break;
    }
    if (c.inProgress) return l10n.tonightResume(c.nextEpisodeLabel ?? '');
    return switch (c.availability) {
      TonightAvailability.inLibrary => l10n.tonightPlay,
      TonightAvailability.requested => l10n.tonightAlreadyRequested,
      TonightAvailability.requestable => l10n.tonightRequest,
    };
  }

  IconData _primaryIcon(TonightCandidate c) {
    if (ready || c.availability == TonightAvailability.inLibrary) {
      return Icons.play_arrow_rounded;
    }
    return Icons.download_rounded;
  }

  static String _meta(
    BuildContext context,
    AppLocalizations l10n,
    TonightCandidate c,
  ) {
    final parts = <String>[
      if (c.year != null) '${c.year}',
      if (c.runtimeMinutes case final minutes? when minutes > 0)
        c.isMovie ? tonightRuntimeText(l10n, minutes) : l10n.tonightEpisodes(minutes),
      if (c.rating case final rating? when rating > 0)
        '★ ${tonightRatingText(context, rating)}',
      for (final genre in c.genres.take(2)) tasteGenreLabel(l10n, genre),
    ];
    return parts.join('  ·  ');
  }
}

String tonightRuntimeText(AppLocalizations l10n, int minutes) {
  if (minutes < 60) return l10n.tonightRuntimeM(minutes);
  final rest = minutes % 60;
  return l10n.tonightRuntimeHM(minutes ~/ 60, rest.toString().padLeft(2, '0'));
}

String tonightRatingText(BuildContext context, double rating) {
  final text = rating.toStringAsFixed(1);
  return Localizations.localeOf(context).languageCode == 'en'
      ? text
      : text.replaceAll('.', ',');
}

/// The line that says why a pick was made.
String tonightReasonText(
  BuildContext context,
  AppLocalizations l10n,
  TonightPick pick,
  TonightAnswers answers,
) {
  final reason = pick.reason;
  switch (reason.kind) {
    case TonightReasonKind.resume:
      return l10n.tonightReasonResume;
    case TonightReasonKind.because:
      final title = reason.seedTitle;
      return title == null || title.isEmpty
          ? l10n.tonightReasonMood
          : l10n.tonightReasonBecause(title);
    case TonightReasonKind.habit:
      final slot = reason.slot;
      return slot == null
          ? l10n.tonightReasonMood
          : l10n.tonightReasonHabit(tonightSlotLabel(l10n, slot));
    case TonightReasonKind.mood:
      return l10n.tonightReasonMood;
    case TonightReasonKind.company:
      return switch (answers.company) {
        TonightCompany.family => l10n.tonightReasonFamily,
        TonightCompany.couple => l10n.tonightReasonCouple,
        TonightCompany.friends => l10n.tonightReasonFriends,
        TonightCompany.alone => l10n.tonightReasonMood,
      };
    case TonightReasonKind.quality:
      final rating = pick.candidate.rating;
      return rating == null
          ? l10n.tonightReasonMood
          : l10n.tonightReasonQuality(tonightRatingText(context, rating));
    case TonightReasonKind.fresh:
      return l10n.tonightReasonFresh;
    case TonightReasonKind.taste:
      final genre = reason.genre;
      return genre == null
          ? l10n.tonightReasonMood
          : l10n.tonightReasonTaste(tasteGenreLabel(l10n, genre).toLowerCase());
    case TonightReasonKind.joker:
      return l10n.tonightReasonJoker;
  }
}

String tonightSlotLabel(AppLocalizations l10n, TonightSlot slot) {
  final day = slot.band == DayBand.daytime;
  return switch (slot.day) {
    DayKind.weekday => switch (slot.band) {
      DayBand.daytime => l10n.tonightSlotWeekdayDay,
      DayBand.evening => l10n.tonightSlotWeekdayEvening,
      DayBand.late => l10n.tonightSlotWeekdayLate,
    },
    DayKind.friday => day ? l10n.tonightSlotWeekdayDay : l10n.tonightSlotFriday,
    DayKind.saturday =>
      day ? l10n.tonightSlotWeekendDay : l10n.tonightSlotSaturday,
    DayKind.sunday => day ? l10n.tonightSlotWeekendDay : l10n.tonightSlotSunday,
  };
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A button that shows clearly when the remote is on it.
class _ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  final bool autofocus;
  final bool compact;
  final bool large;
  final bool busy;
  final FocusNode? focusNode;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.autofocus = false,
    this.compact = false,
    this.large = false,
    this.busy = false,
    this.focusNode,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppColorScheme.accent;
    final onBg = AppColorScheme.onBackground;
    final fill = widget.primary
        ? accent
        : (_focused ? onBg.withValues(alpha: 0.22) : onBg.withValues(alpha: 0.1));
    final text = widget.primary ? AppColorScheme.onAccent : onBg;
    final padding = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
        : widget.large
        ? const EdgeInsets.symmetric(horizontal: 28, vertical: 16)
        : const EdgeInsets.symmetric(horizontal: 20, vertical: 13);
    return AnimatedScale(
      scale: _focused ? 1.05 : 1,
      duration: const Duration(milliseconds: 120),
      child: InkWell(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        borderRadius: BorderRadius.circular(30),
        onFocusChange: (f) => setState(() => _focused = f),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: _focused ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: text),
                )
              else
                Icon(widget.icon, size: widget.large ? 24 : 20, color: text),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: text,
                  fontSize: widget.large ? 18 : (widget.compact ? 13.5 : 15.5),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  State<_Choice> createState() => _ChoiceState();
}

class _ChoiceState extends State<_Choice> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onBg = AppColorScheme.onBackground;
    final accent = AppColorScheme.accent;
    final selected = widget.selected;
    final text = selected ? AppColorScheme.onAccent : onBg;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onFocusChange: (f) => setState(() => _focused = f),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? accent : onBg.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _focused ? onBg : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 19, color: text),
              const SizedBox(width: 7),
            ],
            Text(
              widget.label,
              style: TextStyle(
                color: text,
                fontSize: 15.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A poster as wide as the room it is given, its title under it.
class _PosterCard extends StatefulWidget {
  final TonightPick pick;
  final VoidCallback onTap;

  const _PosterCard({required this.pick, required this.onTap});

  @override
  State<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<_PosterCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = widget.pick.candidate;
    final url = c.posterUrl;
    final onBg = AppColorScheme.onBackground;
    final fallback = Container(
      color: onBg.withValues(alpha: 0.08),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        c.title,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: onBg.withValues(alpha: 0.8), fontSize: 12),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedScale(
          scale: _focused ? 1.06 : 1,
          duration: const Duration(milliseconds: 120),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onFocusChange: (f) => setState(() => _focused = f),
            onTap: widget.onTap,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _focused ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (url == null)
                        fallback
                      else
                        BoundedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          maxWidth: 400,
                          errorBuilder: (_, _, _) => fallback,
                        ),
                      if (widget.pick.isJoker ||
                          c.availability != TonightAvailability.inLibrary)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Icon(
                            widget.pick.isJoker
                                ? Icons.casino_rounded
                                : Icons.bolt_rounded,
                            size: 18,
                            color: Colors.white,
                            shadows: const [
                              Shadow(blurRadius: 6, color: Colors.black),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.pick.isJoker ? l10n.tonightJoker : c.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: onBg.withValues(alpha: 0.85),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
