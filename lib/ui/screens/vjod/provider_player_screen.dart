// The player of the films and episodes read from the IPTV provider (through
// Ma TV, which picks the best source and switches to the next if one fails).
// Unlike the trailer player it used to borrow, it waits long enough for the
// seedbox to find a source that answers, and it has what a film needs: the
// audio language, subtitles with their size, place and delay, seeking, and
// the remote's keys (OK shows the controls, LEFT / RIGHT seek, PLAY/PAUSE,
// BACK hides the controls then leaves). The picture comes from ExoPlayer, the
// engine of TiviMate, with mpv as the fallback (see vod_engine.dart).
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/seerr/taste_profile.dart';
import '../../../data/services/vjod/iptv_learning.dart';
import '../../../data/services/vjod/iptv_next.dart';
import '../../../data/services/vjod/iptv_progress.dart';
import '../../../data/services/vjod/provider_catalog_access.dart';
import '../../../data/services/vjod/vjod_votes.dart';
import '../../../preference/seerr_preferences.dart';
import '../../../data/services/vjod/xtream_catalog.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/system_ui.dart';
import '../../navigation/destinations.dart';
import '../../screensaver/screensaver_controller.dart';
import '../vjod_tv/tv_engine.dart' show TvEngineChoice;
import 'vod_engine.dart';

/// Where each film was left, for this run of the app, so leaving by mistake
/// and coming back picks up there.
final Map<String, Duration> _resumeAt = {};

/// The language of an audio or subtitle track, in French, from its code
/// (`fre`, `fra`, `fr`, `eng`…) or its title. Empty when nothing says.
String trackLanguageName(String? language, String? title) {
  const names = {
    'fr': 'Français', 'fre': 'Français', 'fra': 'Français',
    'en': 'Anglais', 'eng': 'Anglais',
    'ru': 'Russe', 'rus': 'Russe',
    'zh': 'Chinois', 'chi': 'Chinois', 'zho': 'Chinois',
    'de': 'Allemand', 'ger': 'Allemand', 'deu': 'Allemand',
    'es': 'Espagnol', 'spa': 'Espagnol',
    'it': 'Italien', 'ita': 'Italien',
    'pt': 'Portugais', 'por': 'Portugais',
    'ar': 'Arabe', 'ara': 'Arabe',
    'tr': 'Turc', 'tur': 'Turc',
    'ja': 'Japonais', 'jpn': 'Japonais',
    'ko': 'Coréen', 'kor': 'Coréen',
    'nl': 'Néerlandais', 'dut': 'Néerlandais', 'nld': 'Néerlandais',
    'pl': 'Polonais', 'pol': 'Polonais',
    'uk': 'Ukrainien', 'ukr': 'Ukrainien',
  };
  final code = (language ?? '').trim().toLowerCase();
  final name = names[code] ?? (code.isEmpty ? '' : code.toUpperCase());
  final t = (title ?? '').trim();
  if (name.isEmpty) return t;
  if (t.isEmpty || t.toLowerCase() == code) return name;
  return '$name · $t';
}

/// The codes a provider tag (`FR`, `EN`, `RU`, `CN`…) stands for in tracks.
List<String> trackCodesOfTag(String tag) => switch (tag.toUpperCase()) {
  'FR' || 'VF' || 'VFF' || 'VFQ' => const ['fr', 'fre', 'fra'],
  'EN' || 'UK' || 'US' => const ['en', 'eng'],
  'RU' => const ['ru', 'rus'],
  'CN' || 'ZH' => const ['zh', 'chi', 'zho'],
  'DE' => const ['de', 'ger', 'deu'],
  'ES' => const ['es', 'spa'],
  'IT' => const ['it', 'ita'],
  'AR' => const ['ar', 'ara'],
  _ => const [],
};

class ProviderPlayerScreen extends StatefulWidget {
  final String url;
  final String title;

  /// What is playing, to save its place on Ma TV (resume, on any device) and
  /// to learn from it. Null for a playback that keeps nothing.
  final IptvWatch? watch;

  const ProviderPlayerScreen({super.key, required this.url, this.title = '', this.watch});

  @override
  State<ProviderPlayerScreen> createState() => _ProviderPlayerScreenState();
}

class _ProviderPlayerScreenState extends State<ProviderPlayerScreen>
    with ImmersiveSystemUi {
  // Ma TV may try several sources before one answers.
  static const _openTimeout = Duration(seconds: 60);
  static const _subSizes = [('Petit', 0.75), ('Moyen', 1.0), ('Grand', 1.3), ('Très grand', 1.6)];

  late VodEngine _engine;
  final _focus = FocusNode(debugLabel: 'provider_player');
  final _playFocus = FocusNode(debugLabel: 'provider_player_play');
  final _barFocus = FocusNode(debugLabel: 'provider_player_bar');

  // Moving along the progress bar with the remote: the arrows move a target
  // (10 s a press, faster when held), the jump happens once they stop.
  Duration? _scrubTo;
  Timer? _scrubTimer;
  int _scrubHeld = 0;
  final _subs = <StreamSubscription<Object?>>[];
  final _session =
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(1 << 30).toRadixString(36)}';

  bool _loading = true;
  String? _error;
  bool _controls = false;
  Timer? _hideTimer;
  Timer? _noPicture;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _picture = false;
  bool _picked = false;
  bool _exoRetried = false;
  double _subScale = 1.0;
  bool _subRaised = false;
  double _subDelay = 0;
  int _openSeq = 0;

  // Resume and learning.
  final DateTime _startedAt = DateTime.now();
  Duration _watched = Duration.zero;
  Duration _lastPos = Duration.zero;
  Timer? _saveTimer;
  bool _askedServer = false;

  /// Where the film picked up, for « Depuis le début ».
  Duration? _resumedFrom;

  // « J'ai aimé / Bof », asked once during a film's credits.
  bool _voteVisible = false;
  bool _voteAsked = false;
  Timer? _voteTimer;

  // The episode after this one (series only), offered in the last seconds.
  XtreamEpisode? _nextEp;
  bool _nextVisible = false;
  bool _nextDismissed = false;
  bool _leaving = false;
  int _nextCount = 10;
  Timer? _nextTimer;
  final _nextFocus = FocusNode(debugLabel: 'provider_player_next');

  // « Passer le générique »: how far it jumps for this series, and the last
  // jump, so a correction just after it is learned.
  Duration _introLen = IptvIntroSkip.defaultLength;
  Duration? _skipFrom;
  DateTime? _skipAt;

  bool get _exoWanted => TvEngineChoice.exoAvailable && TvEngineChoice.value != 'mpv';

  @override
  void initState() {
    super.initState();
    setImmersive(true);
    GetIt.instance<ScreensaverController>().setPlaybackActive(true);
    _engine = kIsWeb ? WebVodEngine() : (_exoWanted ? ExoVodEngine() : MpvVodEngine());
    _listen();
    unawaited(_open());
    if (widget.watch != null) {
      _saveTimer = Timer.periodic(const Duration(seconds: 30), (_) => _savePlace());
    }
    if (widget.watch?.isSeries ?? false) {
      unawaited(_findNext());
      unawaited(IptvIntroSkip.lengthFor(widget.watch!.id).then((d) => _introLen = d));
    }
  }

  /// Looks up, in the background, the episode that follows this one.
  Future<void> _findNext() async {
    final w = widget.watch;
    final catalog = currentProviderCatalog();
    if (w == null || catalog == null) return;
    try {
      final info = await catalog.seriesInfo(w.id).timeout(const Duration(seconds: 30));
      final next = episodeAfter(info, season: w.season, number: w.episode, id: w.ep);
      if (mounted) _nextEp = next;
    } catch (_) {}
  }

  /// In the last 40 seconds of an episode: « Épisode suivant » with a
  /// 10-second countdown (OK plays it now, BACK or « Annuler » stays).
  void _checkNext() {
    if (_nextEp == null || _nextDismissed || _nextVisible || _leaving) return;
    if (_dur < const Duration(minutes: 5)) return;
    final remaining = _dur - _pos;
    if (remaining > const Duration(seconds: 40) || remaining <= Duration.zero) return;
    setState(() {
      _nextVisible = true;
      _nextCount = 10;
    });
    _nextTimer?.cancel();
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
      } else if (_nextCount <= 1) {
        t.cancel();
        _goNext();
      } else {
        setState(() => _nextCount--);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _nextVisible) _nextFocus.requestFocus();
    });
  }

  void _dismissNext() {
    _nextTimer?.cancel();
    setState(() {
      _nextVisible = false;
      _nextDismissed = true;
    });
    _focus.requestFocus();
  }

  void _goNext() {
    final w = widget.watch;
    final ep = _nextEp;
    final catalog = currentProviderCatalog();
    if (w == null || ep == null || catalog == null || _leaving) return;
    _leaving = true;
    _nextTimer?.cancel();
    context.pushReplacement(
      Destinations.providerPlayer(
        url: catalog.episodeUrl(ep),
        title: '${w.name} · S${ep.season} É${ep.number}',
        watch: IptvWatch(
          kind: 'series',
          id: w.id,
          name: w.name,
          tmdb: w.tmdb,
          poster: w.poster,
          ep: ep.id,
          ext: ep.extension,
          season: ep.season,
          episode: ep.number,
          epName: ep.title,
        ),
      ),
    );
  }

  /// « Passer le générique »: shown in an episode's first 6 minutes.
  bool get _canSkipIntro =>
      (widget.watch?.isSeries ?? false) && _skipFrom == null &&
      _pos > const Duration(seconds: 2) && _pos < const Duration(minutes: 6);

  void _skipIntro() {
    final from = _pos;
    setState(() {
      _skipFrom = from;
      _skipAt = DateTime.now();
    });
    unawaited(_engine.seek(from + _introLen));
  }

  /// A seek by hand just after « Passer le générique »: the jump was too short
  /// or too long, the length it should have had is kept for this series.
  void _learnIntro(Duration landed) {
    final from = _skipFrom, at = _skipAt, w = widget.watch;
    if (from == null || at == null || w == null) return;
    if (DateTime.now().difference(at) > const Duration(seconds: 25)) return;
    final len = IptvIntroSkip.corrected(from, landed);
    if (len == null) return;
    _introLen = len;
    unawaited(IptvIntroSkip.remember(w.id, len));
  }

  /// Saves where this playback stands, on Ma TV, for this profile.
  void _savePlace() {
    final w = widget.watch;
    if (w == null || _dur <= Duration.zero || _pos < const Duration(seconds: 30)) return;
    unawaited(IptvProgressStore.save(w, _pos, _dur));
  }

  /// The place saved on Ma TV, asked once before the first open: a film or
  /// the same episode left halfway picks up there.
  Future<Duration?> _savedPlace() async {
    final w = widget.watch;
    if (w == null || _askedServer) return null;
    _askedServer = true;
    final p = await IptvProgressStore.get(w.kind, w.id, tmdb: w.tmdb).timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );
    if (p == null || !p.resumable) return null;
    if (w.isSeries && !p.isEpisode(w.ep, w.season, w.episode)) return null;
    return p.position;
  }

  void _listen() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    final e = _engine;
    _subs.addAll([
      e.position.listen((p) {
        // Time really played: small steps forward, not seeks.
        final step = p - _lastPos;
        if (_playing && step > Duration.zero && step < const Duration(seconds: 5)) _watched += step;
        _lastPos = p;
        _pos = p;
        if (_dur > Duration.zero && p > Duration.zero) _resumeAt[widget.url] = p;
        _checkVote();
        if (mounted) _checkNext();
        if (_controls && mounted) setState(() {});
      }),
      e.duration.listen((d) {
        if (mounted) setState(() => _dur = d);
      }),
      e.playing.listen((p) {
        if (mounted) setState(() => _playing = p);
      }),
      e.buffering.listen((b) {
        if (mounted) setState(() => _buffering = b);
      }),
      e.firstFrame.listen((_) {
        _picture = true;
        _noPicture?.cancel();
        if (mounted) setState(() => _loading = false);
        // Picked up where it was left: the controls show « Depuis le début ».
        if (mounted && _resumedFrom != null) _showControls();
      }),
      e.tracksChanged.listen((_) {
        if (!mounted) return;
        setState(() {});
        _pickLanguages();
      }),
      e.errors.listen((msg) {
        if (!mounted || _picture) return;
        if (_fallBack()) return;
        setState(() => _error = 'Lecture impossible : $msg');
      }),
    ]);
  }

  Future<void> _open() async {
    final seq = ++_openSeq;
    _picture = false;
    _noPicture?.cancel();
    // ExoPlayer that shows nothing for a long while hands over to mpv; mpv
    // itself gets the full minute Ma TV may need to find a source.
    _noPicture = Timer(_engine is ExoVodEngine ? const Duration(seconds: 25) : _openTimeout, () {
      if (!mounted || seq != _openSeq || _picture) return;
      if (_fallBack()) return;
      setState(() => _error = 'Aucune source n\'a répondu à temps. Réessaie dans un moment.');
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || seq != _openSeq) return;
    var from = _resumeAt[widget.url];
    if (from == null) {
      final saved = await _savedPlace();
      if (!mounted || seq != _openSeq) return;
      if (saved != null) {
        from = saved;
        _resumeAt[widget.url] = saved;
        _resumedFrom = saved;
      }
    }
    try {
      // Each playback carries its own number, so Ma TV tells two devices
      // behind the same box apart: one seeking never cuts the other's film.
      await _engine
          .open(
            widget.url,
            {'X-VJOD-Session': _session},
            start: from != null && from > const Duration(minutes: 1)
                ? from - const Duration(seconds: 5)
                : Duration.zero,
          )
          .timeout(_openTimeout);
      unawaited(_engine.styleSubtitles(scale: _subScale, raised: _subRaised));
      if (mounted && _engine is! ExoVodEngine) setState(() => _loading = false);
    } catch (e) {
      if (!mounted || seq != _openSeq) return;
      if (_fallBack()) return;
      setState(() => _error = e is TimeoutException
          ? 'Aucune source n\'a répondu à temps. Réessaie dans un moment.'
          : 'Lecture impossible : $e');
    }
  }

  /// ExoPlayer brought no picture: once more (Ma TV may still be looking for
  /// a source), then mpv. False when already on mpv.
  bool _fallBack() {
    if (_engine is! ExoVodEngine) return false;
    if (!_exoRetried) {
      _exoRetried = true;
      unawaited(_open());
      return true;
    }
    unawaited(_switchEngine(MpvVodEngine()));
    return true;
  }

  Future<void> _switchEngine(VodEngine next) async {
    final old = _engine;
    final at = _pos;
    if (at > const Duration(minutes: 1)) _resumeAt[widget.url] = at;
    setState(() {
      _engine = next;
      _error = null;
      _loading = true;
      _picked = false;
    });
    _listen();
    unawaited(old.dispose());
    await _open();
  }

  /// Once the tracks are known, the profile's language: its audio when the
  /// file has it, else its subtitles over the original sound.
  void _pickLanguages() {
    if (_picked) return;
    final audios = _engine.audio;
    if (audios.isEmpty) return;
    _picked = true;
    final wanted = [for (final t in currentProviderLanguages()) ...trackCodesOfTag(t)];
    if (wanted.isEmpty) return;
    bool speaks(String lang) => wanted.contains(lang.toLowerCase());
    final audio = audios.where((a) => speaks(a.language)).firstOrNull;
    if (audio != null) {
      if (audio.id != _engine.audioId) unawaited(_engine.setAudio(audio));
      return;
    }
    final sub = _engine.subtitles.where((s) => speaks(s.language)).firstOrNull;
    if (sub != null) unawaited(_engine.setSubtitle(sub));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _hideTimer?.cancel();
    _noPicture?.cancel();
    _saveTimer?.cancel();
    _voteTimer?.cancel();
    _nextTimer?.cancel();
    _nextFocus.dispose();
    final w = widget.watch;
    if (w != null) {
      _savePlace();
      unawaited(IptvLearning.record(
        watch: w,
        startedAt: _startedAt,
        position: _pos,
        duration: _dur,
        watched: _watched,
      ));
    }
    GetIt.instance<ScreensaverController>().setPlaybackActive(false);
    unawaited(_engine.dispose());
    _focus.dispose();
    _playFocus.dispose();
    _barFocus.dispose();
    _scrubTimer?.cancel();
    super.dispose();
  }

  void _showControls() {
    final wasHidden = !_controls;
    setState(() => _controls = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_sheetOpen) setState(() => _controls = false);
      if (mounted) _focus.requestFocus();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only on showing them: a button or the bar already chosen keeps the focus.
      if (mounted && _controls && wasHidden && !_playFocus.hasFocus) _playFocus.requestFocus();
    });
  }

  void _seekBy(int seconds) {
    final to = _pos + Duration(seconds: seconds);
    final target = to < Duration.zero ? Duration.zero : (_dur > Duration.zero && to > _dur ? _dur : to);
    unawaited(_engine.seek(target));
    _learnIntro(target);
    _showControls();
  }

  /// Back to the start of a film that picked up where it was left.
  void _restart() {
    setState(() => _resumedFrom = null);
    _resumeAt.remove(widget.url);
    unawaited(_engine.seek(Duration.zero));
    _showControls();
  }

  String? get _voteKey {
    final w = widget.watch;
    if (w == null || w.isSeries) return null;
    return w.tmdb.isEmpty ? 'iptv:movie:${w.id}' : 'movie:${w.tmdb}';
  }

  /// In a film's last minutes, once: « J'ai aimé / Bof », like the library
  /// player, when personalization is on and the film has no vote yet.
  void _checkVote() {
    if (_voteAsked || _voteVisible || _dur < const Duration(minutes: 40)) return;
    final key = _voteKey;
    if (key == null) return;
    final remaining = _dur - _pos;
    if (_pos < _dur * 0.95 || remaining > const Duration(minutes: 8)) return;
    _voteAsked = true;
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<SeerrPreferences>()) return;
    final prefs = getIt<SeerrPreferences>();
    if (!prefs.vjodPersonalize) return;
    if (VjodVotes.decode(prefs.vjodVotesJson).voteFor(key) != null) return;
    if (!mounted) return;
    setState(() => _voteVisible = true);
    _voteTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _voteVisible = false);
    });
  }

  Future<void> _vote(bool liked) async {
    _voteTimer?.cancel();
    if (mounted) setState(() => _voteVisible = false);
    final key = _voteKey;
    final w = widget.watch;
    if (key == null || w == null) return;
    final tmdb = int.tryParse(w.tmdb);
    final genres = tmdb == null ? <TasteGenre>{} : (await IptvLearning.facts('movie', tmdb)).genres;
    final prefs = GetIt.instance<SeerrPreferences>();
    final votes = VjodVotes.decode(prefs.vjodVotesJson).record(
      VjodVote(key: key, title: w.name, genres: genres, liked: liked, at: DateTime.now()),
    );
    await prefs.setVjodVotesJson(votes.encode());
  }

  Widget _votePrompt() {
    Widget pill(String label, IconData icon, bool liked) => Material(
      color: Colors.white.withValues(alpha: liked ? 0.95 : 0.16),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        canRequestFocus: false,
        onTap: () => unawaited(_vote(liked)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: liked ? Colors.black : Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    color: liked ? Colors.black : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
        ),
      ),
    );
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 24,
      right: 24,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(color: const Color(0xE60B0B0D), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Alors, ce film ?',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            // On a remote the answers stack the way the arrows point.
            pill('▲  J\'ai aimé', Icons.thumb_up_alt_rounded, true),
            const SizedBox(height: 8),
            pill('▼  Bof', Icons.thumb_down_alt_rounded, false),
          ],
        ),
      ),
    );
  }

  Widget _nextPrompt() {
    final ep = _nextEp!;
    return Positioned(
      right: 24,
      bottom: 120,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        decoration: BoxDecoration(color: const Color(0xE60B0B0D), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Épisode suivant : S${ep.season} É${ep.number}',
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            if (ep.title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(ep.title, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  focusNode: _nextFocus,
                  onPressed: _goNext,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: Text('Lire ($_nextCount s)'),
                ),
                const SizedBox(width: 10),
                FilledButton.tonal(onPressed: _dismissNext, child: const Text('Annuler')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _onBarKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      _scrubHeld = 0;
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key.isSelectKey && _scrubTo != null) {
      _commitScrub();
      return KeyEventResult.handled;
    }
    if (!key.isLeftKey && !key.isRightKey) return KeyEventResult.ignored;
    if (_dur == Duration.zero) return KeyEventResult.handled;
    _scrubHeld = event is KeyRepeatEvent ? _scrubHeld + 1 : 0;
    final step = _scrubHeld > 20 ? 120 : (_scrubHeld > 8 ? 60 : (_scrubHeld > 2 ? 30 : 10));
    var to = (_scrubTo ?? _pos) + Duration(seconds: key.isLeftKey ? -step : step);
    if (to < Duration.zero) to = Duration.zero;
    if (to > _dur) to = _dur;
    setState(() => _scrubTo = to);
    _showControls();
    _scrubTimer?.cancel();
    _scrubTimer = Timer(const Duration(milliseconds: 800), _commitScrub);
    return KeyEventResult.handled;
  }

  void _commitScrub() {
    _scrubTimer?.cancel();
    _scrubTimer = null;
    final to = _scrubTo;
    if (to == null) return;
    unawaited(_engine.seek(to));
    if (mounted) setState(() => _scrubTo = null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key.isBackKey) {
      if (_nextVisible) {
        _dismissNext();
      } else if (_controls) {
        setState(() => _controls = false);
        _focus.requestFocus();
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      unawaited(_engine.playOrPause());
      _showControls();
      return KeyEventResult.handled;
    }
    if (_voteVisible && !_controls && (key.isUpKey || key.isDownKey)) {
      unawaited(_vote(key.isUpKey));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-30);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(30);
      return KeyEventResult.handled;
    }
    // With the controls up, the arrows move between them.
    if (_controls) return KeyEventResult.ignored;
    if (key.isLeftKey) {
      _seekBy(-10);
      return KeyEventResult.handled;
    }
    if (key.isRightKey) {
      _seekBy(30);
      return KeyEventResult.handled;
    }
    if (key.isSelectKey || key.isUpKey || key.isDownKey || key.isContextMenuKey) {
      _showControls();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _sheetOpen = false;

  Future<T?> _sheet<T>(String title, List<Widget> Function(BuildContext) tiles) async {
    _sheetOpen = true;
    _hideTimer?.cancel();
    final r = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
              ...tiles(ctx),
            ],
          ),
        ),
      ),
    );
    _sheetOpen = false;
    if (mounted) _showControls();
    return r;
  }

  String _trackName(VodTrack t, String fallback) {
    final n = trackLanguageName(t.language, t.title);
    return n.isEmpty ? fallback : n;
  }

  Future<void> _audioMenu() async {
    final audios = _engine.audio;
    final current = _engine.audioId;
    await _sheet<void>('Langue audio', (ctx) => [
      if (audios.isEmpty) const ListTile(title: Text('Une seule piste audio dans ce fichier')),
      for (final (i, a) in audios.indexed)
        ListTile(
          autofocus: a.id == current || (i == 0 && current == null),
          leading: Icon(a.id == current ? Icons.check_rounded : Icons.volume_up_rounded),
          title: Text(_trackName(a, 'Piste ${i + 1}')),
          onTap: () {
            unawaited(_engine.setAudio(a));
            Navigator.of(ctx).pop();
          },
        ),
    ]);
  }

  Future<void> _subsMenu() async {
    final subs = _engine.subtitles;
    final current = _engine.subtitleId;
    await _sheet<void>('Sous-titres', (ctx) => [
      ListTile(
        autofocus: current == null,
        leading: Icon(current == null ? Icons.check_rounded : Icons.subtitles_off_rounded),
        title: const Text('Désactivés'),
        onTap: () {
          unawaited(_engine.setSubtitle(null));
          Navigator.of(ctx).pop();
        },
      ),
      if (subs.isEmpty) const ListTile(title: Text('Aucun sous-titre dans ce fichier')),
      for (final (i, s) in subs.indexed)
        ListTile(
          autofocus: s.id == current,
          leading: Icon(s.id == current ? Icons.check_rounded : Icons.subtitles_rounded),
          title: Text(_trackName(s, 'Sous-titres ${i + 1}')),
          onTap: () {
            unawaited(_engine.setSubtitle(s));
            Navigator.of(ctx).pop();
          },
        ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.format_size_rounded),
        title: const Text('Taille'),
        subtitle: Text(_subSizes.firstWhere((x) => x.$2 == _subScale, orElse: () => _subSizes[1]).$1),
        onTap: () {
          final i = _subSizes.indexWhere((x) => x.$2 == _subScale);
          setState(() => _subScale = _subSizes[(i + 1) % _subSizes.length].$2);
          unawaited(_engine.styleSubtitles(scale: _subScale, raised: _subRaised));
          Navigator.of(ctx).pop();
          unawaited(_subsMenu());
        },
      ),
      ListTile(
        leading: const Icon(Icons.vertical_align_top_rounded),
        title: const Text('Position'),
        subtitle: Text(_subRaised ? 'Plus haut' : 'En bas'),
        onTap: () {
          setState(() => _subRaised = !_subRaised);
          unawaited(_engine.styleSubtitles(scale: _subScale, raised: _subRaised));
          Navigator.of(ctx).pop();
          unawaited(_subsMenu());
        },
      ),
      ListTile(
        leading: const Icon(Icons.timer_outlined),
        title: Text('Décalage : ${_subDelay >= 0 ? '+' : ''}${_subDelay.toStringAsFixed(1)} s'),
        subtitle: const Text('Appuie pour avancer de 0,5 s, appui long pour reculer'),
        onTap: () {
          _setDelay(_subDelay + 0.5);
          Navigator.of(ctx).pop();
          unawaited(_subsMenu());
        },
        onLongPress: () {
          _setDelay(_subDelay - 0.5);
          Navigator.of(ctx).pop();
          unawaited(_subsMenu());
        },
      ),
      if (_subDelay != 0)
        ListTile(
          leading: const Icon(Icons.restart_alt_rounded),
          title: const Text('Remettre le décalage à zéro'),
          onTap: () {
            _setDelay(0);
            Navigator.of(ctx).pop();
          },
        ),
      if (TvEngineChoice.exoAvailable) ...[
        const Divider(),
        ListTile(
          leading: const Icon(Icons.play_circle_outline_rounded),
          title: Text('Lecteur : ${_engine.name}'),
          subtitle: Text(_engine is ExoVodEngine
              ? 'Passer sur mpv (ancien lecteur) si l\'image ou les sous-titres posent problème'
              : 'Repasser sur ExoPlayer'),
          onTap: () {
            Navigator.of(ctx).pop();
            _exoRetried = true;
            unawaited(_switchEngine(_engine is ExoVodEngine ? MpvVodEngine() : ExoVodEngine()));
          },
        ),
      ],
    ]);
  }

  void _setDelay(double seconds) {
    setState(() => _subDelay = seconds);
    unawaited(_engine.setSubtitleDelay(seconds));
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _button(IconData icon, String label, VoidCallback onTap, {FocusNode? focusNode}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: FilledButton.tonalIcon(
      focusNode: focusNode,
      onPressed: () {
        onTap();
        _showControls();
      },
      icon: Icon(icon),
      label: Text(label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final audio = _engine.audio.where((a) => a.id == _engine.audioId).firstOrNull;
    final audioName = audio == null ? '' : trackLanguageName(audio.language, null);
    final sub = _engine.subtitles.where((s) => s.id == _engine.subtitleId).firstOrNull;
    final subName = sub == null ? 'Désactivés' : _trackName(sub, 'activés');
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _controls ? setState(() => _controls = false) : _showControls(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              KeyedSubtree(
                key: ValueKey(_engine),
                child: _engine.view(scale: _subScale, raised: _subRaised),
              ),
              if (_error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!, textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 20)),
                  ),
                )
              else if (_loading || _buffering)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      if (_loading) ...[
                        const SizedBox(height: 16),
                        Text('Recherche de la meilleure source… (${_engine.name})',
                            style: const TextStyle(color: Colors.white70, fontSize: 18)),
                      ],
                    ],
                  ),
                ),
              if (_voteVisible && _error == null) _votePrompt(),
              if (_nextVisible && _error == null) _nextPrompt(),
              // Touch and remote: a visible way out, shown with the controls (and on an error).
              if (_controls || _error != null)
                Positioned(
                  left: 16,
                  top: 12,
                  child: SafeArea(
                    child: FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Retour'),
                    ),
                  ),
                ),
              if (_controls && _error == null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xDD000000)],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.title.isNotEmpty)
                          Text(widget.title,
                              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(_fmt(_scrubTo ?? _pos),
                                style: TextStyle(
                                  color: _scrubTo != null ? Theme.of(context).colorScheme.primary : Colors.white,
                                  fontWeight: _scrubTo != null ? FontWeight.w700 : FontWeight.normal,
                                )),
                            Expanded(
                              // Reachable with the remote (up from the buttons): left and
                              // right move in the film, OK or a pause jumps there.
                              child: Focus(
                                focusNode: _barFocus,
                                onKeyEvent: _onBarKey,
                                onFocusChange: (_) => setState(() {}),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _barFocus.hasFocus ? Colors.white : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: ExcludeFocus(
                                    child: Slider(
                                      value: _dur.inMilliseconds == 0
                                          ? 0
                                          : ((_scrubTo ?? _pos).inMilliseconds / _dur.inMilliseconds)
                                              .clamp(0.0, 1.0),
                                      onChanged: _dur == Duration.zero
                                          ? null
                                          : (v) => unawaited(_engine.seek(_dur * v)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Text(_fmt(_dur), style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              if (_canSkipIntro)
                                _button(Icons.fast_forward_rounded, 'Passer le générique', _skipIntro),
                              _button(Icons.replay_10_rounded, '−10 s', () => _seekBy(-10)),
                              _button(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  _playing ? 'Pause' : 'Lecture', () => unawaited(_engine.playOrPause()),
                                  focusNode: _playFocus),
                              _button(Icons.forward_30_rounded, '+30 s', () => _seekBy(30)),
                              if (_resumedFrom != null)
                                _button(Icons.restart_alt_rounded, 'Depuis le début', _restart),
                              _button(Icons.record_voice_over_rounded,
                                  audioName.isEmpty ? 'Audio' : 'Audio : $audioName', () => unawaited(_audioMenu())),
                              _button(Icons.subtitles_rounded, 'Sous-titres : $subName',
                                  () => unawaited(_subsMenu())),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page of a title read from the IPTV provider opens this player.
String providerPlayerTitle(XtreamTitle copy, {String quality = ''}) => [
  copy.name,
  if (copy.tag.isNotEmpty) languageName(copy.tag),
  if (quality.isNotEmpty) quality,
].join(' · ');
