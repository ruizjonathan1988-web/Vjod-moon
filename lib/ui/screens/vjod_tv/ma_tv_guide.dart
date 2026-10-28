// Ma TV's programme grid, like a TV box: channels down the side, two and a
// half hours across, the programme under the cursor described at the top.
// UP / DOWN change channel, LEFT / RIGHT move from programme to programme
// (the hours follow), OK watches: live for what's on, the replay for what's
// past when the provider keeps it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/services/vjod/ma_tv.dart';
import '../../../util/focus/dpad_keys.dart';
import 'ma_tv_widgets.dart';

const _rowHeight = 62.0;
const _channelWidth = 230.0;
const _span = Duration(minutes: 150);

DateTime maTvHalfHour(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute < 30 ? 0 : 30);

/// What the grid hands back when a programme is chosen.
class MaTvGuidePick {
  final int index;
  final MaTvProgram? replay;

  const MaTvGuidePick(this.index, {this.replay});
}

class MaTvGuideScreen extends StatefulWidget {
  final List<MaTvChannel> channels;
  final int startIndex;
  final String categoryLabel;

  const MaTvGuideScreen({super.key, required this.channels, required this.startIndex, this.categoryLabel = ''});

  @override
  State<MaTvGuideScreen> createState() => _MaTvGuideScreenState();
}

class _MaTvGuideScreenState extends State<MaTvGuideScreen> {
  final _client = MaTvClient();
  final _focus = FocusNode(debugLabel: 'MaTvGuide');
  final _rows = ScrollController();

  late int _row;
  late DateTime _win;
  late DateTime _cursor;
  DateTime _now = DateTime.now();
  final Map<String, List<MaTvProgram>> _progs = {};
  DateTime? _fetchedFrom;
  DateTime? _fetchedTo;
  final Set<String> _asked = {};
  Timer? _clock;
  Timer? _fetchTimer;
  String? _toast;
  Timer? _toastTimer;
  Set<String> _favorites = {};

  @override
  void initState() {
    super.initState();
    _row = widget.startIndex.clamp(0, widget.channels.isEmpty ? 0 : widget.channels.length - 1);
    _win = maTvHalfHour(_now);
    _cursor = _now;
    _favorites = MaTvMemory.favorites.toSet();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToRow());
    unawaited(_fetch());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _fetchTimer?.cancel();
    _toastTimer?.cancel();
    _focus.dispose();
    _rows.dispose();
    super.dispose();
  }

  List<MaTvChannel> get _chans => widget.channels;

  /// Programmes of the rows around the cursor, for a few hours around the
  /// window, fetched in batches; the rest comes as the viewer moves.
  Future<void> _fetch() async {
    if (_chans.isEmpty) return;
    final from = _win.subtract(const Duration(hours: 2));
    final to = _win.add(const Duration(hours: 6));
    if (_fetchedFrom == null || _win.isBefore(_fetchedFrom!.add(const Duration(minutes: 30))) ||
        _win.add(_span).isAfter(_fetchedTo!)) {
      _asked.clear();
      _fetchedFrom = from;
      _fetchedTo = to;
    }
    final lo = (_row - 12).clamp(0, _chans.length - 1);
    final hi = (_row + 24).clamp(0, _chans.length - 1);
    final ids = [for (var i = lo; i <= hi; i++) if (!_asked.contains(_chans[i].id)) _chans[i].id];
    if (ids.isEmpty) return;
    _asked.addAll(ids);
    final got = await _client.programs(ids, _fetchedFrom!, _fetchedTo!);
    if (!mounted || got == null) return;
    setState(() => _progs.addAll(got));
  }

  void _scheduleFetch() {
    _fetchTimer?.cancel();
    _fetchTimer = Timer(const Duration(milliseconds: 200), () => unawaited(_fetch()));
  }

  void _scrollToRow() {
    if (!_rows.hasClients) return;
    final view = _rows.position.viewportDimension;
    final top = _row * _rowHeight;
    var target = _rows.offset;
    if (top < _rows.offset + _rowHeight) target = top - _rowHeight;
    if (top + _rowHeight > _rows.offset + view - _rowHeight) target = top + 2 * _rowHeight - view;
    _rows.jumpTo(target.clamp(0.0, _rows.position.maxScrollExtent));
  }

  List<MaTvProgram> _rowPrograms(int i) {
    final ch = _chans[i];
    final list = _progs[ch.id];
    if (list != null && list.isNotEmpty) return list;
    return [if (ch.now != null) ch.now!, if (ch.next != null) ch.next!];
  }

  MaTvProgram? _selected() {
    if (_chans.isEmpty) return null;
    for (final p in _rowPrograms(_row)) {
      if (!_cursor.isBefore(p.start) && _cursor.isBefore(p.end)) return p;
    }
    return null;
  }

  /// How far back the hours may go: the replay for channels that keep it,
  /// an hour otherwise.
  DateTime get _earliest {
    final days = _chans.isEmpty ? 0 : _chans[_row].replayDays;
    final back = days > 0 ? Duration(days: days.clamp(1, 7)) : const Duration(hours: 1);
    return maTvHalfHour(_now.subtract(back));
  }

  void _follow() {
    while (_cursor.isBefore(_win)) {
      _win = _win.subtract(const Duration(minutes: 30));
    }
    while (!_cursor.isBefore(_win.add(_span - const Duration(minutes: 20)))) {
      _win = _win.add(const Duration(minutes: 30));
    }
    if (_win.isBefore(_earliest)) _win = _earliest;
  }

  void _moveTime(int d) {
    final progs = _rowPrograms(_row);
    final sel = _selected();
    DateTime next;
    if (d > 0) {
      final after = progs.where((p) => !p.start.isBefore(sel?.end ?? _cursor.add(const Duration(minutes: 1))));
      next = after.isEmpty ? _cursor.add(const Duration(minutes: 30)) : after.first.start;
    } else {
      final before = progs.where((p) => !p.end.isAfter(sel?.start ?? _cursor)).toList();
      next = before.isEmpty ? _cursor.subtract(const Duration(minutes: 30)) : before.last.start;
    }
    if (next.isBefore(_earliest)) next = _earliest;
    if (next.isAfter(_now.add(const Duration(days: 3)))) return;
    // A programme that started before the window: keep the cursor inside.
    setState(() {
      _cursor = next.isBefore(_win) && d > 0 ? _win : next;
      _follow();
    });
    _scheduleFetch();
  }

  void _moveRow(int d) {
    if (_chans.isEmpty) return;
    setState(() {
      _row = (_row + d).clamp(0, _chans.length - 1);
      if (_win.isBefore(_earliest)) _win = _earliest;
      if (_cursor.isBefore(_earliest)) _cursor = _earliest;
    });
    _scrollToRow();
    _scheduleFetch();
  }

  void _say(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _choose() {
    if (_chans.isEmpty) return;
    final ch = _chans[_row];
    final p = _selected();
    final now = DateTime.now();
    if (p == null || p.isOnAt(now)) {
      Navigator.of(context).pop(MaTvGuidePick(_row));
      return;
    }
    if (p.end.isBefore(now) || p.end.isAtSameMomentAs(now)) {
      if (ch.replayDays > 0) {
        Navigator.of(context).pop(MaTvGuidePick(_row, replay: p));
      } else {
        _say('Pas de replay pour ${ch.name}');
      }
      return;
    }
    _say('${p.title} commence à ${maTvTime(p.start)}');
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key.isUpKey) {
      _moveRow(-1);
    } else if (key.isDownKey) {
      _moveRow(1);
    } else if (key.pageDirection != 0) {
      _moveRow(key.pageDirection * 8);
    } else if (key.isLeftKey) {
      _moveTime(-1);
    } else if (key.isRightKey) {
      _moveTime(1);
    } else if (key.isSelectKey && event is KeyDownEvent) {
      _choose();
    } else if (key.isContextMenuKey && _chans.isNotEmpty) {
      final ch = _chans[_row];
      unawaited(MaTvMemory.toggleFavorite(ch.id).then((on) {
        if (!mounted) return;
        setState(() => _favorites = MaTvMemory.favorites.toSet());
        _say(on ? '${ch.name} ajoutée aux favoris' : '${ch.name} retirée des favoris');
      }));
    } else if (key == LogicalKeyboardKey.home) {
      setState(() {
        _cursor = DateTime.now();
        _win = maTvHalfHour(_cursor);
      });
      _scheduleFetch();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: MaTvGuideView(
            channels: _chans,
            programs: {for (var i = 0; i < _chans.length; i++) _chans[i].id: _rowPrograms(i)},
            row: _row,
            cursor: _cursor,
            windowStart: _win,
            now: _now,
            categoryLabel: widget.categoryLabel,
            favorites: _favorites,
            controller: _rows,
            toast: _toast,
            onTapProgram: (row, p) {
              setState(() {
                _row = row;
                _cursor = p.start.isBefore(_win) ? _win : p.start;
              });
              _choose();
            },
          ),
        ),
      ),
    );
  }
}

/// The grid itself, drawn from plain data.
class MaTvGuideView extends StatelessWidget {
  final List<MaTvChannel> channels;
  final Map<String, List<MaTvProgram>> programs;
  final int row;
  final DateTime cursor;
  final DateTime windowStart;
  final DateTime now;
  final String categoryLabel;
  final Set<String> favorites;
  final ScrollController? controller;
  final String? toast;
  final void Function(int row, MaTvProgram program)? onTapProgram;

  const MaTvGuideView({
    super.key,
    required this.channels,
    required this.programs,
    required this.row,
    required this.cursor,
    required this.windowStart,
    required this.now,
    this.categoryLabel = '',
    this.favorites = const {},
    this.controller,
    this.toast,
    this.onTapProgram,
  });

  MaTvProgram? get _selected {
    if (channels.isEmpty) return null;
    for (final p in programs[channels[row.clamp(0, channels.length - 1)].id] ?? const <MaTvProgram>[]) {
      if (!cursor.isBefore(p.start) && cursor.isBefore(p.end)) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    final ch = channels.isEmpty ? null : channels[row.clamp(0, channels.length - 1)];
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _info(ch, sel),
            _timeline(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final width = box.maxWidth - _channelWidth - 28;
                  final ppm = width / _span.inMinutes;
                  final nowX = now.difference(windowStart).inSeconds / 60 * ppm;
                  return Stack(
                    children: [
                      ListView.builder(
                        controller: controller,
                        itemCount: channels.length,
                        itemExtent: _rowHeight,
                        padding: const EdgeInsets.only(left: 28, bottom: 18),
                        itemBuilder: (context, i) => _row(i, width, ppm, sel),
                      ),
                      if (nowX >= 0 && nowX <= width)
                        Positioned(
                          left: 28 + _channelWidth + nowX,
                          top: 0,
                          bottom: 0,
                          child: const IgnorePointer(child: SizedBox(width: 2, child: ColoredBox(color: MaTvColors.live))),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        if (toast != null)
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(color: MaTvColors.panel, borderRadius: BorderRadius.circular(22)),
                child: Text(toast!, style: const TextStyle(color: MaTvColors.ink, fontSize: 15)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _info(MaTvChannel? ch, MaTvProgram? p) {
    final live = p != null && p.isOnAt(now);
    final past = p != null && !p.end.isAfter(now);
    return Container(
      height: 150,
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Grille', style: TextStyle(color: MaTvColors.ink, fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 12),
                    if (categoryLabel.isNotEmpty)
                      Text(categoryLabel, style: const TextStyle(color: MaTvColors.mute, fontSize: 15)),
                    const SizedBox(width: 12),
                    Text(maTvDay(windowStart, now), style: const TextStyle(color: MaTvColors.faint, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 10),
                if (ch != null)
                  Text(
                    p?.title ?? '${ch.name} · pas de programme annoncé',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: MaTvColors.ink, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                if (p != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (live || (past && (ch?.replayDays ?? 0) > 0))
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: live ? MaTvColors.live : const Color(0x33E5A23A),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            live ? 'EN DIRECT' : 'REPLAY',
                            style: TextStyle(
                              color: live ? Colors.white : MaTvColors.accent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      Text(
                        [
                          '${ch!.number} ${ch.name}',
                          '${maTvDay(p.start, now)} ${maTvRange(p)}',
                          if (p.category.isNotEmpty) p.category,
                          if (p.subtitle.isNotEmpty) p.subtitle,
                        ].join('  ·  '),
                        style: const TextStyle(color: MaTvColors.mute, fontSize: 13.5),
                      ),
                    ],
                  ),
                  if (p.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      p.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: MaTvColors.mute, fontSize: 13.5, height: 1.3),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(maTvTime(now), style: const TextStyle(color: MaTvColors.ink, fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('OK regarder · MENU favori', style: TextStyle(color: MaTvColors.faint, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeline() {
    return Padding(
      padding: const EdgeInsets.only(left: 28 + _channelWidth, right: 0, bottom: 6),
      child: LayoutBuilder(
        builder: (context, box) {
          final ppm = box.maxWidth / _span.inMinutes;
          return SizedBox(
            height: 22,
            child: Stack(
              children: [
                for (var m = 0; m < _span.inMinutes; m += 30)
                  Positioned(
                    left: m * ppm,
                    top: 0,
                    child: Text(
                      maTvTime(windowStart.add(Duration(minutes: m))),
                      style: const TextStyle(color: MaTvColors.mute, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(int i, double width, double ppm, MaTvProgram? sel) {
    final ch = channels[i];
    final on = i == row;
    final end = windowStart.add(_span);
    final list = (programs[ch.id] ?? const <MaTvProgram>[])
        .where((p) => p.end.isAfter(windowStart) && p.start.isBefore(end))
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: _channelWidth - 8,
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: on ? MaTvColors.rowOn : MaTvColors.row,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 38,
                  child: Text('${ch.number}', textAlign: TextAlign.right, style: const TextStyle(color: MaTvColors.mute, fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                MaTvLogo(url: ch.logo, name: ch.name, size: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MaTvColors.ink, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                if (favorites.contains(ch.id)) const Icon(Icons.star_rounded, size: 14, color: MaTvColors.accent),
              ],
            ),
          ),
          SizedBox(
            width: width,
            child: Stack(
              children: [
                if (list.isEmpty)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: MaTvColors.row,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: on ? MaTvColors.ink : Colors.transparent, width: 2),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      child: const Text('Pas de programme annoncé', style: TextStyle(color: MaTvColors.faint, fontSize: 13)),
                    ),
                  ),
                for (final p in list) _cell(i, ch, p, width, ppm, on && sel != null && p.start == sel.start),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(int i, MaTvChannel ch, MaTvProgram p, double width, double ppm, bool selected) {
    final from = p.start.isBefore(windowStart) ? windowStart : p.start;
    final to = p.end.isAfter(windowStart.add(_span)) ? windowStart.add(_span) : p.end;
    final left = from.difference(windowStart).inSeconds / 60 * ppm;
    final w = (to.difference(from).inSeconds / 60 * ppm - 4).clamp(2.0, width);
    final live = p.isOnAt(now);
    final past = !p.end.isAfter(now);
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      width: w,
      child: GestureDetector(
        onTap: onTapProgram == null ? null : () => onTapProgram!(i, p),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? MaTvColors.ink
                : (live ? const Color(0x24EDEBE6) : (past ? const Color(0x0AEDEBE6) : MaTvColors.row)),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.centerLeft,
          child: w < 40
              ? null
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (past && ch.replayDays > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.replay_rounded, size: 13, color: selected ? Colors.black54 : MaTvColors.mute),
                          ),
                        Expanded(
                          child: Text(
                            p.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? Colors.black : (past ? MaTvColors.mute : MaTvColors.ink),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (w > 90)
                      Text(
                        maTvRange(p),
                        maxLines: 1,
                        style: TextStyle(color: selected ? Colors.black54 : MaTvColors.faint, fontSize: 12),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
