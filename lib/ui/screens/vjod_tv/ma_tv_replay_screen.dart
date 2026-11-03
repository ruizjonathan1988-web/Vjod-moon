// Replay of the channels (VJOD 4.18): « Mes émissions » (the new episodes of
// what this profile follows), the page of a channel (last night, one row per
// show, then day by day), and an episode's sheet. One press plays; « Infos » or a
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

Widget _chip(String text, {Color bg = const Color(0xCC141210), Color fg = _ink}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
  child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .5)),
);

/// An episode: one press plays. [siblings] give « Épisode suivant » on its
/// sheet; [chanName] puts the channel on the picture (« Mes émissions »);
/// [infos] adds the « Infos » button under it.
Widget _episodeCard(
  BuildContext context,
  ReplayItem e, {
  bool autofocus = false,
  double width = 260,
  List<ReplayItem> siblings = const [],
  String chanName = '',
  bool infos = false,
  VoidCallback? afterChange,
}) {
  void sheet() => unawaited(showReplaySheet(context, e, siblings: siblings, afterChange: afterChange));
  final card = MediaCard(
    title: e.show,
    subtitle: '${e.dayLabel}${e.subtitle.isNotEmpty && e.subtitle != e.dayLabel ? ' · ${e.subtitle}' : ''}',
    imageUrl: e.image.isEmpty ? null : e.image,
    width: width,
    aspectRatio: 16 / 9,
    itemType: 'Episode',
    focusColor: _focusColor(),
    autofocus: autofocus,
    overlayOccupiesTopLeft: chanName.isNotEmpty,
    imageOverlays: [
      if (chanName.isNotEmpty) Positioned(top: 8, left: 8, child: _chip(chanName)),
      if (e.isNew) Positioned(top: 8, right: 8, child: _chip('NOUVEAU', bg: const Color(0xFFE5484D), fg: Colors.white)),
    ],
    onTap: () => unawaited(playReplay(context, e)),
    onLongPress: sheet,
  );
  if (!infos) return card;
  return SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        card,
        TextButton.icon(
          onPressed: sheet,
          icon: const Icon(Icons.info_outline_rounded, size: 18),
          label: const Text('Infos'),
          style: TextButton.styleFrom(foregroundColor: _mute, padding: const EdgeInsets.symmetric(horizontal: 6)),
        ),
      ],
    ),
  );
}

/// The episode's sheet: Regarder, Suivre / Suivi, Épisode suivant, Pas pour
/// nous, and the channel's app.
Future<void> showReplaySheet(
  BuildContext context,
  ReplayItem e, {
  List<ReplayItem> siblings = const [],
  VoidCallback? afterChange,
}) async {
  final client = MaTvReplay();
  var followed = e.followed;
  final next = nextEpisode(e, siblings);
  final meta = [e.dayLabel, if (e.subtitle != e.dayLabel) e.subtitle].where((s) => s.isNotEmpty).join(' · ');
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: const Color(0xFF1C1418),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meta.toUpperCase(), style: const TextStyle(color: _mute, fontSize: 13, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(e.show, style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
            if (e.title.isNotEmpty && e.title != e.show)
              Text(e.title, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: e.description.isEmpty
              ? const SizedBox.shrink()
              : Text(e.description, maxLines: 7, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 15)),
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
          if (next != null)
            OutlinedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(playReplay(context, next));
              },
              child: const Text('Épisode suivant'),
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

Widget _rowTitle(String title, {String count = '', bool followed = false}) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Row(
    children: [
      Flexible(child: Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 20, fontWeight: FontWeight.w700))),
      if (count.isNotEmpty) ...[const SizedBox(width: 10), Text(count, style: const TextStyle(color: _mute))],
      if (followed) ...[
        const SizedBox(width: 10),
        const Text('✓ Suivi', style: TextStyle(color: Color(0xFF8FD6A8), fontWeight: FontWeight.w700)),
      ],
    ],
  ),
);

Widget _episodeRow(BuildContext context, List<ReplayItem> items, {bool autofocusFirst = false, VoidCallback? afterChange}) => SizedBox(
  height: 230,
  child: ListView.separated(
    scrollDirection: Axis.horizontal,
    itemCount: items.length,
    separatorBuilder: (_, _) => const SizedBox(width: 16),
    itemBuilder: (context, i) => _episodeCard(context, items[i], autofocus: autofocusFirst && i == 0, siblings: items, afterChange: afterChange),
  ),
);

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
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
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
              SliverPadding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), sliver: SliverToBoxAdapter(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}

/// « Mes émissions »: the new episodes of the shows this profile follows.
/// With nothing followed yet: « Suis tes émissions en un appui », from what
/// the channels put forward.
class MaTvReplayMineScreen extends StatefulWidget {
  const MaTvReplayMineScreen({super.key});

  @override
  State<MaTvReplayMineScreen> createState() => _MaTvReplayMineScreenState();
}

class _MaTvReplayMineScreenState extends State<MaTvReplayMineScreen> {
  final _client = MaTvReplay();
  ReplayHome? _home;
  bool _loading = true;
  final _followed = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load(markSeen: true));
  }

  Future<void> _load({bool markSeen = false}) async {
    final h = await _client.home();
    // Seen once the « NOUVEAU » marks are on screen: next time, only what
    // aired since.
    if (markSeen) unawaited(_client.setPref(seen: true));
    if (!mounted) return;
    setState(() {
      _home = h;
      _loading = false;
    });
  }

  String _chanName(String chan) {
    for (final c in _home?.channels ?? const <ReplayChannel>[]) {
      if (c.chan == chan) return c.name;
    }
    return chan;
  }

  Widget _start(ReplayHome h) {
    final seen = <String>{};
    final shows = [
      for (final e in h.featured)
        if (seen.add(e.show)) e,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Suis tes émissions en un appui', style: TextStyle(color: _ink, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
          'Ce que les chaînes mettent à la une. Une émission suivie remonte ici à chaque nouvel épisode.',
          style: TextStyle(color: _mute),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < shows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _chip(_chanName(shows[i].chan), bg: const Color(0xFF2A2724)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shows[i].show, style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w700)),
                      Text('à la une · ${shows[i].dayLabel}', style: const TextStyle(color: _mute, fontSize: 13)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(playReplay(context, shows[i])),
                  child: const Text('Regarder'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  autofocus: i == 0,
                  style: _followed.contains(shows[i].show)
                      ? FilledButton.styleFrom(backgroundColor: const Color(0xFF2E5E3E), foregroundColor: const Color(0xFFCFEFD8))
                      : null,
                  onPressed: () async {
                    final on = _followed.contains(shows[i].show);
                    if (await _client.setPref(show: shows[i].show, follow: !on) && mounted) {
                      setState(() => on ? _followed.remove(shows[i].show) : _followed.add(shows[i].show));
                    }
                  },
                  child: Text(_followed.contains(shows[i].show) ? '✓ Suivi' : '+ Suivre'),
                ),
              ],
            ),
          ),
        if (_followed.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => unawaited(_load()), child: const Text('Voir mes émissions')),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = _home;
    final mine = h?.mine ?? const <ReplayItem>[];
    return _ReplayScaffold(
      title: 'Mes émissions',
      subtitle: mine.isNotEmpty
          ? 'Les nouveaux épisodes de ce que tu suis · un appui : ça joue · « Infos » : la fiche'
          : '',
      child: _loading
          ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
          : h == null
          ? const Text('Le replay ne répond pas (Ma TV 3.62 ou plus nécessaire).', style: TextStyle(color: _mute))
          : mine.isEmpty
          ? _start(h)
          : Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                for (var i = 0; i < mine.length; i++)
                  _episodeCard(
                    context,
                    mine[i],
                    autofocus: i == 0,
                    siblings: mine,
                    chanName: _chanName(mine[i].chan),
                    infos: true,
                    afterChange: _load,
                  ),
              ],
            ),
    );
  }
}

/// The page of a channel: last night first, then one row per show (the
/// followed ones first), then day by day.
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
  int _day = 0;

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
      if (_day >= (p?.days.length ?? 0)) _day = 0;
    });
  }

  List<ReplayItem> _all(ReplayChannelPage p) => [for (final s in p.shows) ...s.items];

  Widget _prime(ReplayChannelPage p, ReplayItem prime) {
    final at = prime.aired;
    final hour = at == null ? '' : ' · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final siblings = _all(p);
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth > 700;
        final picture = _episodeCard(context, prime, autofocus: true, width: wide ? 460 : box.maxWidth, siblings: siblings, afterChange: _load);
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${at == null ? 'LA SOIRÉE' : switch (ReplayDay(day: at).label()) { 'Aujourd\u2019hui' => 'CE SOIR', 'Hier' => 'HIER SOIR', final d => '${d.toUpperCase()} SOIR' }}$hour', style: const TextStyle(color: _mute, fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(prime.show.toUpperCase(), style: const TextStyle(color: _ink, fontSize: 26, fontWeight: FontWeight.w900)),
            if (prime.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(prime.description, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 15)),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: () => unawaited(playReplay(context, prime)),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Regarder'),
                ),
                OutlinedButton(
                  onPressed: () => unawaited(showReplaySheet(context, prime, siblings: siblings, afterChange: _load)),
                  child: const Text('Infos'),
                ),
              ],
            ),
          ],
        );
        return wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [picture, const SizedBox(width: 24), Expanded(child: text)])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [picture, const SizedBox(height: 12), text]);
      },
    );
  }

  Widget _days(ReplayChannelPage p) {
    final day = p.days[_day];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rowTitle('Jour par jour'),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: p.days.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => i == _day
                ? FilledButton(onPressed: () {}, child: Text(p.days[i].label()))
                : OutlinedButton(onPressed: () => setState(() => _day = i), child: Text(p.days[i].label())),
          ),
        ),
        const SizedBox(height: 12),
        _episodeRow(context, day.items, afterChange: _load),
      ],
    );
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
                if (prime != null) ...[_prime(p, prime), const SizedBox(height: 28)],
                for (final s in p.shows) ...[
                  _rowTitle(s.show, count: '${s.items.length} épisode${s.items.length > 1 ? 's' : ''}', followed: s.followed),
                  _episodeRow(context, s.items, autofocusFirst: prime == null && s == p.shows.first, afterChange: _load),
                  const SizedBox(height: 18),
                ],
                if (p.days.isNotEmpty) _days(p),
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
