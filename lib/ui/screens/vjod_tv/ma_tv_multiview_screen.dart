// Multiview (VJOD 4.7): two live channels side by side (four on a computer),
// opened from the player's menu. Only the tile picked is heard. OK on a tile:
// full screen, another channel, or remove it. Each tile is its own player,
// stopped and freed when the tile is emptied or the screen closed.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/services/vjod/ma_tv.dart';
import '../../../util/vjod_log.dart';
import 'ma_tv_search_screen.dart';
import 'ma_tv_widgets.dart';
import 'tv_engine.dart';

class _Tile {
  MaTvChannel? channel;
  TvEngine? engine;
  bool picture = false;
  String? problem;
  Timer? watchdog;
  final subs = <StreamSubscription<Object?>>[];
}

class MaTvMultiviewScreen extends StatefulWidget {
  /// The channels to pick from (the player's list), the first one shown.
  final List<MaTvChannel> channels;
  final MaTvChannel first;
  final int tiles;

  const MaTvMultiviewScreen({super.key, required this.channels, required this.first, this.tiles = 2});

  @override
  State<MaTvMultiviewScreen> createState() => _MaTvMultiviewScreenState();
}

class _MaTvMultiviewScreenState extends State<MaTvMultiviewScreen> {
  final _client = MaTvClient();
  late final List<_Tile> _tiles = [for (var i = 0; i < widget.tiles.clamp(2, 4); i++) _Tile()];
  int _heard = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_put(0, widget.first));
  }

  @override
  void dispose() {
    for (final t in _tiles) {
      unawaited(_free(t));
    }
    super.dispose();
  }

  TvEngine _newEngine() => WebTvEngine.wanted ? WebTvEngine() : MpvTvEngine();

  Future<void> _free(_Tile t) async {
    t.watchdog?.cancel();
    for (final s in t.subs) {
      await s.cancel();
    }
    t.subs.clear();
    final e = t.engine;
    t.engine = null;
    if (e != null) {
      try {
        await e.dispose();
      } catch (err) {
        vjodLogError('Multiview : arrêt d’une case', err);
      }
    }
  }

  Future<void> _put(int i, MaTvChannel ch) async {
    final t = _tiles[i];
    await _free(t);
    final uri = _client.liveUri(ch);
    if (!mounted || uri == null) return;
    final e = _newEngine();
    setState(() {
      t.channel = ch;
      t.engine = e;
      t.picture = false;
      t.problem = null;
    });
    t.subs.add(e.firstFrame.listen((_) {
      if (mounted) setState(() => t.picture = true);
    }));
    t.subs.add(e.errors.listen((_) {
      if (mounted && !t.picture) setState(() => t.problem = _refused);
    }));
    // No picture after 30 s: most often the provider refusing one more channel.
    t.watchdog = Timer(const Duration(seconds: 30), () {
      if (mounted && !t.picture) setState(() => t.problem = _refused);
    });
    await WidgetsBinding.instance.endOfFrame;
    try {
      await e.setMuted(i != _heard);
      await e.open(uri.toString());
    } catch (err) {
      vjodLogError('Multiview : ouverture', err);
      if (mounted) setState(() => t.problem = _refused);
    }
  }

  static const _refused =
      'Pas d’image. Le fournisseur refuse peut-être une chaîne de plus : retire une case ou réessaie.';

  void _hear(int i) {
    if (i == _heard) return;
    setState(() => _heard = i);
    for (var k = 0; k < _tiles.length; k++) {
      unawaited(_tiles[k].engine?.setMuted(k != i));
    }
  }

  Future<void> _pick(int i) async {
    final ch = await showDialog<Object>(
      context: context,
      builder: (context) => _ChannelPicker(channels: widget.channels, exclude: {
        for (final t in _tiles)
          if (t.channel != null) t.channel!.id,
      }),
    );
    if (!mounted) return;
    if (ch == _ChannelPicker.search) {
      final found = await Navigator.of(context).push<({List<MaTvChannel> channels, int index})>(
        maTvRoute((_) => const MaTvSearchScreen()),
      );
      if (!mounted || found == null || found.channels.isEmpty) return;
      await _put(i, found.channels[found.index.clamp(0, found.channels.length - 1)]);
    } else if (ch is MaTvChannel) {
      await _put(i, ch);
    }
  }

  Future<void> _tileMenu(int i) async {
    final t = _tiles[i];
    if (t.channel == null) return _pick(i);
    final what = await showDialog<String>(
      context: context,
      builder: (context) => _Menu(title: t.channel!.name, items: const [
        ('full', Icons.fullscreen_rounded, 'Plein écran'),
        ('change', Icons.swap_horiz_rounded, 'Changer de chaîne'),
        ('remove', Icons.close_rounded, 'Retirer'),
      ]),
    );
    if (!mounted || what == null) return;
    switch (what) {
      case 'full':
        Navigator.of(context).pop<MaTvChannel>(t.channel);
      case 'change':
        await _pick(i);
      case 'remove':
        await _free(t);
        if (mounted) {
          setState(() {
            t.channel = null;
            t.problem = null;
          });
        }
    }
  }

  Widget _tileView(int i) {
    final t = _tiles[i];
    final heard = i == _heard;
    return InkWell(
      autofocus: i == 0,
      onFocusChange: (f) {
        if (f) _hear(i);
      },
      onTap: () => unawaited(_tileMenu(i)),
      focusColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: heard ? MaTvColors.ink : const Color(0xFF26262A), width: heard ? 3 : 1),
        ),
        child: Stack(
          children: [
            if (t.engine != null) Positioned.fill(child: KeyedSubtree(key: ObjectKey(t.engine), child: t.engine!.view())),
            if (t.channel == null)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: MaTvColors.mute, size: 40),
                    SizedBox(height: 6),
                    Text('OK pour choisir une chaîne', style: TextStyle(color: MaTvColors.mute, fontSize: 16)),
                  ],
                ),
              )
            else if (!t.picture && t.problem == null)
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            if (t.problem != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(t.problem!,
                      textAlign: TextAlign.center, style: const TextStyle(color: MaTvColors.ink, fontSize: 15)),
                ),
              ),
            if (t.channel != null)
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: MaTvColors.panel, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(heard ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                          size: 16, color: heard ? MaTvColors.ink : MaTvColors.mute),
                      const SizedBox(width: 6),
                      Text('${t.channel!.number}  ${t.channel!.name}',
                          style: const TextStyle(color: MaTvColors.ink, fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = _tiles.length;
    final Widget grid = n <= 2
        ? Row(children: [for (var i = 0; i < n; i++) Expanded(child: _tileView(i))])
        : Column(
            children: [
              Expanded(child: Row(children: [Expanded(child: _tileView(0)), Expanded(child: _tileView(1))])),
              Expanded(child: Row(children: [Expanded(child: _tileView(2)), Expanded(child: _tileView(3))])),
            ],
          );
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Center(child: AspectRatio(aspectRatio: n <= 2 ? 32 / 9 : 16 / 9, child: grid))),
          const Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: Center(
              child: Text('Le son suit la case choisie · OK : plein écran, changer, retirer · Retour : quitter',
                  style: TextStyle(color: MaTvColors.faint, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelPicker extends StatelessWidget {
  static const search = 'search';
  final List<MaTvChannel> channels;
  final Set<String> exclude;

  const _ChannelPicker({required this.channels, required this.exclude});

  @override
  Widget build(BuildContext context) {
    final list = [for (final c in channels) if (!exclude.contains(c.id)) c];
    return Dialog(
      backgroundColor: const Color(0xFF17171A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 6, bottom: 10),
                child: Text('Choisir une chaîne',
                    style: TextStyle(color: MaTvColors.ink, fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length + 1,
                  itemBuilder: (context, i) => i == 0
                      ? _MenuRow(
                          autofocus: true,
                          icon: Icons.search_rounded,
                          label: 'Rechercher une chaîne…',
                          onTap: () => Navigator.of(context).pop(search),
                        )
                      : _MenuRow(
                          icon: Icons.live_tv_rounded,
                          label: '${list[i - 1].number}  ${list[i - 1].name}',
                          onTap: () => Navigator.of(context).pop(list[i - 1]),
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

class _Menu extends StatelessWidget {
  final String title;
  final List<(String, IconData, String)> items;

  const _Menu({required this.title, required this.items});

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: const Color(0xFF17171A),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 10),
              child: Text(title, style: const TextStyle(color: MaTvColors.ink, fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            for (var i = 0; i < items.length; i++)
              _MenuRow(
                autofocus: i == 0,
                icon: items[i].$2,
                label: items[i].$3,
                onTap: () => Navigator.of(context).pop(items[i].$1),
              ),
          ],
        ),
      ),
    ),
  );
}

class _MenuRow extends StatefulWidget {
  final bool autofocus;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuRow({required this.icon, required this.label, required this.onTap, this.autofocus = false});

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _on = false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: InkWell(
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      onFocusChange: (f) => setState(() => _on = f),
      focusColor: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _on ? MaTvColors.rowOn : MaTvColors.row,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _on ? MaTvColors.ink : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            Icon(widget.icon, size: 21, color: MaTvColors.ink),
            const SizedBox(width: 12),
            Expanded(
              child: Text(widget.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MaTvColors.ink, fontSize: 16)),
            ),
          ],
        ),
      ),
    ),
  );
}
