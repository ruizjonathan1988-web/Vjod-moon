// Recordings, in the TV tab: what Ma TV is recording, what is scheduled,
// what is ready to watch (kept 7 days unless marked to keep), and the series
// followed. Plus the two ways to schedule from here: a programme (from the
// channel menu or the guide) and a time range on a channel.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/vjod/ma_tv.dart';
import '../../../data/services/vjod/ma_tv_recordings.dart';
import '../../navigation/destinations.dart';
import 'ma_tv_search_screen.dart';
import 'ma_tv_widgets.dart';
import '../../../util/vjod_text.dart';

String _tn(String fr, String en, String ru, String zh) =>
    vjodTextNow(fr: fr, en: en, ru: ru, zh: zh);


String _size(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1).replaceAll('.', ',')} Go';
  return '${(bytes / (1 << 20)).round()} Mo';
}

String _when(DateTime start, DateTime end, DateTime now) =>
    '${maTvDay(start, now)} ${maTvTime(start)} – ${maTvTime(end)}';

/// Asks how to record [program] on [channel] (this airing, or every airing
/// of the title) and schedules it. Returns what to tell the viewer, or null
/// when left without choosing.
Future<String?> maTvRecordProgram(BuildContext context, MaTvChannel channel, MaTvProgram program) async {
  final recorder = MaTvRecorder();
  final known = MaTvRecorder.last?.of(channel.id, program.start);
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => _ChoiceDialog(
      title: program.title,
      subtitle: '${channel.name} · ${_when(program.start, program.end, DateTime.now())}',
      choices: [
        if (known != null) ('cancel', Icons.stop_circle_outlined, _tn('Annuler l\'enregistrement', 'Cancel the recording', 'Отменить запись', '取消录制'))
        else ...[
          ('one', Icons.fiber_manual_record_rounded, _tn('Enregistrer cette émission', 'Record this programme', 'Записать эту передачу', '录制此节目')),
          ('series', Icons.repeat_rounded, '${_tn('Toutes les diffusions sur', 'Every airing on', 'Все показы на', '所有播出：')} ${channel.name}'),
        ],
        ('none', Icons.close_rounded, _tn('Retour', 'Back', 'Назад', '返回')),
      ],
    ),
  );
  if (choice == null || choice == 'none') return null;
  if (choice == 'cancel') {
    final ok = await recorder.remove(known!.id);
    unawaited(recorder.list());
    return ok ? _tn('Enregistrement annulé', 'Recording cancelled', 'Запись отменена', '录制已取消') : _tn('Ma TV ne répond pas', 'Ma TV isn’t responding', 'Ma TV не отвечает', 'Ma TV 无响应');
  }
  final err = await recorder.add(
    channelId: channel.id,
    start: program.start,
    end: program.end,
    title: program.title,
    subtitle: program.subtitle,
    series: choice == 'series',
  );
  unawaited(recorder.list());
  if (err != null) return err;
  final live = program.isOnAt(DateTime.now());
  if (choice == 'series') return _tn('Toutes les diffusions de « %s » seront enregistrées', 'Every airing of “%s” will be recorded', 'Все показы «%s» будут записаны', '“%s” 的所有播出都将被录制').replaceFirst('%s', program.title);
  return live ? _tn('Enregistrement en cours (même télé éteinte)', 'Recording now (even with the TV off)', 'Идёт запись (даже при выключенном ТВ)', '正在录制（电视关着也行）') : '${_tn('Enregistrement programmé à', 'Recording planned at', 'Запись запланирована на', '已安排录制：')} ${maTvTime(program.start)}';
}

/// A short list of choices, easy with the remote: the first one is focused.
class _ChoiceDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<(String, IconData, String)> choices;

  const _ChoiceDialog({required this.title, required this.subtitle, required this.choices});

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: const Color(0xFF17171A),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: MaTvColors.ink, fontSize: 20, fontWeight: FontWeight.w700)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: MaTvColors.mute, fontSize: 14)),
            ],
            const SizedBox(height: 14),
            for (var i = 0; i < choices.length; i++)
              _FocusRow(
                autofocus: i == 0,
                onTap: () => Navigator.of(context).pop(choices[i].$1),
                child: Row(
                  children: [
                    Icon(choices[i].$2,
                        size: 22, color: choices[i].$1 == 'one' ? MaTvColors.live : MaTvColors.ink),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(choices[i].$3, style: const TextStyle(color: MaTvColors.ink, fontSize: 16)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// A row lit when the remote is on it.
class _FocusRow extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool autofocus;

  const _FocusRow({required this.child, this.onTap, this.autofocus = false});

  @override
  State<_FocusRow> createState() => _FocusRowState();
}

class _FocusRowState extends State<_FocusRow> {
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _on ? MaTvColors.rowOn : MaTvColors.row,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _on ? MaTvColors.ink : Colors.transparent, width: 2),
        ),
        child: widget.child,
      ),
    ),
  );
}

class MaTvRecordingsScreen extends StatefulWidget {
  const MaTvRecordingsScreen({super.key});

  @override
  State<MaTvRecordingsScreen> createState() => _MaTvRecordingsScreenState();
}

class _MaTvRecordingsScreenState extends State<MaTvRecordingsScreen> {
  final _recorder = MaTvRecorder();
  MaTvRecordings? _data;
  bool _failed = false;
  Timer? _refresh;
  String? _toast;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // Sizes grow and statuses change while something records.
    _refresh = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final d = await _recorder.list();
    if (!mounted) return;
    setState(() {
      if (d != null) _data = d;
      _failed = d == null && _data == null;
    });
  }

  void _say(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _play(MaTvRecording r) {
    final uri = _recorder.playUri(r);
    if (uri == null) return;
    final title = r.subtitle.isNotEmpty ? '${r.title} · ${r.subtitle}' : r.title;
    context.push(Destinations.providerPlayer(url: uri.toString(), title: title));
  }

  Future<void> _actions(MaTvRecording r) async {
    final now = DateTime.now();
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => _ChoiceDialog(
        title: r.title,
        subtitle: '${r.channelName} · ${_when(r.start, r.end, now)}',
        choices: [
          if (r.playable) ('play', Icons.play_arrow_rounded, r.recording ? _tn('Regarder (en cours)', 'Watch (recording)', 'Смотреть (идёт запись)', '观看（录制中）') : _tn('Regarder', 'Watch', 'Смотреть', '观看')),
          if (!r.scheduled && !r.recording)
            (r.keep ? 'unkeep' : 'keep', r.keep ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined,
                r.keep ? _tn('Ne plus garder (effacé après %d jours)', 'Stop keeping (deleted after %d days)', 'Не хранить (удалится через %d дн.)', '不再保留（%d 天后删除）').replaceFirst('%d', '${_data?.keepDays ?? 7}') : _tn('Garder (ne pas effacer)', 'Keep (don’t delete)', 'Хранить (не удалять)', '保留（不删除）')),
          if (r.scheduled || r.recording)
            ('delete', Icons.stop_circle_outlined, r.recording ? _tn('Arrêter et effacer', 'Stop and delete', 'Остановить и удалить', '停止并删除') : _tn('Annuler l\'enregistrement', 'Cancel the recording', 'Отменить запись', '取消录制'))
          else
            ('delete', Icons.delete_outline_rounded, _tn('Effacer', 'Delete', 'Удалить', '删除')),
          ('none', Icons.close_rounded, _tn('Retour', 'Back', 'Назад', '返回')),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'none') return;
    switch (choice) {
      case 'play':
        _play(r);
        return;
      case 'keep' || 'unkeep':
        final ok = await _recorder.keep(r.id, choice == 'keep');
        _say(ok ? (choice == 'keep' ? _tn('Gardé', 'Kept', 'Сохранено', '已保留') : _tn('Sera effacé après %d jours', 'Will be deleted after %d days', 'Удалится через %d дн.', '%d 天后删除').replaceFirst('%d', '${_data?.keepDays ?? 7}')) : _tn('Ma TV ne répond pas', 'Ma TV isn’t responding', 'Ma TV не отвечает', 'Ma TV 无响应'));
      case 'delete':
        final ok = await _recorder.remove(r.id);
        _say(ok ? (r.scheduled ? _tn('Annulé', 'Cancelled', 'Отменено', '已取消') : _tn('Effacé', 'Deleted', 'Удалено', '已删除')) : _tn('Ma TV ne répond pas', 'Ma TV isn’t responding', 'Ma TV не отвечает', 'Ma TV 无响应'));
    }
    await _load();
  }

  Future<void> _ruleActions(MaTvRecordingRule rule) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => _ChoiceDialog(
        title: rule.title,
        subtitle: '${_tn('Toutes les diffusions sur', 'Every airing on', 'Все показы на', '所有播出：')} ${rule.channelName}',
        choices: const [
          ('stop', Icons.stop_circle_outlined, _tn('Ne plus enregistrer', 'Stop recording', 'Больше не записывать', '停止录制')),
          ('none', Icons.close_rounded, _tn('Retour', 'Back', 'Назад', '返回')),
        ],
      ),
    );
    if (!mounted || choice != 'stop') return;
    final ok = await _recorder.removeRule(rule.id);
    _say(ok ? _tn('Plus enregistré (déjà enregistrés gardés)', 'No longer recorded (existing ones kept)', 'Больше не записывается (готовые сохранены)', '不再录制（已录的保留）') : _tn('Ma TV ne répond pas', 'Ma TV isn’t responding', 'Ma TV не отвечает', 'Ma TV 无响应'));
    await _load();
  }

  Future<void> _manual() async {
    final msg = await Navigator.of(context).push<String>(maTvRoute((_) => const MaTvManualRecordScreen()));
    if (!mounted) return;
    if (msg != null) _say(msg);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final now = DateTime.now();
    final running = d?.items.where((r) => r.recording).toList() ?? const [];
    final planned = d?.items.where((r) => r.scheduled).toList() ?? const [];
    final ready = d?.items.where((r) => !r.recording && !r.scheduled).toList() ?? const [];
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(_tn('Enregistrements', 'Recordings', 'Записи', '录像'),
                          style: const TextStyle(color: MaTvColors.ink, fontSize: 26, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 14),
                      if (d != null)
                        Expanded(
                          child: Text(
                            [
                              if (d.used > 0) '${_size(d.used)} ${_tn('utilisés', 'used', 'занято', '已用')}',
                              if (d.free != null) '${_size(d.free!)} ${_tn('libres', 'free', 'свободно', '可用')}',
                              _tn('effacés après %d jours sauf « gardés »', 'deleted after %d days unless “kept”', 'удаляются через %d дн., кроме «сохранённых»', '%d 天后删除（“保留”的除外）').replaceFirst('%d', '${d.keepDays}'),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: MaTvColors.mute, fontSize: 14),
                          ),
                        )
                      else
                        const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tn('Ma TV enregistre sur la seedbox : la télé peut rester éteinte. Pour enregistrer une émission, MENU sur la chaîne ou OK sur une émission à venir dans la grille.', 'Ma TV records on the seedbox: the TV can stay off. To record a programme, MENU on the channel or OK on an upcoming programme in the guide.', 'Ma TV пишет на сидбокс: телевизор можно выключить. Чтобы записать передачу — МЕНЮ на канале или OK на будущей передаче в сетке.', 'Ma TV 在种子盒上录制：电视可以关着。要录制节目，在频道上按菜单，或在节目表中对即将播出的节目按确定。'),
                    style: const TextStyle(color: MaTvColors.faint, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: d == null
                        ? Center(
                            child: _failed
                                ? Text(_tn('Ma TV ne répond pas, réessaie dans un instant.', 'Ma TV isn’t responding, try again in a moment.', 'Ma TV не отвечает, попробуй чуть позже.', 'Ma TV 无响应，请稍后再试。'),
                                    style: const TextStyle(color: MaTvColors.mute, fontSize: 16))
                                : const CircularProgressIndicator(strokeWidth: 2),
                          )
                        : ListView(
                            children: [
                              _FocusRow(
                                autofocus: true,
                                onTap: _manual,
                                child: Row(
                                  children: [
                                    const Icon(Icons.more_time_rounded, color: MaTvColors.accent),
                                    const SizedBox(width: 14),
                                    Text(_tn('Programmer une plage horaire', 'Plan a time slot', 'Запланировать интервал', '安排时段录制'),
                                        style: const TextStyle(color: MaTvColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                              if (running.isNotEmpty) ...[
                                _header(_tn('En cours', 'Recording now', 'Идёт запись', '录制中')),
                                for (final r in running) _row(r, now),
                              ],
                              if (planned.isNotEmpty) ...[
                                _header(_tn('Programmés', 'Planned', 'Запланировано', '已安排')),
                                for (final r in planned) _row(r, now),
                              ],
                              _header(_tn('Enregistrés', 'Recorded', 'Записано', '已录制')),
                              if (ready.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(_tn('Rien pour le moment.', 'Nothing yet.', 'Пока ничего.', '暂时没有。'), style: const TextStyle(color: MaTvColors.mute, fontSize: 15)),
                                ),
                              for (final r in ready) _row(r, now),
                              if (d.rules.isNotEmpty) ...[
                                _header(_tn('Séries suivies', 'Followed series', 'Отслеживаемые', '追踪的节目')),
                                for (final rule in d.rules)
                                  _FocusRow(
                                    onTap: () => _ruleActions(rule),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.repeat_rounded, color: MaTvColors.mute, size: 22),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Text(rule.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: MaTvColors.ink, fontSize: 16)),
                                        ),
                                        Text(rule.channelName, style: const TextStyle(color: MaTvColors.mute, fontSize: 14)),
                                      ],
                                    ),
                                  ),
                              ],
                              const SizedBox(height: 24),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            if (_toast != null)
              Positioned(
                bottom: 28,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(color: MaTvColors.panel, borderRadius: BorderRadius.circular(22)),
                    child: Text(_toast!, style: const TextStyle(color: MaTvColors.ink, fontSize: 15)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
    child: Text(text.toUpperCase(),
        style: const TextStyle(color: MaTvColors.mute, fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
  );

  Widget _row(MaTvRecording r, DateTime now) {
    final (IconData icon, Color color, String state) = switch (r.status) {
      'recording' => (Icons.fiber_manual_record_rounded, MaTvColors.live, '${_tn('en cours', 'recording', 'идёт запись', '录制中')} · ${_size(r.size)}'),
      'scheduled' => (Icons.schedule_rounded, MaTvColors.accent, r.rule.isNotEmpty ? _tn('série', 'series', 'серия', '系列') : _tn('programmé', 'planned', 'запланировано', '已安排')),
      'done' => (Icons.play_circle_outline_rounded, MaTvColors.good, _size(r.size)),
      'partial' => (Icons.play_circle_outline_rounded, MaTvColors.accent, '${_tn('incomplet', 'incomplete', 'неполная', '不完整')} · ${_size(r.size)}'),
      _ => (Icons.error_outline_rounded, MaTvColors.mute, r.message.isNotEmpty ? r.message : _tn('échec', 'failed', 'ошибка', '失败')),
    };
    return _FocusRow(
      onTap: () => _actions(r),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.subtitle.isNotEmpty ? '${r.title} · ${r.subtitle}' : r.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MaTvColors.ink, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${r.number != null ? '${r.number} ' : ''}${r.channelName} · ${_when(r.start, r.end, now)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MaTvColors.mute, fontSize: 13.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (r.keep) const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.bookmark_rounded, size: 18, color: MaTvColors.accent),
          ),
          Text(state, style: TextStyle(color: color, fontSize: 13.5)),
        ],
      ),
    );
  }
}

/// A time range on a channel: the channel (searched by name or number), the
/// day, the start and how long. Everything with the arrows and OK.
class MaTvManualRecordScreen extends StatefulWidget {
  const MaTvManualRecordScreen({super.key});

  @override
  State<MaTvManualRecordScreen> createState() => _MaTvManualRecordScreenState();
}

class _MaTvManualRecordScreenState extends State<MaTvManualRecordScreen> {
  MaTvChannel? _channel;
  late DateTime _start;
  Duration _length = const Duration(hours: 1);
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // The next quarter hour.
    final q = DateTime(now.year, now.month, now.day, now.hour, (now.minute ~/ 15) * 15);
    _start = q.add(const Duration(minutes: 15));
  }

  void _shift(Duration d) {
    final next = _start.add(d);
    final now = DateTime.now();
    if (next.add(_length).isBefore(now)) return;
    if (next.isAfter(now.add(const Duration(days: 7)))) return;
    setState(() => _start = next);
  }

  void _resize(Duration d) {
    final next = _length + d;
    if (next < const Duration(minutes: 15) || next > const Duration(hours: 6)) return;
    setState(() => _length = next);
  }

  Future<void> _pickChannel() async {
    final pick = await Navigator.of(context).push<({List<MaTvChannel> channels, int index})>(
      maTvRoute((_) => const MaTvSearchScreen()),
    );
    if (!mounted || pick == null) return;
    setState(() => _channel = pick.channels[pick.index]);
  }

  Future<void> _save() async {
    final ch = _channel;
    if (ch == null) {
      await _pickChannel();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await MaTvRecorder().add(
      channelId: ch.id,
      start: _start,
      end: _start.add(_length),
      title: '${ch.name} · ${maTvTime(_start)}',
    );
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop('${_tn('Plage programmée', 'Slot planned', 'Интервал запланирован', '时段已安排')} : ${ch.name}, ${maTvDay(_start, DateTime.now())} ${maTvTime(_start)}');
      return;
    }
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  String get _lengthLabel {
    final h = _length.inHours;
    final m = _length.inMinutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final end = _start.add(_length);
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              children: [
                Text(_tn('Programmer une plage', 'Plan a slot', 'Запланировать интервал', '安排时段'),
                    style: const TextStyle(color: MaTvColors.ink, fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 18),
                _FocusRow(
                  autofocus: true,
                  onTap: _pickChannel,
                  child: Row(
                    children: [
                      SizedBox(width: 90, child: Text(_tn('Chaîne', 'Channel', 'Канал', '频道'), style: const TextStyle(color: MaTvColors.mute, fontSize: 15))),
                      if (_channel != null) ...[
                        MaTvLogo(url: _channel!.logo, name: _channel!.name, size: 30),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          _channel == null ? _tn('Choisir une chaîne…', 'Choose a channel…', 'Выбери канал…', '选择频道…') : '${_channel!.number} ${_channel!.name}',
                          style: TextStyle(
                            color: _channel == null ? MaTvColors.accent : MaTvColors.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(Icons.search_rounded, color: MaTvColors.mute),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _stepper(_tn('Jour', 'Day', 'День', '日期'), maTvDay(_start, now), [
                  ('− 1 ${_tn('jour', 'day', 'день', '天')}', () => _shift(const Duration(days: -1))),
                  ('+ 1 ${_tn('jour', 'day', 'день', '天')}', () => _shift(const Duration(days: 1))),
                ]),
                _stepper(_tn('Début', 'Start', 'Начало', '开始'), maTvTime(_start), [
                  ('− 1 h', () => _shift(const Duration(hours: -1))),
                  ('− 5 min', () => _shift(const Duration(minutes: -5))),
                  ('+ 5 min', () => _shift(const Duration(minutes: 5))),
                  ('+ 1 h', () => _shift(const Duration(hours: 1))),
                ]),
                _stepper(_tn('Durée', 'Length', 'Длительность', '时长'), '$_lengthLabel  (${_tn('fin', 'end', 'конец', '结束')} ${maTvTime(end)})', [
                  ('− 15 min', () => _resize(const Duration(minutes: -15))),
                  ('+ 15 min', () => _resize(const Duration(minutes: 15))),
                ]),
                const SizedBox(height: 18),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(_error!, style: const TextStyle(color: MaTvColors.live, fontSize: 15)),
                  ),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.fiber_manual_record_rounded, color: MaTvColors.live),
                      label: Text(_channel == null ? _tn('Choisir la chaîne', 'Choose the channel', 'Выбрать канал', '选择频道') : _tn('Programmer', 'Plan', 'Запланировать', '安排')),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(_tn('Annuler', 'Cancel', 'Отмена', '取消'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepper(String label, String value, List<(String, VoidCallback)> steps) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: MaTvColors.row, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(color: MaTvColors.mute, fontSize: 15))),
          Expanded(
            child: Text(value, style: const TextStyle(color: MaTvColors.ink, fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: OutlinedButton(
                onPressed: s.$2,
                style: OutlinedButton.styleFrom(
                  foregroundColor: MaTvColors.ink,
                  side: const BorderSide(color: MaTvColors.faint),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(s.$1),
              ),
            ),
        ],
      ),
    ),
  );
}
