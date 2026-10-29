// The player of the films and episodes read from the IPTV provider (through
// Ma TV, which picks the best source and switches to the next if one fails).
// Unlike the trailer player it used to borrow, it waits long enough for the
// seedbox to find a source that answers, and it has what a film needs: the
// audio language, subtitles with their size, place and delay, seeking, and
// the remote's keys (OK shows the controls, LEFT / RIGHT seek, PLAY/PAUSE,
// BACK hides the controls then leaves).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/services/vjod/provider_catalog_access.dart';
import '../../../data/services/vjod/xtream_catalog.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/system_ui.dart';
import '../../screensaver/screensaver_controller.dart';

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
  static const _subSizes = [('Petit', 32.0), ('Moyen', 44.0), ('Grand', 56.0), ('Très grand', 70.0)];

  final _player = Player(configuration: const PlayerConfiguration(libass: false));
  late final _video = VideoController(_player);
  final _focus = FocusNode(debugLabel: 'provider_player');
  final _playFocus = FocusNode(debugLabel: 'provider_player_play');
  final _subs = <StreamSubscription<Object?>>[];

  bool _loading = true;
  String? _error;
  bool _controls = false;
  Timer? _hideTimer;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  Tracks _tracks = const Tracks();
  AudioTrack? _audio;
  SubtitleTrack? _sub;
  bool _picked = false;
  double _subSize = 44;
  double _subLift = 24;
  double _subDelay = 0;

  @override
  void initState() {
    super.initState();
    setImmersive(true);
    GetIt.instance<ScreensaverController>().setPlaybackActive(true);
    _subs.addAll([
      _player.stream.position.listen((p) {
        _pos = p;
        if (_dur > Duration.zero) _resumeAt[widget.url] = p;
        if (_controls && mounted) setState(() {});
      }),
      _player.stream.duration.listen((d) => setState(() => _dur = d)),
      _player.stream.playing.listen((p) => setState(() => _playing = p)),
      _player.stream.buffering.listen((b) => setState(() => _buffering = b)),
      _player.stream.tracks.listen((t) {
        setState(() => _tracks = t);
        _pickLanguages();
      }),
      _player.stream.track.listen((t) => setState(() {
        _audio = t.audio;
        _sub = t.subtitle;
      })),
      _player.stream.error.listen((e) {
        if (_loading && mounted) setState(() => _error = e);
      }),
    ]);
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final dynamic native = _player.platform;
      for (final kv in const [
        ('network-timeout', '60'),
        ('cache', 'yes'),
        ('demuxer-max-bytes', '150MiB'),
        ('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5'),
      ]) {
        try {
          await Future<void>.value(native.setProperty(kv.$1, kv.$2));
        } catch (_) {}
      }
    } catch (_) {}
    try {
      await _player.open(Media(widget.url)).timeout(_openTimeout);
      final from = _resumeAt[widget.url];
      if (from != null && from > const Duration(minutes: 1)) {
        await _player.seek(from - const Duration(seconds: 5));
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is TimeoutException
            ? 'Aucune source n\'a répondu à temps. Réessaie dans un moment.'
            : 'Lecture impossible : $e');
      }
    }
  }

  /// Once the tracks are known, the profile's language: its audio when the
  /// file has it, else its subtitles over the original sound.
  void _pickLanguages() {
    if (_picked) return;
    final audios = _realAudio;
    if (audios.isEmpty) return;
    _picked = true;
    final wanted = [for (final t in currentProviderLanguages()) ...trackCodesOfTag(t)];
    if (wanted.isEmpty) return;
    bool speaks(String? lang) => wanted.contains((lang ?? '').toLowerCase());
    final audio = audios.where((a) => speaks(a.language)).firstOrNull;
    if (audio != null) {
      unawaited(_player.setAudioTrack(audio));
      return;
    }
    final sub = _realSubs.where((s) => speaks(s.language)).firstOrNull;
    if (sub != null) unawaited(_player.setSubtitleTrack(sub));
  }

  List<AudioTrack> get _realAudio => [
    for (final a in _tracks.audio)
      if (a.id != 'auto' && a.id != 'no') a,
  ];

  List<SubtitleTrack> get _realSubs => [
    for (final s in _tracks.subtitle)
      if (s.id != 'auto' && s.id != 'no') s,
  ];

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _hideTimer?.cancel();
    GetIt.instance<ScreensaverController>().setPlaybackActive(false);
    _player.dispose();
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
    unawaited(_player.seek(to < Duration.zero ? Duration.zero : (_dur > Duration.zero && to > _dur ? _dur : to)));
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
      unawaited(_player.playOrPause());
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

  Future<void> _audioMenu() async {
    final audios = _realAudio;
    await _sheet<void>('Langue audio', (ctx) => [
      if (audios.isEmpty) const ListTile(title: Text('Une seule piste audio dans ce fichier')),
      for (final (i, a) in audios.indexed)
        ListTile(
          autofocus: a.id == _audio?.id || (i == 0 && _audio == null),
          leading: Icon(a.id == _audio?.id ? Icons.check_rounded : Icons.volume_up_rounded),
          title: Text(trackLanguageName(a.language, a.title).isEmpty
              ? 'Piste ${i + 1}'
              : trackLanguageName(a.language, a.title)),
          subtitle: Text([
            if ((a.codec ?? '').isNotEmpty) a.codec!.toUpperCase(),
            if ((a.channelscount ?? 0) > 0) '${a.channelscount} canaux',
          ].join(' · ')),
          onTap: () {
            unawaited(_player.setAudioTrack(a));
            Navigator.of(ctx).pop();
          },
        ),
    ]);
  }

  Future<void> _subsMenu() async {
    final subs = _realSubs;
    await _sheet<void>('Sous-titres', (ctx) => [
      ListTile(
        autofocus: _sub == null || _sub!.id == 'no',
        leading: Icon(_sub == null || _sub!.id == 'no' ? Icons.check_rounded : Icons.subtitles_off_rounded),
        title: const Text('Désactivés'),
        onTap: () {
          unawaited(_player.setSubtitleTrack(SubtitleTrack.no()));
          Navigator.of(ctx).pop();
        },
      ),
      if (subs.isEmpty) const ListTile(title: Text('Aucun sous-titre dans ce fichier')),
      for (final (i, s) in subs.indexed)
        ListTile(
          autofocus: s.id == _sub?.id,
          leading: Icon(s.id == _sub?.id ? Icons.check_rounded : Icons.subtitles_rounded),
          title: Text(trackLanguageName(s.language, s.title).isEmpty
              ? 'Sous-titres ${i + 1}'
              : trackLanguageName(s.language, s.title)),
          onTap: () {
            unawaited(_player.setSubtitleTrack(s));
            Navigator.of(ctx).pop();
          },
        ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.format_size_rounded),
        title: const Text('Taille'),
        subtitle: Text(_subSizes.firstWhere((x) => x.$2 == _subSize, orElse: () => _subSizes[1]).$1),
        onTap: () {
          final i = _subSizes.indexWhere((x) => x.$2 == _subSize);
          setState(() => _subSize = _subSizes[(i + 1) % _subSizes.length].$2);
          Navigator.of(ctx).pop();
          unawaited(_subsMenu());
        },
      ),
      ListTile(
        leading: const Icon(Icons.vertical_align_top_rounded),
        title: const Text('Position'),
        subtitle: Text(_subLift > 60 ? 'Plus haut' : 'En bas'),
        onTap: () {
          setState(() => _subLift = _subLift > 60 ? 24 : 120);
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
    ]);
  }

  void _setDelay(double seconds) {
    setState(() => _subDelay = seconds);
    try {
      final dynamic native = _player.platform;
      unawaited(Future<void>.value(native.setProperty('sub-delay', seconds.toStringAsFixed(2))));
    } catch (_) {}
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
    final audioName = _audio == null ? '' : trackLanguageName(_audio!.language, null);
    final subName = _sub == null || _sub!.id == 'no' || _sub!.id == 'auto'
        ? 'Désactivés'
        : trackLanguageName(_sub!.language, null);
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
              Video(
                controller: _video,
                controls: NoVideoControls,
                fit: BoxFit.contain,
                fill: Colors.black,
                subtitleViewConfiguration: SubtitleViewConfiguration(
                  style: TextStyle(
                    fontSize: _subSize,
                    color: Colors.white,
                    backgroundColor: const Color(0x99000000),
                    height: 1.3,
                  ),
                  padding: EdgeInsets.fromLTRB(24, 24, 24, _subLift),
                ),
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
                        const Text('Recherche de la meilleure source…',
                            style: TextStyle(color: Colors.white70, fontSize: 18)),
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
                                      : (v) => unawaited(_player.seek(_dur * v)),
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
                                  _playing ? 'Pause' : 'Lecture', () => unawaited(_player.playOrPause()),
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
