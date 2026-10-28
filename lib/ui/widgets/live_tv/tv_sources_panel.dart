import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/services/vjod/tv_sources.dart';
import '../../../util/focus/dpad_keys.dart';

/// The sources panel of the live player, opened with RIGHT like a box: every
/// provider stream behind the channel on screen, best first, with what the
/// seedbox measured (picture, frame rate, bitrate, start time).
///
/// UP / DOWN move, OK switches to the source on the spot (the relay changes
/// stream while it plays, nothing retunes), a long OK keeps that source for
/// the channel for good, LEFT or BACK closes. Touch: tap to switch, long press
/// to keep.
class TvSourcesPanel extends StatefulWidget {
  final int channelNumber;
  final String channelName;
  final TvSourcesClient client;
  final VoidCallback onClose;

  /// Called with a short line to show once a source is picked.
  final ValueChanged<String> onPicked;

  const TvSourcesPanel({
    super.key,
    required this.channelNumber,
    required this.channelName,
    required this.client,
    required this.onClose,
    required this.onPicked,
  });

  @override
  State<TvSourcesPanel> createState() => _TvSourcesPanelState();
}

class _TvSourcesPanelState extends State<TvSourcesPanel> {
  static const _longPress = Duration(milliseconds: 650);
  static const _ink = Color(0xFFEDEBE6);
  static const _mute = Color(0x99EDEBE6);
  static const _good = Color(0xFF5BD18B);
  static const _bad = Color(0xFFE86A5F);

  final _focus = FocusNode(debugLabel: 'TvSourcesPanel');
  final _scroll = ScrollController();
  TvChannelSources? _data;
  bool _loading = true;
  bool _busy = false;
  int _index = 0;
  DateTime? _selectDownAt;
  bool _longFired = false;
  Timer? _refresh;
  Timer? _longTimer;

  bool get _french => Localizations.localeOf(context).languageCode == 'fr';
  String _t(String fr, String en) => _french ? fr : en;

  bool _showAll = false;

  /// One source per real server up front: the others would fall with it, so
  /// they wait behind "see the others" unless one plays or was chosen.
  List<TvSource> get _visible {
    final all = _data?.sources ?? const <TvSource>[];
    return _showAll ? all : [for (final s in all) if (!s.duplicate) s];
  }

  int get _hidden => (_data?.sources.length ?? 0) - _visible.length;

  /// Row 0 is "automatic", then the sources, then "see the others".
  int get _rows => 1 + _visible.length + (_hidden > 0 ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _load(placeFocus: true);
    // The relay reports which source feeds the stream, which moves on its own
    // when one fails: keep the marks current while the panel is up.
    _refresh = Timer.periodic(const Duration(seconds: 3), (_) => _load());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _longTimer?.cancel();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool placeFocus = false}) async {
    final data = await widget.client.channel(widget.channelNumber);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (data == null) return;
      _data = data;
      if (placeFocus) {
        final shown = _visible;
        final playing = shown.indexWhere((s) => s.playing);
        _index = playing >= 0 ? playing + 1 : (data.hasChoice ? 1 : 0);
      }
      _index = _index.clamp(0, _rows - 1);
    });
  }

  Future<void> _pick(int row, {required bool sticky}) async {
    final data = _data;
    if (data == null || _busy) return;
    if (row > _visible.length) {
      setState(() => _showAll = true);
      return;
    }
    final source = row == 0 ? null : _visible[row - 1];
    setState(() => _busy = true);
    final result = await widget.client.prefer(data.id, source?.key, sticky: sticky);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != null) _data = result;
    });
    if (result == null) {
      widget.onPicked(_t('IPTV Checker ne répond pas', 'IPTV Checker is not answering'));
      return;
    }
    final details = source?.details(french: _french) ?? '';
    widget.onPicked(
      source == null
          ? _t('Source automatique : la meilleure du moment', 'Automatic source: the best one right now')
          : '${_t('Source', 'Source')} ${source.rank}${details.isEmpty ? '' : ' · $details'}'
                '${sticky ? _t(' · gardée pour cette chaîne', ' · kept for this channel') : ''}',
    );
    widget.onClose();
  }

  void _move(int delta) {
    if (_rows == 0) return;
    setState(() => _index = (_index + delta).clamp(0, _rows - 1));
    _ensureVisible();
  }

  void _ensureVisible() {
    if (!_scroll.hasClients) return;
    const rowHeight = 74.0;
    final target = (_index * rowHeight) - 80;
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key.isSelectKey) {
      if (event is KeyDownEvent) {
        _selectDownAt = DateTime.now();
        _longFired = false;
        _longTimer?.cancel();
        _longTimer = Timer(_longPress, () {
          if (!mounted || _selectDownAt == null) return;
          _longFired = true;
          unawaited(_pick(_index, sticky: true));
        });
      } else if (event is KeyUpEvent) {
        _longTimer?.cancel();
        final down = _selectDownAt;
        _selectDownAt = null;
        if (down != null && !_longFired) unawaited(_pick(_index, sticky: false));
      }
      return KeyEventResult.handled;
    }
    if (!event.isActionable) return KeyEventResult.handled;
    if (key.isUpKey) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key.isLeftKey || key.isBackKey) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    // Everything else stays inside the panel so nothing zaps behind it.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width < 600 ? width * 0.92 : 460.0;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onClose,
            child: const ColoredBox(color: Color(0x55000000)),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: panelWidth,
          child: Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [Color(0xF20B0B0D), Color(0xE00B0B0D)],
                ),
                border: Border(left: BorderSide(color: Color(0x33EDEBE6))),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 24,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
                left: 20,
                right: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('Sources', 'Sources'),
                    style: const TextStyle(color: _mute, fontSize: 13, letterSpacing: 1.2, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.channelNumber}  ${widget.channelName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _ink, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  Expanded(child: _buildBody()),
                  const SizedBox(height: 10),
                  Text(
                    _t('OK : changer tout de suite · OK long : garder pour cette chaîne',
                        'OK: switch now · Hold OK: keep for this channel'),
                    style: const TextStyle(color: _mute, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final data = _data;
    if (data == null) {
      return Text(
        _t("Cette chaîne n'est pas dans Ma TV, ou IPTV Checker ne répond pas.",
            "This channel isn't in Ma TV, or IPTV Checker is not answering."),
        style: const TextStyle(color: _mute, fontSize: 15),
      );
    }
    return ListView.builder(
      controller: _scroll,
      itemCount: _rows,
      itemBuilder: (context, row) => _buildRow(data, row),
    );
  }

  Widget _buildRow(TvChannelSources data, int row) {
    final selected = row == _index;
    if (row > _visible.length) return _buildMoreRow(row, selected);
    final source = row == 0 ? null : _visible[row - 1];
    final title = source == null
        ? _t('Automatique', 'Automatic')
        : '${_t('Source', 'Source')} ${source.rank}';
    final subtitle = source == null
        ? _t('La meilleure source du moment, et la suivante si elle coupe',
            'The best source right now, and the next one if it drops')
        : [source.details(french: _french), source.where.isNotEmpty ? source.where : source.provider]
            .where((s) => s.isNotEmpty)
            .join(' · ');
    final badges = <Widget>[
      if (source == null && !data.hasChoice) _badge(_t('actif', 'on'), _good),
      if (source != null && source.playing) _badge(_t('en lecture', 'playing'), _good),
      if (source != null && source.sticky) _badge(_t('toujours', 'always'), AppColorScheme.accent)
      else if (source != null && source.chosen) _badge(_t('choisie', 'chosen'), AppColorScheme.accent),
      if (source != null && source.ok == false) _badge(_t('en panne', 'down'), _bad),
      if (source != null && source.ok == null) _badge(_t('pas testée', 'untested'), _mute),
    ];
    return GestureDetector(
      onTap: () {
        setState(() => _index = row);
        unawaited(_pick(row, sticky: false));
      },
      onLongPress: () {
        setState(() => _index = row);
        unawaited(_pick(row, sticky: true));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        height: 66,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0x26EDEBE6) : const Color(0x0DEDEBE6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _ink : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: const TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _mute, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (_busy && selected)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Wrap(spacing: 6, children: badges),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreRow(int row, bool selected) {
    return GestureDetector(
      onTap: () {
        setState(() => _index = row);
        setState(() => _showAll = true);
      },
      child: Container(
        height: 50,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: selected ? const Color(0x26EDEBE6) : const Color(0x0DEDEBE6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _ink : Colors.transparent, width: 2),
        ),
        child: Text(
          _t('Voir les $_hidden autres (même serveur)', 'See the other $_hidden (same server)'),
          style: const TextStyle(color: _mute, fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.6)),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
  );
}
