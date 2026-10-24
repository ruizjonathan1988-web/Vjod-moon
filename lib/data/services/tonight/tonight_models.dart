import 'dart:convert';

/// Who is watching tonight.
enum TonightCompany { alone, couple, family, friends }

/// How much time the evening leaves.
enum TonightTime {
  /// Under an hour and a half.
  short,

  /// A whole evening.
  evening,

  /// No limit.
  any;

  /// Minutes available, or null for no limit.
  int? get budgetMinutes => switch (this) {
    TonightTime.short => 95,
    TonightTime.evening => 210,
    TonightTime.any => null,
  };
}

/// What the evening calls for.
enum TonightMood { laugh, chills, escape, think, comfort, surprise }

/// The youngest child watching, which sets how far a family evening goes.
enum KidsAge {
  under7,
  from7to12,
  teen;

  /// The oldest age rating allowed.
  int get maxRatingAge => switch (this) {
    KidsAge.under7 => 6,
    KidsAge.from7to12 => 10,
    KidsAge.teen => 13,
  };
}

/// The kind of day an evening falls on. Friday and Saturday nights are
/// rarely spent like a Tuesday.
enum DayKind { weekday, friday, saturday, sunday }

/// The part of the day.
enum DayBand { daytime, evening, late }

/// When something is watched, as habits read it: the kind of day and the
/// part of it. Past midnight still belongs to the evening before.
class TonightSlot {
  final DayKind day;
  final DayBand band;

  const TonightSlot(this.day, this.band);

  factory TonightSlot.of(DateTime time) {
    final local = time.toLocal();
    // 00:00 to 04:59 is the end of the previous evening.
    final effective = local.hour < 5
        ? local.subtract(const Duration(hours: 5))
        : local;
    final band = local.hour < 5 || local.hour >= 22
        ? DayBand.late
        : local.hour >= 17
        ? DayBand.evening
        : DayBand.daytime;
    final day = switch (effective.weekday) {
      DateTime.friday => DayKind.friday,
      DateTime.saturday => DayKind.saturday,
      DateTime.sunday => DayKind.sunday,
      _ => DayKind.weekday,
    };
    return TonightSlot(day, band);
  }

  String get key => '${day.name}_${band.name}';

  @override
  bool operator ==(Object other) =>
      other is TonightSlot && other.day == day && other.band == band;

  @override
  int get hashCode => Object.hash(day, band);
}

/// The device a session runs on, as a weak hint of who is around.
enum TonightDevice { tv, phone }

/// What the viewer answered in the Tonight sheet.
class TonightAnswers {
  final TonightCompany company;
  final TonightTime time;
  final TonightMood mood;
  final KidsAge kidsAge;

  /// When these answers were given.
  final DateTime at;

  const TonightAnswers({
    required this.company,
    required this.time,
    required this.mood,
    required this.at,
    this.kidsAge = KidsAge.from7to12,
  });

  TonightAnswers copyWith({
    TonightCompany? company,
    TonightTime? time,
    TonightMood? mood,
    KidsAge? kidsAge,
    DateTime? at,
  }) => TonightAnswers(
    company: company ?? this.company,
    time: time ?? this.time,
    mood: mood ?? this.mood,
    kidsAge: kidsAge ?? this.kidsAge,
    at: at ?? this.at,
  );

  String encode() => jsonEncode({
    'company': company.name,
    'time': time.name,
    'mood': mood.name,
    'kids': kidsAge.name,
    'at': at.toUtc().toIso8601String(),
  });

  static TonightAnswers? decode(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      final json = jsonDecode(source);
      if (json is! Map) return null;
      final company = TonightCompany.values.asNameMap()[json['company']];
      final time = TonightTime.values.asNameMap()[json['time']];
      final mood = TonightMood.values.asNameMap()[json['mood']];
      final at = DateTime.tryParse(json['at'] as String? ?? '');
      if (company == null || time == null || mood == null || at == null) {
        return null;
      }
      return TonightAnswers(
        company: company,
        time: time,
        mood: mood,
        kidsAge:
            KidsAge.values.asNameMap()[json['kids']] ?? KidsAge.from7to12,
        at: at.toLocal(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// The age a rating string allows, or null when it can't be read.
///
/// Reads the forms Jellyfin libraries carry: French (`FR-12`, `Tous
/// publics`), US film (`PG-13`, `R`) and TV (`TV-Y7`, `TV-MA`), UK (`U`,
/// `12A`) and bare numbers.
int? ratingAge(String? rating) {
  if (rating == null) return null;
  var value = rating.trim().toUpperCase();
  if (value.isEmpty) return null;
  // Country prefixes: "FR-12", "DE-16", "GB-15".
  final prefixed = RegExp(r'^[A-Z]{2}[-/ ](.+)$').firstMatch(value);
  if (prefixed != null && !value.startsWith('TV-') && !value.startsWith('PG')) {
    value = prefixed.group(1)!.trim();
  }
  const exact = {
    'G': 0,
    'U': 0,
    'TP': 0,
    'TOUS PUBLICS': 0,
    'ALL': 0,
    'AL': 0,
    'TV-Y': 0,
    'TV-G': 0,
    'TV-Y7': 7,
    'TV-Y7-FV': 7,
    'PG': 10,
    'TV-PG': 10,
    'PG-13': 13,
    'TV-14': 14,
    'R': 17,
    'TV-MA': 17,
    'NC-17': 18,
    'X': 18,
    'XXX': 18,
    'NR': null,
    'UNRATED': null,
  };
  if (exact.containsKey(value)) return exact[value];
  final number = RegExp(r'(\d{1,2})').firstMatch(value);
  if (number != null) return int.tryParse(number.group(1)!);
  return null;
}
