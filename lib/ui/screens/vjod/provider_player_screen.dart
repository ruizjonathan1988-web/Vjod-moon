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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import '../../../data/services/vjod/provider_catalog_access.dart';
import '../../../data/services/vjod/xtream_catalog.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/system_ui.dart';
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

  const ProviderPlayerScreen({super.key, required this.url, this.title = ''});

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

  bool get _exoWanted => TvEngineChoice.exoAvailable && TvEngineChoice.value != 'mpv';

  @override
  void initState() {
    super.initState();
    setImmersive(true);
    GetIt.instance<ScreensaverController>().setPlaybackActive(true);
    _engine = _exoWanted ? ExoVodEngine() : MpvVodEngine();
    _listen();
    unawaited(_open());
  }

  void _listen() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    final e = _engine;
    _subs.addAll([
      e.position.listen((p) {
        _pos = p;
        if (_dur > Duration.zero && p > Duration.zero) _resumeAt[widget.url] = p;
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
    final from = _resumeAt[widget.url];
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
      if (mounted && _engine is MpvVodEngine) setState(() => _loading = false);
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
    GetIt.instance<ScreensaverController>().setPlaybackActive(false);
    unawaited(_engine.dispose());
    _focus.dispose();
    _playFocus.dispose();
    super.dispose();
  }

  void _showControls() {
    setState(() => _controls = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_sheetOpen) setState(() => _controls = false);
      if (mounted) _focus.requestFocus();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controls && !_playFocus.hasFocus) _playFocus.requestFocus();
    });
  }

  void _seekBy(int seconds) {
    final to = _pos + Duration(seconds: seconds);
    unawaited(_engine.seek(to < Duration.zero ? Duration.zero : (_dur > Duration.zero && to > _dur ? _dur : to)));
    _showControls();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key.isBackKey) {
      if (_controls) {
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
                            Text(_fmt(_pos), style: const TextStyle(color: Colors.white)),
                            Expanded(
                              child: ExcludeFocus(
                                child: Slider(
                                  value: _dur.inMilliseconds == 0
                                      ? 0
                                      : (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0),
                                  onChanged: _dur == Duration.zero
                                      ? null
                                      : (v) => unawaited(_engine.seek(_dur * v)),
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
                              _button(Icons.replay_10_rounded, '−10 s', () => _seekBy(-10)),
                              _button(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  _playing ? 'Pause' : 'Lecture', () => unawaited(_engine.playOrPause()),
                                  focusNode: _playFocus),
                              _button(Icons.forward_30_rounded, '+30 s', () => _seekBy(30)),
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
