// Replay of the channels (VJOD 4.18): « Mes émissions » (the new episodes of
// what this profile follows), the page of a channel (last night, then one
// row per show), and an episode's sheet. One press plays; « Infos » or a
// long press opens the sheet. The episode plays in VJOD's own player; an
// encrypted one opens the channel's app, last of all.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/vjod/ma_tv_replay.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/media_card.dart';
import 'ma_tv_widgets.dart';

const _ink = Color(0xFFEDEBE6);
const _mute = Color(0xFFB8B4AC);
const _bg = Color(0xFF0B0B0D);

/// Plays [item]: in VJOD when the channel serves this device a readable
/// stream, else in the channel's app (said in one line first).
Future<void> playReplay(BuildContext context, ReplayItem item) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(const SnackBar(content: Text('Ouverture…'), duration: Duration(seconds: 2)));
  final play = await MaTvReplay().playback(item);
  if (!context.mounted) return;
  messenger?.hideCurrentSnackBar();
  final title = item.title.isEmpty || item.title == item.show ? item.show : '${item.show} · ${item.title}';
  if (play.inVjod) {
    unawaited(context.push(Destinations.providerPlayer(url: play.url!, title: title)));
    return;
  }
  messenger?.showSnackBar(SnackBar(
    content: Text(play.reason == 'chiffré'
        ? 'Cet épisode est protégé : il s’ouvre dans l’appli de la chaîne.'
        : 'Lecture impossible ici : ouverture dans l’appli de la chaîne.'),
    duration: const Duration(seconds: 4),
  ));
  final opened = await MaTvReplay.openOfficial(item, tv: PlatformDetection.isTV);
  if (!opened) {
    messenger?.showSnackBar(const SnackBar(content: Text('Ni la vidéo ni l’appli de la chaîne n’ont pu s’ouvrir.')));
  }
}

Color _focusColor() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<UserPreferences>()) return _ink;
  return Color(getIt<UserPreferences>().get(UserPreferences.focusColor).colorValue);
}

Widget _episodeCard(BuildContext context, ReplayItem e, {bool autofocus = false, double width = 260, VoidCallback? afterChange}) {
  return MediaCard(
    title: e.show,
    subtitle: '${e.dayLabel}${e.subtitle.isNotEmpty && e.subtitle != e.dayLabel ? ' · ${e.subtitle}' : ''}',
    imageUrl: e.image.isEmpty ? null : e.image,
    width: width,
    aspectRatio: 16 / 9,
    itemType: 'Episode',
    focusColor: _focusColor(),
    autofocus: autofocus,
    onTap: () => unawaited(playReplay(context, e)),
    onLongPress: () => unawaited(showReplaySheet(context, e, afterChange: afterChange)),
  );
}

/// The episode's sheet: Regarder, Suivre / Suivi, Pas pour nous, and the
/// channel's app.
Future<void> showReplaySheet(BuildContext context, ReplayItem e, {VoidCallback? afterChange}) async {
  final client = MaTvReplay();
  var followed = e.followed;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: const Color(0xFF1C1418),
        title: Text(e.show, style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text([e.dayLabel, if (e.subtitle != e.dayLabel) e.subtitle].where((s) => s.isNotEmpty).join(' · '),
                  style: const TextStyle(color: _mute, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (e.description.isNotEmpty)
                Text(e.description, maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 15)),
            ],
          ),
        ),
        actions: [
          FilledButton.icon(
            autofocus: true,
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(playReplay(context, e));
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Regarder'),
          ),
          OutlinedButton(
            onPressed: () async {
              final ok = await client.setPref(show: e.show, follow: !followed);
              if (ok) {
                setState(() => followed = !followed);
                afterChange?.call();
              }
            },
            child: Text(followed ? '✓ Suivi' : '+ Suivre'),
          ),
          OutlinedButton(
            onPressed: () async {
              await client.setPref(show: e.show, hide: true);
              if (ctx.mounted) Navigator.of(ctx).pop();
              afterChange?.call();
            },
            child: const Text('Pas pour nous'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(MaTvReplay.openOfficial(e, tv: PlatformDetection.isTV));
            },
            child: const Text('Dans l’appli de la chaîne'),
          ),
        ],
      ),
    ),
  );
}

class _ReplayScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _ReplayScaffold({required this.title, this.subtitle = '', required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: FocusTraversalGroup(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Retour',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded, color: _ink),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(color: _ink, fontSize: 28, fontWeight: FontWeight.w800)),
                            if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(color: _mute, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(padding: const EdgeInsets.fromLTRB(28, 8, 28, 40), sliver: SliverToBoxAdapter(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

/// « Mes émissions »: the new episodes of the shows this profile follows.
/// With nothing followed yet: « À la une » to start from, each with Suivre.
class MaTvReplayMineScreen extends StatefulWidget {
  const MaTvReplayMineScreen({super.key});

  @override
  State<MaTvReplayMineScreen> createState() => _MaTvReplayMineScreenState();
}

class _MaTvReplayMineScreenState extends State<MaTvReplayMineScreen> {
  final _client = MaTvReplay();
  ReplayHome? _home;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // Seen: the Home badges start again from now.
    unawaited(_client.setPref(seen: true));
  }

  Future<void> _load() async {
    final h = await _client.home();
    if (!mounted) return;
    setState(() {
      _home = h;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = _home;
    return _ReplayScaffold(
      title: 'Mes émissions',
      subtitle: h != null && h.mine.isNotEmpty
          ? 'Un appui : ça joue · appui long : la fiche'
          : 'Suis tes émissions : leurs nouveaux épisodes arriveront ici',
      child: _loading
          ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          : h == null
          ? const Text('Le replay ne répond pas (Ma TV 3.62 ou plus nécessaire).', style: TextStyle(color: _mute))
          : h.mine.isNotEmpty
          ? Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (var i = 0; i < h.mine.length; i++)
                  _episodeCard(context, h.mine[i], autofocus: i == 0, afterChange: _load),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('À la une des chaînes', style: TextStyle(color: _ink, fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Appui long sur un épisode : « Suivre » son émission.', style: TextStyle(color: _mute)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (var i = 0; i < h.featured.length; i++)
                      _episodeCard(context, h.featured[i], autofocus: i == 0, afterChange: _load),
                  ],
                ),
              ],
            ),
    );
  }
}

/// The page of a channel: last night first, then one row per show (the
/// followed ones first).
class MaTvReplayChannelScreen extends StatefulWidget {
  final String chan;
  final String name;
  const MaTvReplayChannelScreen({super.key, required this.chan, required this.name});

  @override
  State<MaTvReplayChannelScreen> createState() => _MaTvReplayChannelScreenState();
}

class _MaTvReplayChannelScreenState extends State<MaTvReplayChannelScreen> {
  final _client = MaTvReplay();
  ReplayChannelPage? _page;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final p = await _client.channel(widget.chan);
    if (!mounted) return;
    setState(() {
      _page = p;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _page;
    final prime = p?.prime;
    return _ReplayScaffold(
      title: 'Replay ${widget.name}',
      subtitle: 'Jusqu’à 3 semaines · météo, journaux et jeux masqués',
      child: _loading
          ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          : p == null || (prime == null && p.shows.isEmpty)
          ? const Text('Rien en replay pour l’instant sur cette chaîne.', style: TextStyle(color: _mute))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (prime != null) ...[
                  const Text('HIER SOIR', style: TextStyle(color: _mute, fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _episodeCard(context, prime, autofocus: true, width: 420, afterChange: _load),
                  const SizedBox(height: 24),
                ],
                for (final s in p.shows) ...[
                  Row(
                    children: [
                      Text(s.show, style: const TextStyle(color: _ink, fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      Text('${s.items.length} épisode${s.items.length > 1 ? 's' : ''}', style: const TextStyle(color: _mute)),
                      if (s.followed) ...[
                        const SizedBox(width: 10),
                        const Text('✓ Suivi', style: TextStyle(color: Color(0xFF8FD6A8), fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 220,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: s.items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 16),
                      itemBuilder: (context, i) => _episodeCard(
                        context,
                        s.items[i],
                        autofocus: prime == null && s == p.shows.first && i == 0,
                        afterChange: _load,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ],
            ),
    );
  }
}

/// Opens « Mes émissions » or a channel's page from the Home row.
void openReplayCard(BuildContext context, Map<dynamic, dynamic> r, {VoidCallback? onClosed}) {
  final kind = '${r['kind'] ?? ''}';
  final screen = kind == 'mine'
      ? const MaTvReplayMineScreen()
      : MaTvReplayChannelScreen(chan: '${r['chan'] ?? ''}', name: '${r['name'] ?? ''}');
  unawaited(Navigator.of(context, rootNavigator: true).push(maTvRoute<void>((_) => screen)).then((_) => onClosed?.call()));
}
