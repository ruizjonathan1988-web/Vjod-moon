// Sports, in the TV tab (VJOD 4.6, Ma TV 3.55): the day's matches of the
// sports this profile follows, the live score, the odds, and « Regarder »
// on the channel that shows the match. OK on a match opens its choices (watch
// on a channel, be told at kick-off, follow a team), the easy way with a
// remote. Read again every minute while open; nothing runs once closed.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/services/vjod/ma_tv.dart';
import '../../../data/services/vjod/ma_tv_sports.dart';
import '../../../util/vjod_log.dart';
import 'ma_tv_search_screen.dart';
import 'ma_tv_widgets.dart';

/// What the screen hands back: the channels of the match, the one to play.
typedef MaTvSportsPick = ({List<MaTvChannel> channels, int index});

class MaTvSportsScreen extends StatefulWidget {
  const MaTvSportsScreen({super.key});

  @override
  State<MaTvSportsScreen> createState() => _MaTvSportsScreenState();
}

class _MaTvSportsScreenState extends State<MaTvSportsScreen> {
  final _client = MaTvClient();
  MaTvSports? _data;
  bool _loading = true;
  bool _tooOld = false;
  SportsChoices _choices = SportsChoices.read();
  Timer? _timer;
  Timer? _toastTimer;
  String? _toast;
  final Map<String, String> _states = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final c = SportsChoices.read();
    final data = await _client.sports(kinds: c.kinds, teams: c.teams, limit: 120);
    if (!mounted) return;
    if (data != null) {
      final started = kickOffs(Map.of(_states), data.events, reminders: c.reminders, teams: c.teams);
      for (final e in data.events) {
        _states[e.id] = e.state;
      }
      if (started.isNotEmpty) _say('Coup d’envoi : ${started.first.home} – ${started.first.away}');
    }
    setState(() {
      _choices = c;
      _loading = false;
      _tooOld = data == null;
      if (data != null) _data = data;
    });
  }

  void _say(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _open(SportEvent e) async {
    final reminded = _choices.reminders.contains(e.id);
    final pick = await showDialog<String>(
      context: context,
      builder: (context) => _SportChoices(
        event: e,
        choices: [
          for (final ch in e.channels) ('watch:${ch.id}', Icons.play_arrow_rounded, 'Regarder sur ${ch.name}'),
          if (e.channels.isEmpty) ('search', Icons.search_rounded, 'Chercher la chaîne'),
          if (!e.live && !e.finished)
            (
              'remind',
              reminded ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
              reminded ? 'Ne plus me prévenir' : 'Me prévenir au coup d’envoi',
            ),
          for (final team in [e.home, e.away])
            (
              'team:$team',
              _choices.teams.any((t) => t.toLowerCase() == team.toLowerCase()) ? Icons.star_rounded : Icons.star_border_rounded,
              _choices.teams.any((t) => t.toLowerCase() == team.toLowerCase()) ? 'Ne plus suivre $team' : 'Suivre $team',
            ),
          ('none', Icons.close_rounded, 'Retour'),
        ],
      ),
    );
    if (!mounted || pick == null || pick == 'none') return;
    if (pick == 'remind') {
      await SportsChoices.toggleReminder(e.id);
      _say(reminded ? 'Rappel retiré' : 'Tu seras prévenu au coup d’envoi (sur cet écran ou dans le lecteur)');
    } else if (pick.startsWith('team:')) {
      await SportsChoices.toggleTeam(pick.substring(5));
      _say('Équipes suivies mises à jour');
    } else if (pick == 'search') {
      await _search(e);
      return;
    } else if (pick.startsWith('watch:')) {
      await _watch(e, pick.substring(6));
      return;
    }
    setState(() => _choices = SportsChoices.read());
  }

  Future<void> _watch(SportEvent e, String channelId) async {
    final ids = [for (final c in e.channels) c.id];
    final chans = await _client.channelsByIds(ids);
    if (!mounted) return;
    if (chans == null || chans.isEmpty) {
      _say('Ma TV ne répond pas pour le moment');
      return;
    }
    final index = chans.indexWhere((c) => c.id == channelId);
    Navigator.of(context).pop<MaTvSportsPick>((channels: chans, index: index < 0 ? 0 : index));
  }

  /// The card's button: watch, be told at kick-off, or look for the channel.
  Future<void> _primary(SportEvent e) async {
    if (e.channels.isNotEmpty) return _watch(e, e.channels.first.id);
    if (!e.live && !e.finished && !_choices.reminders.contains(e.id)) {
      await SportsChoices.toggleReminder(e.id);
      if (!mounted) return;
      setState(() => _choices = SportsChoices.read());
      _say('Tu seras prévenu au coup d\u2019envoi (sur cet écran ou dans le lecteur)');
      return;
    }
    await _search(e);
  }

  /// No channel found in the guide: Ma TV's search, the team typed in.
  Future<void> _search(SportEvent e) async {
    final pick = await Navigator.of(context).push<({List<MaTvChannel> channels, int index})>(
      maTvRoute((_) => MaTvSearchScreen(initialQuery: e.home)),
    );
    if (!mounted || pick == null) return;
    Navigator.of(context).pop<MaTvSportsPick>(pick);
  }

  Future<void> _settings() async {
    final teams = <String>{for (final e in _data?.events ?? const <SportEvent>[]) ...[e.home, e.away]}.toList()..sort();
    await Navigator.of(context).push<void>(
      maTvRoute((_) => MaTvSportsSettingsScreen(kinds: _data?.kinds ?? const [], teams: teams)),
    );
    if (!mounted) return;
    setState(() => _choices = SportsChoices.read());
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 700;
    final events = _data?.events ?? const <SportEvent>[];
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_tooOld) {
      body = const _Empty('Ma TV ne donne pas encore les sports : mets-la à jour (version 3.55 ou plus).');
    } else if (events.isEmpty) {
      body = _Empty(
        _data?.source == null
            ? 'Les scores ne répondent pas pour le moment. Réessaie dans quelques minutes.'
            : 'Aucun match aujourd’hui pour tes sports.',
      );
    } else {
      final columns = (width / (narrow ? 340 : 330)).floor().clamp(1, 5);
      body = GridView.builder(
        padding: EdgeInsets.fromLTRB(narrow ? 12 : 28, 4, narrow ? 12 : 28, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: _choices.odds ? 224 : 192,
        ),
        itemCount: events.length,
        itemBuilder: (context, i) => SportCard(
          event: events[i],
          autofocus: i == 0,
          showOdds: _choices.odds,
          reminded: _choices.reminders.contains(events[i].id),
          followed: followsAny(events[i], _choices.teams),
          onTap: () => unawaited(_open(events[i])),
          onPrimary: () => unawaited(_primary(events[i])),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(narrow ? 16 : 28, 18, narrow ? 12 : 28, 12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded, color: MaTvColors.ink),
                      ),
                      const Text('Sports',
                          style: TextStyle(color: MaTvColors.ink, fontSize: 26, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 14),
                      if (!narrow && _data?.source != null)
                        Flexible(
                          child: Text('Scores en direct · ${_data!.source}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: MaTvColors.mute, fontSize: 14)),
                        ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => unawaited(_settings()),
                        icon: const Icon(Icons.tune_rounded, size: 18, color: MaTvColors.mute),
                        label: Text(narrow ? 'Réglages' : 'Mes sports et réglages',
                            style: const TextStyle(color: MaTvColors.mute)),
                      ),
                    ],
                  ),
                ),
                Expanded(child: body),
              ],
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
}

class _Empty extends StatelessWidget {
  final String text;

  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: MaTvColors.mute, fontSize: 17)),
    ),
  );
}

/// One match: competition and clock, both sides with the score, the odds,
/// and where to watch it.
class SportCard extends StatefulWidget {
  final SportEvent event;
  final bool autofocus;
  final bool showOdds;
  final bool reminded;
  final bool followed;
  final VoidCallback? onTap;

  /// The button under the match: « Regarder », « Me prévenir » or « Chercher la chaîne ».
  final VoidCallback? onPrimary;

  const SportCard({
    super.key,
    required this.event,
    this.autofocus = false,
    this.showOdds = true,
    this.reminded = false,
    this.followed = false,
    this.onTap,
    this.onPrimary,
  });

  @override
  State<SportCard> createState() => _SportCardState();
}

class _SportCardState extends State<SportCard> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final score = e.score;
    final recent = e.last != null && DateTime.now().difference(e.last!.at) < const Duration(minutes: 10);
    Widget side(String name, String? value) => Row(
      children: [
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: MaTvColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        if (value != null)
          Text(value, style: const TextStyle(color: MaTvColors.ink, fontSize: 17, fontWeight: FontWeight.w800)),
      ],
    );
    return InkWell(
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      onFocusChange: (f) => setState(() => _on = f),
      focusColor: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: _on ? MaTvColors.rowOn : const Color(0xFF17171A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _on ? MaTvColors.ink : (e.live ? MaTvColors.live : Colors.transparent),
            width: _on ? 2 : 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (widget.followed) const Icon(Icons.star_rounded, size: 15, color: MaTvColors.accent),
                Expanded(
                  child: Text(
                    [e.sportName, e.competition].where((x) => x.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: MaTvColors.mute, fontSize: 12.5),
                  ),
                ),
                if (e.live) const Icon(Icons.circle, size: 8, color: MaTvColors.live),
                const SizedBox(width: 4),
                Text(e.clockText,
                    style: TextStyle(
                      color: e.live ? MaTvColors.live : MaTvColors.mute,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    )),
              ],
            ),
            const SizedBox(height: 8),
            if (e.sets != null && e.sets![0].isNotEmpty) ...[
              side(e.home, e.sets![0].join(' ')),
              side(e.away, e.sets![1].join(' ')),
            ] else ...[
              side(e.home, score?[0]),
              side(e.away, score?[1]),
            ],
            if (widget.showOdds && e.odds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final k in const ['1', 'N', '2'])
                    if (e.odds[k] != null)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: MaTvColors.row, borderRadius: BorderRadius.circular(6)),
                          child: Text('$k · ${e.odds[k]!.toStringAsFixed(2).replaceAll('.', ',')}',
                              style: const TextStyle(color: MaTvColors.ink, fontSize: 12.5)),
                        ),
                      ),
                ],
              ),
            ],
            const Spacer(),
            if (recent)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(e.last!.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: MaTvColors.accent, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            _PrimaryButton(
              label: e.channels.isNotEmpty
                  ? 'Regarder · ${e.channels.first.name}'
                  : (!e.live && !e.finished)
                  ? (widget.reminded ? 'Prévenu au coup d\u2019envoi' : 'Me prévenir')
                  : 'Chercher la chaîne',
              icon: e.channels.isNotEmpty
                  ? Icons.play_arrow_rounded
                  : (!e.live && !e.finished)
                  ? Icons.notifications_active_outlined
                  : Icons.search_rounded,
              strong: e.channels.isNotEmpty,
              onTap: widget.onPrimary,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool strong;
  final VoidCallback? onTap;

  const _PrimaryButton({required this.label, required this.icon, this.strong = false, this.onTap});

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _on = false;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: widget.onTap,
    onFocusChange: (f) => setState(() => _on = f),
    focusColor: Colors.transparent,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.strong ? const Color(0xFFE50914) : MaTvColors.row,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _on ? MaTvColors.ink : Colors.transparent, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(widget.icon, size: 18, color: Colors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );
}

/// The choices on a match, the first one focused.
class _SportChoices extends StatelessWidget {
  final SportEvent event;
  final List<(String, IconData, String)> choices;

  const _SportChoices({required this.event, required this.choices});

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: const Color(0xFF17171A),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${event.home} – ${event.away}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MaTvColors.ink, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                [event.competition, event.clockText, event.scoreText].where((x) => x.isNotEmpty).join(' · '),
                style: const TextStyle(color: MaTvColors.mute, fontSize: 14),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < choices.length; i++)
                _Tile(
                  autofocus: i == 0,
                  onTap: () => Navigator.of(context).pop(choices[i].$1),
                  icon: choices[i].$2,
                  label: choices[i].$3,
                  strong: choices[i].$1.startsWith('watch:'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Tile extends StatefulWidget {
  final bool autofocus;
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final String? trailing;
  final bool strong;

  const _Tile({
    required this.onTap,
    required this.icon,
    required this.label,
    this.autofocus = false,
    this.trailing,
    this.strong = false,
  });

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
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
        child: Row(
          children: [
            Icon(widget.icon, size: 22, color: widget.strong ? MaTvColors.live : MaTvColors.ink),
            const SizedBox(width: 14),
            Expanded(child: Text(widget.label, style: const TextStyle(color: MaTvColors.ink, fontSize: 16))),
            if (widget.trailing != null)
              Text(widget.trailing!, style: const TextStyle(color: MaTvColors.accent, fontSize: 15)),
          ],
        ),
      ),
    ),
  );
}

/// This profile's sports settings: the score on the channel, the odds, the
/// sports followed and the teams followed.
class MaTvSportsSettingsScreen extends StatefulWidget {
  final List<SportKind> kinds;

  /// The teams of the matches to come, to pick from.
  final List<String> teams;

  const MaTvSportsSettingsScreen({super.key, required this.kinds, this.teams = const []});

  @override
  State<MaTvSportsSettingsScreen> createState() => _MaTvSportsSettingsScreenState();
}

class _MaTvSportsSettingsScreenState extends State<MaTvSportsSettingsScreen> {
  SportsChoices _c = SportsChoices.read();

  Future<void> _do(Future<void> Function() change) async {
    try {
      await change();
    } catch (e) {
      vjodLogError('Sports : réglage', e);
    }
    if (mounted) setState(() => _c = SportsChoices.read());
  }

  String _onOff(bool v) => v ? 'Activé' : 'Désactivé';

  @override
  Widget build(BuildContext context) {
    final all = _c.kinds.isEmpty;
    Widget head(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(t, style: const TextStyle(color: MaTvColors.mute, fontSize: 14, fontWeight: FontWeight.w700)),
    );
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: MaTvColors.ink),
                    ),
                    const Text('Sports · ce profil',
                        style: TextStyle(color: MaTvColors.ink, fontSize: 24, fontWeight: FontWeight.w800)),
                  ],
                ),
                head('Affichage'),
                _Tile(
                  autofocus: true,
                  icon: Icons.scoreboard_outlined,
                  label: 'Score sur la chaîne du match',
                  trailing: _onOff(_c.banner),
                  onTap: () => _do(() => SportsChoices.setBanner(!_c.banner)),
                ),
                _Tile(
                  icon: Icons.percent_rounded,
                  label: 'Afficher les cotes (jamais en mode enfants)',
                  trailing: _onOff(_c.odds),
                  onTap: () => _do(() => SportsChoices.setOdds(!_c.odds)),
                ),
                head('Mes sports'),
                _Tile(
                  icon: Icons.select_all_rounded,
                  label: 'Tous les sports',
                  trailing: all ? '✓' : null,
                  onTap: () => _do(SportsChoices.setAllKinds),
                ),
                for (final k in widget.kinds)
                  _Tile(
                    icon: Icons.sports_rounded,
                    label: k.name,
                    trailing: !all && _c.kinds.contains(k.id) ? '✓' : null,
                    onTap: () => _do(() => SportsChoices.toggleKind(k.id)),
                  ),
                head('Équipes et sportifs suivis'),
                _Tile(
                  icon: Icons.add_rounded,
                  label: 'Ajouter une équipe ou un sportif',
                  onTap: () async {
                    final team = await showDialog<String>(
                      context: context,
                      builder: (context) => _TeamPicker(teams: widget.teams, already: _c.teams),
                    );
                    if (team != null && team.trim().isNotEmpty) await _do(() => SportsChoices.toggleTeam(team.trim()));
                  },
                ),
                for (final t in _c.teams)
                  _Tile(
                    icon: Icons.star_rounded,
                    label: t,
                    trailing: 'Retirer',
                    onTap: () => _do(() => SportsChoices.toggleTeam(t)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Finds a team (or a fighter, a player) among the matches to come, or takes
/// the name as typed.
class _TeamPicker extends StatefulWidget {
  final List<String> teams;
  final List<String> already;

  const _TeamPicker({required this.teams, required this.already});

  @override
  State<_TeamPicker> createState() => _TeamPickerState();
}

class _TeamPickerState extends State<_TeamPicker> {
  final _field = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final taken = {for (final t in widget.already) t.toLowerCase()};
    final list = [
      for (final t in widget.teams)
        if (!taken.contains(t.toLowerCase()) && (q.isEmpty || t.toLowerCase().contains(q))) t,
    ].take(60).toList();
    return Dialog(
      backgroundColor: const Color(0xFF17171A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Ajouter une équipe ou un sportif',
                  style: TextStyle(color: MaTvColors.ink, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: _field,
                autofocus: true,
                style: const TextStyle(color: MaTvColors.ink, fontSize: 20),
                decoration: const InputDecoration(
                  hintText: 'PSG, Stade Toulousain, Ciryl Gane…',
                  hintStyle: TextStyle(color: MaTvColors.faint),
                  filled: true,
                  fillColor: Color(0xFF26262A),
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                ),
                onChanged: (v) => setState(() => _q = v),
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
              const SizedBox(height: 10),
              if (q.isNotEmpty)
                _Tile(
                  icon: Icons.add_rounded,
                  label: 'Ajouter « ${_q.trim()} »',
                  onTap: () => Navigator.of(context).pop(_q.trim()),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in list)
                      _Tile(icon: Icons.star_border_rounded, label: t, onTap: () => Navigator.of(context).pop(t)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
