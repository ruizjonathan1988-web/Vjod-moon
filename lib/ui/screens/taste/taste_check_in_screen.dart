import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/repositories/seerr_repository.dart';
import '../../../data/services/seerr/for_you_service.dart';
import '../../../data/services/seerr/taste_check_in.dart';
import '../../../data/services/seerr/taste_profile.dart';
import '../../../data/services/seerr/taste_quiz.dart';
import '../../../data/services/seerr/taste_quiz_loader.dart';
import '../../../data/services/tonight/evening_journal.dart';
import '../../../data/services/tonight/tonight_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../layout/screen_form.dart';
import '../../../preference/seerr_preferences.dart';
import '../../widgets/seerr/seerr_image_urls.dart';
import 'taste_questionnaire_screen.dart';

/// Opens the monthly check-in: a few cards drawn from what the viewer
/// actually watched. Returns true once the taste profile changed.
Future<bool> openTasteCheckIn(BuildContext context) async {
  final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const TasteCheckInScreen(),
    ),
  );
  return saved == true;
}

sealed class _Card {
  const _Card();
}

class _FinishedCard extends _Card {
  final JournalEntry entry;
  const _FinishedCard(this.entry);
}

class _DroppedCard extends _Card {
  final JournalEntry entry;
  const _DroppedCard(this.entry);
}

class _DuelCard extends _Card {
  final QuizDuel duel;
  const _DuelCard(this.duel);
}

class _StillTrueCard extends _Card {
  final StillTrue question;
  const _StillTrueCard(this.question);
}

/// A minute a month to keep suggestions on track: a verdict on the last
/// title watched through, why the last one was dropped, one duel on the
/// least known axis of taste, and whether an old limit still holds.
class TasteCheckInScreen extends StatefulWidget {
  const TasteCheckInScreen({super.key});

  @override
  State<TasteCheckInScreen> createState() => _TasteCheckInScreenState();
}

class _TasteCheckInScreenState extends State<TasteCheckInScreen> {
  final _prefs = GetIt.instance<SeerrPreferences>();
  late TasteProfile _profile;
  final List<_Card> _cards = [];
  final List<String> _asked = [];
  int _index = 0;
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _profile = TasteProfile.decode(_prefs.tasteProfileJson);
    _build();
  }

  Future<void> _build() async {
    final journal = TonightService.instance.journal.entries;
    final sittings = checkInSittings(
      journal: journal,
      profile: _profile,
      asked: _prefs.tasteCheckInAsked.toSet(),
    );
    final cards = <_Card>[
      if (sittings.finished case final e?) _FinishedCard(e),
      if (sittings.dropped case final e?) _DroppedCard(e),
    ];

    // One duel on the axis known least.
    final axis = [
      for (final a in TasteAxis.values)
        if (!_profile.axes.containsKey(a)) a,
    ].firstOrNull;
    if (axis != null) {
      try {
        final repo = await GetIt.instance.getAsync<SeerrRepository>();
        await repo.ensureInitialized();
        final pool = await loadQuizPool(repo);
        final duel = buildDuel(
          axis,
          pool: pool,
          used: _profile.seenKeys,
          avoided: _profile.avoided,
        );
        if (duel != null) cards.add(_DuelCard(duel));
      } catch (e) {
        debugPrint('[Taste] Check-in duel failed: $e');
      }
    }

    if (stillTrueQuestion(_profile) case final q?) cards.add(_StillTrueCard(q));

    if (!mounted) return;
    setState(() {
      _cards.addAll(cards);
      _loading = false;
    });
  }

  Future<void> _answer(TasteProfile next, {JournalEntry? asked}) async {
    HapticFeedback.selectionClick();
    if (asked != null) _asked.add(checkInKey(asked));
    setState(() {
      if (!identical(next, _profile)) _changed = true;
      _profile = next;
      _index++;
    });
    if (_index >= _cards.length) await _save();
  }

  void _skip() {
    final card = _cards[_index];
    if (card case _FinishedCard(:final entry) || _DroppedCard(:final entry)) {
      _asked.add(checkInKey(entry));
    }
    setState(() => _index++);
    if (_index >= _cards.length) _save();
  }

  Future<void> _save() async {
    final asked = [..._prefs.tasteCheckInAsked, ..._asked];
    await _prefs.setTasteCheckInAsked(
      asked.length > 200 ? asked.sublist(asked.length - 200) : asked,
    );
    await _prefs.setTastePromptedAt(DateTime.now().millisecondsSinceEpoch);
    if (_changed) {
      await _prefs.setTasteProfileJson(
        _profile.copyWith(updatedAt: DateTime.now()).encode(),
      );
      ForYouService.instance.clearCache();
    }
    if (mounted) Navigator.of(context).pop(_changed);
  }

  Future<void> _openFull() async {
    final navigator = Navigator.of(context);
    final saved = await openTasteQuestionnaire(context);
    if (saved) {
      navigator.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onBg = AppColorScheme.onBackground;
    final compact = ScreenForm.of(context) == ScreenForm.cover;
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: SafeArea(
        child: Padding(
          padding: compact
              ? const EdgeInsets.fromLTRB(16, 10, 16, 10)
              : const EdgeInsets.fromLTRB(24, 16, 24, 14),
          // One card at a time reads best at a phone's width, even opened.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_repeat_rounded, color: AppColorScheme.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.checkInTitle,
                          style: TextStyle(
                            color: onBg,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!_loading && _cards.isNotEmpty)
                        Text(
                          l10n.tasteStepOf(
                            (_index + 1).clamp(1, _cards.length),
                            _cards.length,
                          ),
                          style: TextStyle(
                            color: onBg.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _index >= _cards.length
                        ? _empty(l10n)
                        : FocusTraversalGroup(
                            key: ValueKey(_index),
                            child: _buildCard(l10n, _cards[_index]),
                          ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(l10n.tasteLater),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _openFull,
                        child: Text(l10n.checkInFull),
                      ),
                      if (!_loading && _index < _cards.length) ...[
                        const SizedBox(width: 8),
                        TextButton(onPressed: _skip, child: Text(l10n.quizSkip)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(AppLocalizations l10n) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.checkInNothing,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColorScheme.onBackground, fontSize: 16),
        ),
        const SizedBox(height: 14),
        _Option(
          label: l10n.checkInFull,
          autofocus: true,
          onTap: _openFull,
        ),
      ],
    ),
  );

  Widget _buildCard(AppLocalizations l10n, _Card card) {
    switch (card) {
      case _FinishedCard(:final entry):
        return _question(
          l10n.checkInFinished(entry.title),
          [
            for (final (i, v) in CheckInVerdict.values.indexed)
              _Option(
                label: switch (v) {
                  CheckInVerdict.loved => l10n.checkInLoved,
                  CheckInVerdict.good => l10n.checkInGood,
                  CheckInVerdict.meh => l10n.checkInMeh,
                  CheckInVerdict.disliked => l10n.checkInDisliked,
                },
                autofocus: i == 0,
                onTap: () =>
                    _answer(applyVerdict(_profile, entry, v), asked: entry),
              ),
          ],
        );
      case _DroppedCard(:final entry):
        return _question(
          l10n.checkInDropped(entry.title, entry.watchedMinutes),
          [
            for (final (i, r) in DropReason.values.indexed)
              _Option(
                label: switch (r) {
                  DropReason.notNow => l10n.checkInNotNow,
                  DropReason.tooSlow => l10n.checkInTooSlow,
                  DropReason.tooDark => l10n.checkInTooDark,
                  DropReason.notMyGenre => l10n.checkInNotMyGenre,
                  DropReason.later => l10n.checkInLater,
                },
                autofocus: i == 0,
                onTap: () => _answer(
                  applyDropReason(_profile, entry, r),
                  asked: entry,
                ),
              ),
          ],
        );
      case _DuelCard(:final duel):
        void pick(double value) {
          final axes = {..._profile.axes, duel.axis: value};
          _answer(_profile.copyWith(axes: axes));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title(l10n.quizDuelsTitle),
            const SizedBox(height: 14),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _Poster(
                      title: duel.left,
                      autofocus: true,
                      onTap: () => pick(-1),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _Poster(title: duel.right, onTap: () => pick(1)),
                  ),
                ],
              ),
            ),
          ],
        );
      case _StillTrueCard(:final question):
        final text = switch (question) {
          StillAvoided(:final genre) => l10n.checkInStillAvoided(
            tasteGenreLabel(l10n, genre).toLowerCase(),
          ),
          StillNoSubtitles() => l10n.checkInStillNoSubtitles,
          StillNoViolence() => l10n.checkInStillNoViolence,
        };
        return _question(text, [
          _Option(
            label: l10n.checkInYes,
            autofocus: true,
            onTap: () => _answer(_profile),
          ),
          _Option(
            label: l10n.checkInNotAnymore,
            onTap: () => _answer(releaseChoice(_profile, question)),
          ),
        ]);
    }
  }

  Widget _title(String text) => Text(
    text,
    style: TextStyle(
      color: AppColorScheme.onBackground,
      fontSize: 24,
      fontWeight: FontWeight.w800,
      height: 1.2,
    ),
  );

  Widget _question(String text, List<Widget> options) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(text),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, children: options),
      ],
    ),
  );
}

class _Option extends StatefulWidget {
  final String label;
  final bool autofocus;
  final VoidCallback onTap;

  const _Option({
    required this.label,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_Option> createState() => _OptionState();
}

class _OptionState extends State<_Option> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onBg = AppColorScheme.onBackground;
    return InkWell(
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(24),
      onFocusChange: (f) => setState(() => _focused = f),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: _focused
              ? AppColorScheme.accent
              : onBg.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _focused ? onBg : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: _focused ? AppColorScheme.onAccent : onBg,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Poster extends StatefulWidget {
  final QuizTitle title;
  final bool autofocus;
  final VoidCallback onTap;

  const _Poster({
    required this.title,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  State<_Poster> createState() => _PosterState();
}

class _PosterState extends State<_Poster> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onBg = AppColorScheme.onBackground;
    final t = widget.title;
    final poster = t.posterPath;
    return InkWell(
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(14),
      onFocusChange: (f) => setState(() => _focused = f),
      onTap: widget.onTap,
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
                    color: _focused ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: poster == null
                      ? Container(color: onBg.withValues(alpha: 0.08))
                      : Image.network(
                          '$seerrPosterBase$poster',
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
            style: TextStyle(color: onBg, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
