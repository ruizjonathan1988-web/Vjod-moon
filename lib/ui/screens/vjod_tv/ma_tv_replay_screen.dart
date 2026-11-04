// Replay of the channels (VJOD 4.18): « Mes émissions » (the new episodes of
// what this profile follows), the page of a channel (last night, one row per
// show, then day by day), and an episode's sheet. One press plays; « Infos » or a
// long press opens the sheet. The episode plays in VJOD's own player; an
// encrypted one opens the channel's app, last of all.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/vjod/iptv_progress.dart' show IptvWatch;
import '../../../data/services/vjod/ma_tv_replay.dart';
import '../../../data/services/vjod/replay_keep.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/media_card.dart';
import '../../widgets/navigation_layout.dart';
import 'ma_tv_widgets.dart';
import 'ma_tv_player_screen.dart' show MaTvPlayerScreen;
import '../../../data/services/vjod/ma_tv.dart' show MaTvClient, MaTvChannel;

// The palette of the rest of Ma TV.
const _ink = MaTvColors.ink;
const _mute = Color(0xFFB8B4AC);
const _good = MaTvColors.good;
const _live = MaTvColors.live;
const _bg = Color(0xFF0B0B0D);

IptvWatch _watchOf(ReplayItem item) => IptvWatch(
  kind: 'replay',
  id: item.id,
  name: item.show,
  poster: item.image,
);

String _titleOf(ReplayItem item) =>
    item.title.isEmpty || item.title == item.show ? item.show : '${item.show} · ${item.title}';

/// Plays [item] from its best source: the episode in the library when it is
/// there (no ads, kept), else the channel's replay in VJOD, else the IPTV
/// recording of the broadcast (« Passer la pub »), the channel's app last.
/// A replay keeps its place on Ma TV: it comes back in « Reprendre ».
Future<void> playReplay(BuildContext context, ReplayItem item) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(const SnackBar(content: Text('Ouverture…'), duration: Duration(seconds: 3)));
  final lib = await ReplaySources.library(item).timeout(const Duration(seconds: 3), onTimeout: () => null);
  if (!context.mounted) return;
  if (lib != null && lib.episode) {
    messenger?.hideCurrentSnackBar();
    unawaited(context.push(lib.route));
    return;
  }
  if (item.isIptv) {
    // Ma TV 3.66: TF1, M6… come from the provider's catch-up only.
    final iptv = await ReplaySources.iptv(item);
    if (!context.mounted) return;
    messenger?.hideCurrentSnackBar();
    if (iptv == null) {
      messenger?.showSnackBar(const SnackBar(content: Text('Ton fournisseur ne garde plus cette émission.')));
      return;
    }
    unawaited(context.push(Destinations.providerPlayer(url: '$iptv', title: _titleOf(item), watch: _watchOf(item), adSkip: true)));
    return;
  }
  final play = await MaTvReplay().playback(item);
  if (!context.mounted) return;
  if (play.inVjod) {
    messenger?.hideCurrentSnackBar();
    unawaited(context.push(Destinations.providerPlayer(url: play.url!, title: _titleOf(item), watch: _watchOf(item))));
    return;
  }
  final iptv = await ReplaySources.iptv(item);
  if (!context.mounted) return;
  messenger?.hideCurrentSnackBar();
  if (iptv != null) {
    messenger?.showSnackBar(const SnackBar(
      content: Text('Le replay de la chaîne ne se lit pas ici : la diffusion enregistrée par ton fournisseur prend le relais.'),
      duration: Duration(seconds: 4),
    ));
    unawaited(context.push(Destinations.providerPlayer(url: '$iptv', title: _titleOf(item), watch: _watchOf(item), adSkip: true)));
    return;
  }
  await _openApp(context, item, play.reason);
}

Future<void> _openApp(BuildContext context, ReplayItem item, String? reason) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(SnackBar(
    content: Text(reason == 'chiffré'
        ? 'Cet épisode est protégé : il s’ouvre dans l’appli de la chaîne.'
        : 'Lecture impossible ici : ouverture dans l’appli de la chaîne.'),
    duration: const Duration(seconds: 4),
  ));
  final opened = await MaTvReplay.openOfficial(item, tv: PlatformDetection.isTV);
  if (!opened) {
    messenger?.showSnackBar(const SnackBar(content: Text('Ni la vidéo ni l’appli de la chaîne n’ont pu s’ouvrir.')));
  }
}

/// A replay picked up from « Reprendre »: the episode found again on Ma TV,
/// then played from its source (the player goes back to the saved place).
Future<void> resumeReplay(BuildContext context, String id) async {
  final item = await MaTvReplay().item(id);
  if (!context.mounted) return;
  if (item == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Cet épisode n’est plus au replay de la chaîne.')),
    );
    return;
  }
  await playReplay(context, item);
}

/// One source of « Autres sources » chosen by hand.
Future<void> _useSource(BuildContext context, ReplayItem e, ReplaySource s) async {
  switch (s.kind) {
    case 'library' || 'vod':
      unawaited(context.push(s.route!));
    case 'seerr':
      await _keepWithSeerr(context, e, s);
    case 'tracker':
      await _keepFromTrackers(context, e);
    case 'iptv':
      unawaited(context.push(Destinations.providerPlayer(url: '${s.stream}', title: _titleOf(e), watch: _watchOf(e), adSkip: true)));
    case 'app':
      await _openApp(context, e, null);
    default:
      final play = await MaTvReplay().playback(e);
      if (!context.mounted) return;
      if (play.inVjod) {
        unawaited(context.push(Destinations.providerPlayer(url: play.url!, title: _titleOf(e), watch: _watchOf(e))));
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(play.reason == 'chiffré'
              ? 'Le replay de la chaîne est protégé pour cet épisode.'
              : 'Le replay de la chaîne ne répond pas pour cet épisode.'),
        ));
      }
  }
}

/// « Garder dans ma bibliothèque »: the show found in Seerr, its season
/// asked for after a yes; not found, Seerr's search opens on its name.
Future<void> _keepWithSeerr(BuildContext context, ReplayItem e, ReplaySource s) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(const SnackBar(content: Text('Recherche dans Seerr…'), duration: Duration(seconds: 3)));
  final m = await ReplayKeep.seerrMatch(e);
  if (!context.mounted) return;
  messenger?.hideCurrentSnackBar();
  if (m == null) {
    messenger?.showSnackBar(const SnackBar(content: Text('Seerr ne la connaît pas sous ce nom : la recherche s’ouvre.')));
    unawaited(context.push(s.route!));
    return;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Garder « ${m.name} » ?'),
      content: Text('Seerr demande la saison ${m.season} à Sonarr. Elle arrivera dans ta bibliothèque, sans pub.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
        FilledButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Demander')),
      ],
    ),
  );
  if (ok != true) return;
  final said = await ReplayKeep.requestSeerr(m);
  messenger?.showSnackBar(SnackBar(content: Text(said)));
}

/// « Chercher sur mes trackers »: what Prowlarr finds, the most shared
/// first; one press, then a yes, sends it to the download.
Future<void> _keepFromTrackers(BuildContext context, ReplayItem e) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF141210),
    builder: (ctx) => _TrackerSheet(item: e),
  );
}

class _TrackerSheet extends StatefulWidget {
  final ReplayItem item;
  const _TrackerSheet({required this.item});

  @override
  State<_TrackerSheet> createState() => _TrackerSheetState();
}

class _TrackerSheetState extends State<_TrackerSheet> {
  late final TextEditingController _query = TextEditingController(text: ReplayKeep.queryFor(widget.item));
  TrackerSearch? _found;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _busy = true);
    final got = await ReplayKeep.search(_query.text.trim());
    if (!mounted) return;
    setState(() {
      _found = got;
      _busy = false;
    });
  }

  Future<void> _pick(TrackerRelease r) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!(_found?.mayGrab ?? false)) {
      messenger?.showSnackBar(const SnackBar(content: Text('Seul un administrateur de Jellyfin peut lancer un téléchargement.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Télécharger cette version ?'),
        content: Text('${r.title}\n${r.detail}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          FilledButton(autofocus: true, onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Télécharger')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final said = await ReplayKeep.grab(r, show: widget.item.show);
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger?.showSnackBar(SnackBar(content: Text(said)));
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    final h = MediaQuery.sizeOf(context).height * .8;
    return SafeArea(
      child: SizedBox(
        height: h,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 12 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Chercher sur mes trackers',
                  style: TextStyle(color: _ink, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                found != null && !found.mayGrab && found.error.isEmpty
                    ? 'Tu peux regarder ce qui existe ; le téléchargement est réservé aux administrateurs.'
                    : 'Rien ne part sans ton appui. Les plus partagés d’abord.',
                style: const TextStyle(color: MaTvColors.mute, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => unawaited(_search()),
                style: const TextStyle(color: _ink),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: MaTvColors.row,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  suffixIcon: IconButton(
                    tooltip: 'Chercher',
                    icon: const Icon(Icons.search_rounded, color: _ink),
                    onPressed: _busy ? null : () => unawaited(_search()),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _busy
                    ? const Center(child: CircularProgressIndicator())
                    : found == null
                    ? const SizedBox.shrink()
                    : found.error.isNotEmpty
                    ? Center(child: Text(found.error, textAlign: TextAlign.center, style: const TextStyle(color: MaTvColors.mute)))
                    : found.results.isEmpty
                    ? const Center(
                        child: Text('Rien trouvé. Essaie sans le numéro d’épisode, ou avec la date.',
                            textAlign: TextAlign.center, style: TextStyle(color: MaTvColors.mute)),
                      )
                    : ListView.separated(
                        itemCount: found.results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (ctx, i) {
                          final r = found.results[i];
                          return Material(
                            color: MaTvColors.row,
                            borderRadius: BorderRadius.circular(10),
                            child: ListTile(
                              autofocus: i == 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              focusColor: MaTvColors.rowOn,
                              title: Text(r.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w600)),
                              subtitle: Text(r.detail, style: const TextStyle(color: MaTvColors.mute, fontSize: 12)),
                              trailing: Icon(found.mayGrab ? Icons.download_rounded : Icons.lock_outline_rounded,
                                  color: MaTvColors.mute),
                              onTap: () => unawaited(_pick(r)),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
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
  bool chanChip = false,
  bool infos = false,
  VoidCallback? afterChange,
}) {
  void sheet() => unawaited(showReplaySheet(context, e, siblings: siblings, chanName: chanName, afterChange: afterChange));
  final card = MediaCard(
    title: e.show,
    subtitle: '${e.dayLabel}${e.subtitle.isNotEmpty && e.subtitle != e.dayLabel ? ' · ${e.subtitle}' : ''}',
    imageUrl: e.image.isEmpty ? null : e.image,
    width: width,
    aspectRatio: 16 / 9,
    itemType: 'Episode',
    focusColor: _focusColor(),
    autofocus: autofocus,
    overlayOccupiesTopLeft: chanChip && chanName.isNotEmpty,
    imageOverlays: [
      if (chanChip && chanName.isNotEmpty) Positioned(top: 8, left: 8, child: _chip(chanName)),
      if (e.isNew) Positioned(top: 8, right: 8, child: _chip('NOUVEAU', bg: _live, fg: Colors.white)),
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
  String chanName = '',
  VoidCallback? afterChange,
}) async {
  final client = MaTvReplay();
  var followed = e.followed;
  final next = nextEpisode(e, siblings);
  final meta = [chanName, e.dayLabel, if (e.subtitle != e.dayLabel) e.subtitle].where((s) => s.isNotEmpty).join(' · ');
  final sources = ReplaySources.all(e, chanName: chanName);
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.description.isNotEmpty)
                  Text(e.description, maxLines: 7, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 15)),
                const SizedBox(height: 16),
                const Text('AUTRES SOURCES', style: TextStyle(color: _mute, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w800)),
                const Text('La meilleure est déjà choisie. Les autres, au cas où.', style: TextStyle(color: _mute, fontSize: 13)),
                const SizedBox(height: 6),
                FutureBuilder<List<ReplaySource>>(
                  future: sources,
                  builder: (_, snap) {
                    final list = snap.data;
                    if (list == null) {
                      return const Padding(padding: EdgeInsets.all(10), child: LinearProgressIndicator());
                    }
                    return Column(
                      children: [
                        for (final src in list)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Row(
                              children: [
                                Flexible(child: Text(src.name, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700))),
                                if (src.tag.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(src.tag,
                                      style: TextStyle(
                                        color: src.tag == 'avec pub' ? MaTvColors.accent : _mute,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      )),
                                ],
                              ],
                            ),
                            subtitle: Text(src.detail, style: const TextStyle(color: _mute, fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right_rounded, color: _mute),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              unawaited(_useSource(context, e, src));
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
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
        const Text('✓ Suivi', style: TextStyle(color: _good, fontWeight: FontWeight.w700)),
      ],
    ],
  ),
);

Widget _episodeRow(BuildContext context, List<ReplayItem> items, {bool autofocusFirst = false, String chanName = '', VoidCallback? afterChange}) => SizedBox(
  height: 230,
  child: ListView.separated(
    scrollDirection: Axis.horizontal,
    itemCount: items.length,
    separatorBuilder: (_, _) => const SizedBox(width: 16),
    itemBuilder: (context, i) =>
        _episodeCard(context, items[i], autofocus: autofocusFirst && i == 0, siblings: items, chanName: chanName, afterChange: afterChange),
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
    unawaited(_client.homeSaved().then((h) {
      if (h != null && mounted && _loading) {
        setState(() {
          _home = h;
          _loading = false;
        });
      }
    }));
    unawaited(_load(markSeen: true));
  }

  Future<void> _load({bool markSeen = false}) async {
    final h = await _client.home() ?? _home;
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

  static const _weekdays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

  /// « vu en direct lundi », else « à la une ».
  String _why(ReplayItem e) {
    final at = e.liveAt;
    if (at == null) return 'à la une · ${e.dayLabel}';
    final ago = DateTime.now().difference(DateTime(at.year, at.month, at.day)).inDays;
    return 'vu en direct ${ago <= 0 ? 'aujourd\u2019hui' : ago == 1 ? 'hier' : _weekdays[at.weekday - 1]}';
  }

  Widget _start(ReplayHome h) {
    final seen = <String>{};
    final shows = [
      for (final e in [...h.suggest, ...h.featured])
        if (seen.add(e.show)) e,
    ].take(14).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Suis tes émissions en un appui', style: TextStyle(color: _ink, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          h.suggest.isNotEmpty
              ? 'Ce que tu as regardé en direct ces derniers jours. Une émission suivie remonte ici à chaque nouvel épisode.'
              : 'Ce que les chaînes mettent à la une. Une émission suivie remonte ici à chaque nouvel épisode.',
          style: const TextStyle(color: _mute),
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
                      Text(_why(shows[i]), style: const TextStyle(color: _mute, fontSize: 13)),
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
                    chanChip: true,
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
    unawaited(_client.channelSaved(widget.chan).then((p) {
      if (p != null && mounted && _loading) {
        setState(() {
          _page = p;
          _loading = false;
        });
      }
    }));
    unawaited(_load());
  }

  Future<void> _load() async {
    final p = await _client.channel(widget.chan) ?? _page;
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
        final picture = _episodeCard(context, prime,
            autofocus: true, width: wide ? 460 : box.maxWidth, siblings: siblings, chanName: widget.name, afterChange: _load);
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
                  onPressed: () => unawaited(showReplaySheet(context, prime, siblings: siblings, chanName: widget.name, afterChange: _load)),
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
        _episodeRow(context, day.items, chanName: widget.name, afterChange: _load),
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
                  _episodeRow(context, s.items,
                      autofocusFirst: prime == null && s == p.shows.first, chanName: widget.name, afterChange: _load),
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

/// VJOD 4.31: the « Replay » tab, laid out like the France TV app: the
/// « une » in big with its category, « Notre sélection », the channels live
/// now, « À la une » numbered, the categories, then « Mes émissions » and a
/// row per category in portrait pictures with « Nouveau » marks, and « Nos
/// chaînes » at the bottom. One video per show.
class MaTvReplayPageScreen extends StatefulWidget {
  const MaTvReplayPageScreen({super.key});

  @override
  State<MaTvReplayPageScreen> createState() => _MaTvReplayPageScreenState();
}

/// The colour of a category's pill, as in the France TV app.
Color _genreColor(String g) => switch (g) {
  'Séries & fictions' => const Color(0xFF8A4B57),
  'Documentaires' => const Color(0xFF7A8236),
  'Cinéma' => const Color(0xFFB03A3A),
  'Société' => const Color(0xFF6E5A52),
  'Info' => const Color(0xFF6B6B6B),
  'Arts & spectacles' => const Color(0xFFC0602A),
  'Sport' => const Color(0xFF2B3FD0),
  'Divertissement' => const Color(0xFF9E3B7A),
  'Enfants' => const Color(0xFF7A3FC0),
  _ => const Color(0xFF555555),
};

Widget _badgeChip(String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
  child: Text(text, style: const TextStyle(color: Color(0xFF141210), fontSize: 12, fontWeight: FontWeight.w800)),
);

class _MaTvReplayPageScreenState extends State<MaTvReplayPageScreen> {
  final _client = MaTvReplay();
  ReplayPage? _page;
  bool _loading = true;
  Map<String, String> _logos = const {};
  List<MaTvChannel> _liveChans = const [];
  int _hero = 0;
  Timer? _heroTimer;

  bool get _kids {
    final getIt = GetIt.instance;
    return getIt.isRegistered<UserPreferences>() && getIt<UserPreferences>().get(UserPreferences.kidsModeEnabled);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_client.pageSaved(kids: _kids).then((p) {
      if (p != null && mounted && _loading) setState(() => _page = p);
    }));
    unawaited(_load());
    _heroTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      final n = _page?.hero.length ?? 0;
      if (n > 1 && mounted) setState(() => _hero = (_hero + 1) % n);
    });
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await _client.page(kids: _kids) ?? _page;
    if (!mounted) return;
    setState(() {
      _page = p;
      _loading = false;
    });
    if (p == null || p.channels.isEmpty) return;
    final logos = await replayLogos(p.channels);
    if (mounted) setState(() => _logos = logos);
    // « En direct »: the replay's channels, live in Ma TV now.
    try {
      final all = await MaTvClient().allChannels().timeout(const Duration(seconds: 8));
      if (all == null || !mounted) return;
      final want = {for (final c in p.channels) replayNameKey(c.name)};
      final seen = <String>{};
      setState(() => _liveChans = [
            for (final c in all)
              if (want.contains(replayNameKey(c.name)) && seen.add(replayNameKey(c.name))) c,
          ]);
    } catch (_) {}
  }

  String _chanName(String chan) {
    for (final c in _page?.channels ?? const <ReplayChannel>[]) {
      if (c.chan == chan) return c.name;
    }
    return chan;
  }

  void _openChan(ReplayChannel c) {
    unawaited(ReplayOrder.noteOpen(c.chan));
    unawaited(Navigator.of(context, rootNavigator: true)
        .push(maTvRoute<void>((_) => MaTvReplayChannelScreen(chan: c.chan, name: c.name))));
  }

  void _openCategory(String g) => unawaited(Navigator.of(context, rootNavigator: true)
      .push(maTvRoute<void>((_) => _ReplayCategoryScreen(genre: g, kids: _kids, chanName: _chanName))));

  Widget _section(String title, Widget child, {bool dot = false}) => Padding(
    padding: const EdgeInsets.only(top: 30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          if (dot) ...[
            Container(width: 12, height: 12, decoration: const BoxDecoration(color: _live, shape: BoxShape.circle)),
            const SizedBox(width: 10),
          ],
          Text(title, style: const TextStyle(color: _ink, fontSize: 22, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );

  Widget _heroCard(ReplayItem e) {
    final w = MediaQuery.sizeOf(context).width;
    final h = (w * (PlatformDetection.useMobileUi ? .62 : .36)).clamp(220.0, 460.0);
    final words = e.description.split(RegExp(r'(?<=[.!?])\s')).first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (e.image.isNotEmpty) Image.network(e.image, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF24252B))),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xF20B0B0D), Color(0x000B0B0D)],
                  stops: [0, .75],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(children: [
                    _chip(_chanName(e.chan)),
                    if (e.genre.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xCC141210),
                          border: Border.all(color: _genreColor(e.genre)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(e.genre, style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 10),
                  Text(e.show, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _ink, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1)),
                  if (words.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(words, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 16),
                  Row(children: [
                    FilledButton(
                      autofocus: true,
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF141210),
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16), shape: const StadiumBorder()),
                      onPressed: () => unawaited(playReplay(context, e)),
                      child: const Text('Regarder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      tooltip: 'Infos',
                      onPressed: () => unawaited(showReplaySheet(context, e, chanName: _chanName(e.chan), afterChange: _load)),
                      icon: const Icon(Icons.info_outline_rounded),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A tile of the page: [portrait] pictures for the categories, the
  /// channel's mark on the picture, « Nouveau » top right.
  Widget _tile(ReplayItem e, {bool portrait = false, double width = 260, int? rank, String? words}) {
    final img = portrait && e.poster.isNotEmpty ? e.poster : e.image;
    final ratio = portrait && e.poster.isNotEmpty ? 3 / 4 : 16 / 9;
    final card = MediaCard(
      title: e.show,
      subtitle: words ?? (e.subtitle.isNotEmpty ? e.subtitle : e.dayLabel),
      imageUrl: img.isEmpty ? null : img,
      width: width,
      aspectRatio: ratio,
      itemType: 'Episode',
      focusColor: _focusColor(),
      overlayOccupiesTopLeft: true,
      imageOverlays: [
        Positioned(top: 8, left: 8, child: _chip(_chanName(e.chan))),
        if (e.badge.isNotEmpty) Positioned(top: 8, right: 8, child: _badgeChip(e.badge))
        else if (e.isNew) Positioned(top: 8, right: 8, child: _chip('NOUVEAU', bg: _live, fg: Colors.white)),
      ],
      onTap: () => unawaited(playReplay(context, e)),
      onLongPress: () => unawaited(showReplaySheet(context, e, chanName: _chanName(e.chan), afterChange: _load)),
    );
    if (rank == null) return card;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$rank', style: TextStyle(
          fontSize: 96, height: 1, fontWeight: FontWeight.w900,
          foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = _mute,
        )),
        card,
      ],
    );
  }

  Widget _strip(List<ReplayItem> items, {bool portrait = false, bool numbered = false, double width = 260, bool words = false}) {
    final ratio = portrait && items.any((e) => e.poster.isNotEmpty) ? 3 / 4 : 16 / 9;
    final h = width / ratio + (words ? 90 : 64);
    return SizedBox(
      height: h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, i) => _tile(items[i],
            portrait: portrait, width: width, rank: numbered ? i + 1 : null,
            words: words ? items[i].description.split(RegExp(r'(?<=[.!?])\s')).first : null),
      ),
    );
  }

  Widget _liveRow() => SizedBox(
    height: 170,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _liveChans.length,
      separatorBuilder: (_, _) => const SizedBox(width: 16),
      itemBuilder: (context, i) {
        final c = _liveChans[i];
        final now = c.now;
        final progress = now == null ? 0.0 : now.progressAt(DateTime.now());
        return SizedBox(
          width: 260,
          child: Material(
            color: const Color(0xFF1B1C21),
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              focusColor: MaTvColors.rowOn,
              onTap: () => unawaited(Navigator.of(context, rootNavigator: true).push<void>(maTvRoute(
                (_) => MaTvPlayerScreen(channels: _liveChans, startIndex: i, categoryId: 'replay', categoryLabel: 'En direct'),
              ))),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      MaTvLogo(url: c.logo, name: c.name, size: 30),
                      const Spacer(),
                      _chip('● Direct', bg: _live, fg: Colors.white),
                    ]),
                    const Spacer(),
                    Text(now?.title ?? c.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    MaTvProgress(value: progress),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _categories(List<String> genres) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      for (final g in genres)
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: _genreColor(g).withValues(alpha: .25),
            side: BorderSide(color: _genreColor(g), width: 2),
            foregroundColor: _ink,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
          ),
          onPressed: () => _openCategory(g),
          child: Text(g, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
    ],
  );

  Widget _channels(ReplayPage p) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      for (final c in p.channels)
        SizedBox(
          width: 170,
          height: 72,
          child: Material(
            color: const Color(0xFF24252B),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              focusColor: MaTvColors.rowOn,
              onTap: () => _openChan(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Center(
                  child: (_logos[c.chan] ?? '').isEmpty
                      ? Text(c.name, textAlign: TextAlign.center, style: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w800))
                      : Image.network(_logos[c.chan]!, fit: BoxFit.contain, semanticLabel: c.name,
                          errorBuilder: (_, _, _) => Text(c.name, style: const TextStyle(color: _ink, fontWeight: FontWeight.w800))),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final p = _page;
    final isMobile = PlatformDetection.useMobileUi;
    final side = isMobile ? 16.0 : 48.0;
    final top = MediaQuery.paddingOf(context).top + (isMobile ? 64.0 : 96.0);
    final Widget body;
    if (p == null) {
      body = Center(
        child: _loading
            ? const CircularProgressIndicator()
            : const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Le replay arrive avec Ma TV 3.70 sur la seedbox.', textAlign: TextAlign.center, style: TextStyle(color: _mute)),
              ),
      );
    } else {
      final hero = p.hero.isEmpty ? null : p.hero[_hero % p.hero.length];
      final top10 = p.rows.where((r) => r.kind == 'top').firstOrNull;
      final rest = [for (final r in p.rows) if (r.kind != 'top' && r.items.isNotEmpty) r];
      final mine = rest.where((r) => r.id == 'mine' || r.id == 'live').toList();
      final others = rest.where((r) => r.id != 'mine' && r.id != 'live').toList();
      body = RefreshIndicator(
        onRefresh: _load,
        child: FocusTraversalGroup(
          child: ListView(
            padding: EdgeInsets.fromLTRB(side, top, side, 48),
            children: [
              if (hero != null) _heroCard(hero),
              for (final r in mine) _section(r.title, _strip(r.items)),
              if (p.selection.isNotEmpty) _section('Notre sélection', _strip(p.selection, width: 320, words: true)),
              if (_liveChans.isNotEmpty) _section('En direct', _liveRow(), dot: true),
              if (top10 != null && top10.items.isNotEmpty) _section('À la une', _strip(top10.items, numbered: true, width: 220)),
              if (p.categories.isNotEmpty) _section('Catégories', _categories(p.categories)),
              for (final r in others)
                _section(
                  r.kind == 'poster' ? _rowLabel(r.genre.isNotEmpty ? r.genre : r.title) : r.title,
                  _strip(r.items, portrait: r.kind == 'poster', width: r.kind == 'poster' ? 200 : 260),
                ),
              if (p.channels.isNotEmpty) _section('Nos chaînes', _channels(p)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: _bg,
      body: NavigationLayout(activeRoute: Destinations.replay, child: body),
    );
  }

  /// The France TV app's row names.
  static String _rowLabel(String g) => switch (g) {
    'Séries & fictions' => 'Les séries à ne pas rater',
    'Documentaires' => 'Le meilleur du documentaire',
    'Cinéma' => 'Films et téléfilms',
    'Enfants' => 'Pour les enfants',
    'Société' => 'Magazines et enquêtes',
    'Arts & spectacles' => 'Arts et spectacles',
    _ => g,
  };
}

/// Every show of a category, in a grid.
class _ReplayCategoryScreen extends StatefulWidget {
  final String genre;
  final bool kids;
  final String Function(String chan) chanName;
  const _ReplayCategoryScreen({required this.genre, required this.kids, required this.chanName});

  @override
  State<_ReplayCategoryScreen> createState() => _ReplayCategoryScreenState();
}

class _ReplayCategoryScreenState extends State<_ReplayCategoryScreen> {
  List<ReplayItem>? _items;

  @override
  void initState() {
    super.initState();
    unawaited(MaTvReplay().category(widget.genre, kids: widget.kids).then((l) {
      if (mounted) setState(() => _items = l);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return _ReplayScaffold(
      title: widget.genre,
      subtitle: items == null ? '' : '${items.length} émissions',
      child: items == null
          ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          : Wrap(
              spacing: 16,
              runSpacing: 20,
              children: [
                for (var i = 0; i < items.length; i++)
                  _episodeCard(context, items[i], autofocus: i == 0, chanName: widget.chanName(items[i].chan), chanChip: true),
              ],
            ),
    );
  }
}
