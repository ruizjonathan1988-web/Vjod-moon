// Sports (VJOD 4.6, Ma TV 3.55): the day's matches with the live score, the
// odds and the channels that show them. Ma TV reads them for the whole house
// (Kambi, the engine behind Unibet, in French); VJOD only asks Ma TV.
//
// Everything a profile chooses (sports, odds, banner, teams, reminders) is a
// scoped preference, so each profile has its own. The decisions are plain
// functions, tested without a device.
import 'package:get_it/get_it.dart';

import '../../../preference/user_preferences.dart';

class SportChannel {
  final String id;
  final int number;
  final String name;

  const SportChannel({required this.id, required this.number, required this.name});

  factory SportChannel.fromJson(Map<String, dynamic> j) => SportChannel(
    id: j['id']?.toString() ?? '',
    number: (j['num'] as num?)?.toInt() ?? 0,
    name: j['name']?.toString() ?? '',
  );
}

/// A goal, or points, seen by Ma TV when the score changed.
class SportMoment {
  final String text;
  final int? minute;
  final DateTime at;

  const SportMoment({required this.text, required this.at, this.minute});

  String get label => minute == null ? text : '$text ($minute’)';
}

class SportEvent {
  final String id;
  final String sport;
  final String sportName;
  final String competition;
  final String country;
  final String home;
  final String away;
  final DateTime start;

  /// pre, live or end.
  final String state;
  final List<String>? score;
  final List<List<int>>? sets;
  final int? minute;
  final String? period;

  /// « 1 », « N », « 2 » → decimal odds.
  final Map<String, double> odds;
  final SportMoment? last;
  final List<SportChannel> channels;

  const SportEvent({
    required this.id,
    required this.sport,
    required this.sportName,
    required this.competition,
    required this.country,
    required this.home,
    required this.away,
    required this.start,
    required this.state,
    this.score,
    this.sets,
    this.minute,
    this.period,
    this.odds = const {},
    this.last,
    this.channels = const [],
  });

  bool get live => state == 'live';
  bool get finished => state == 'end';

  factory SportEvent.fromJson(Map<String, dynamic> j) {
    List<String>? score;
    if (j['score'] is List && (j['score'] as List).length == 2) {
      score = [for (final x in j['score'] as List) x.toString()];
    }
    List<List<int>>? sets;
    if (j['sets'] is List && (j['sets'] as List).length == 2) {
      sets = [
        for (final side in j['sets'] as List)
          [if (side is List) for (final x in side) if (x is num) x.toInt()],
      ];
    }
    final odds = <String, double>{};
    if (j['odds'] is Map) {
      (j['odds'] as Map).forEach((k, v) {
        if (v is num) odds[k.toString()] = v.toDouble();
      });
    }
    SportMoment? last;
    if (j['last'] is Map) {
      final l = Map<String, dynamic>.from(j['last'] as Map);
      last = SportMoment(
        text: l['text']?.toString() ?? '',
        minute: (l['min'] as num?)?.toInt(),
        at: DateTime.fromMillisecondsSinceEpoch(((l['at'] as num?)?.toInt() ?? 0) * 1000),
      );
    }
    return SportEvent(
      id: j['id']?.toString() ?? '',
      sport: j['sport']?.toString() ?? '',
      sportName: j['sportName']?.toString() ?? '',
      competition: j['comp']?.toString() ?? '',
      country: j['country']?.toString() ?? '',
      home: j['home']?.toString() ?? '',
      away: j['away']?.toString() ?? '',
      start: DateTime.fromMillisecondsSinceEpoch(((j['start'] as num?)?.toInt() ?? 0) * 1000),
      state: j['state']?.toString() ?? 'pre',
      score: score,
      sets: sets,
      minute: (j['minute'] as num?)?.toInt(),
      period: j['period']?.toString(),
      odds: odds,
      last: last,
      channels: [
        if (j['chans'] is List)
          for (final c in j['chans'] as List)
            if (c is Map) SportChannel.fromJson(Map<String, dynamic>.from(c)),
      ],
    );
  }

  /// « 2 – 1 », the sets for tennis (« 6-4 3-5 »), or empty before kick-off.
  String get scoreText {
    final s = sets;
    if (s != null && s[0].isNotEmpty) {
      return [for (var i = 0; i < s[0].length && i < s[1].length; i++) '${s[0][i]}-${s[1][i]}'].join(' ');
    }
    final sc = score;
    return sc == null ? '' : '${sc[0]} – ${sc[1]}';
  }

  /// What the corner of the card says: the minute, the period, « Terminé »
  /// or the kick-off time.
  String get clockText {
    if (finished) return 'Terminé';
    if (live) {
      if (minute != null) return '$minute’';
      return period?.isNotEmpty == true ? period! : 'En direct';
    }
    final h = start.hour.toString().padLeft(2, '0');
    final m = start.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class SportKind {
  final String id;
  final String name;

  const SportKind(this.id, this.name);
}

class MaTvSports {
  final List<SportEvent> events;
  final List<SportKind> kinds;

  /// Where the scores come from, null when Ma TV could not read them yet.
  final String? source;
  final String? error;

  const MaTvSports({this.events = const [], this.kinds = const [], this.source, this.error});

  factory MaTvSports.fromJson(Map<String, dynamic> j) => MaTvSports(
    events: [
      if (j['events'] is List)
        for (final e in j['events'] as List)
          if (e is Map) SportEvent.fromJson(Map<String, dynamic>.from(e)),
    ],
    kinds: [
      if (j['sports'] is List)
        for (final s in j['sports'] as List)
          if (s is Map) SportKind(s['id']?.toString() ?? '', s['name']?.toString() ?? ''),
    ],
    source: j['source']?.toString(),
    error: j['error']?.toString(),
  );
}

// ------------------------------------------------------------------ choices
String _norm(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Whether [team] (as followed) is one of the two sides of [e].
bool followsTeam(SportEvent e, String team) {
  final k = _norm(team);
  if (k.isEmpty) return false;
  for (final side in [e.home, e.away]) {
    final n = _norm(side);
    if (n == k || n.split(' ').contains(k) || k.contains(n)) return true;
  }
  return false;
}

bool followsAny(SportEvent e, Iterable<String> teams) => teams.any((t) => followsTeam(e, t));

/// Odds are shown when the profile wants them, never in Kids Mode.
bool showSportOdds({required bool wanted, required bool kids}) => wanted && !kids;

List<String> splitList(String raw, String sep) =>
    [for (final x in raw.split(sep)) if (x.trim().isNotEmpty) x.trim()];

String joinList(Iterable<String> items, String sep) => items.where((x) => x.trim().isNotEmpty).join(sep);

/// Adds or removes [item] from a stored list.
String toggleInList(String raw, String item, String sep) {
  final items = splitList(raw, sep);
  final at = items.indexWhere((x) => x.toLowerCase() == item.toLowerCase());
  if (at >= 0) {
    items.removeAt(at);
  } else {
    items.add(item);
  }
  return joinList(items, sep);
}

/// Matches whose state just went from « pre » to « live » and that the
/// profile asked about (a reminder, or a followed team): told once each.
List<SportEvent> kickOffs(
  Map<String, String> before,
  List<SportEvent> now, {
  required Set<String> reminders,
  required List<String> teams,
}) => [
  for (final e in now)
    if (e.live && before[e.id] == 'pre' && (reminders.contains(e.id) || followsAny(e, teams))) e,
];

/// The settings of the profile signed in now.
class SportsChoices {
  final bool on;
  final bool banner;
  final bool odds;
  final List<String> kinds;
  final List<String> teams;
  final Set<String> reminders;

  const SportsChoices({
    this.on = true,
    this.banner = true,
    this.odds = true,
    this.kinds = const [],
    this.teams = const [],
    this.reminders = const {},
  });

  static UserPreferences? get _prefs {
    final getIt = GetIt.instance;
    return getIt.isRegistered<UserPreferences>() ? getIt<UserPreferences>() : null;
  }

  static SportsChoices read() {
    final p = _prefs;
    if (p == null) return const SportsChoices();
    final kids = p.get(UserPreferences.kidsModeEnabled);
    return SportsChoices(
      on: p.get(UserPreferences.vjodSportsOn),
      banner: p.get(UserPreferences.vjodSportsBanner),
      odds: showSportOdds(wanted: p.get(UserPreferences.vjodSportsOdds), kids: kids),
      kinds: splitList(p.get(UserPreferences.vjodSportsKinds), ','),
      teams: splitList(p.get(UserPreferences.vjodSportsTeams), '|'),
      reminders: splitList(p.get(UserPreferences.vjodSportsReminders), '|').toSet(),
    );
  }

  static Future<void> setOn(bool v) async => _prefs?.set(UserPreferences.vjodSportsOn, v);
  static Future<void> setBanner(bool v) async => _prefs?.set(UserPreferences.vjodSportsBanner, v);
  static Future<void> setOdds(bool v) async => _prefs?.set(UserPreferences.vjodSportsOdds, v);

  static Future<void> toggleKind(String id) async {
    final p = _prefs;
    if (p == null) return;
    await p.set(UserPreferences.vjodSportsKinds, toggleInList(p.get(UserPreferences.vjodSportsKinds), id, ','));
  }

  static Future<void> setAllKinds() async => _prefs?.set(UserPreferences.vjodSportsKinds, '');

  static Future<void> toggleTeam(String team) async {
    final p = _prefs;
    if (p == null) return;
    await p.set(UserPreferences.vjodSportsTeams, toggleInList(p.get(UserPreferences.vjodSportsTeams), team, '|'));
  }

  static Future<void> toggleReminder(String id) async {
    final p = _prefs;
    if (p == null) return;
    // Old reminders don't pile up: the last 40 are kept.
    final items = splitList(toggleInList(p.get(UserPreferences.vjodSportsReminders), id, '|'), '|');
    await p.set(
      UserPreferences.vjodSportsReminders,
      joinList(items.length > 40 ? items.sublist(items.length - 40) : items, '|'),
    );
  }
}
