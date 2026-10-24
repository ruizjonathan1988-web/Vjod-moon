import 'dart:math' as math;

import '../seerr/taste_profile.dart';
import 'evening_journal.dart';
import 'tonight_models.dart';

/// What a set of sittings says: which genres held the viewer, movies or
/// series, how long a film tends to be, and who was around.
class HabitProfile {
  /// Sittings behind it, discounted by age.
  final double weight;

  /// Each genre's share of what was watched through, 0 to 1, summing to 1.
  final Map<TasteGenre, double> genreShare;

  /// Each genre's share of what was dropped early.
  final Map<TasteGenre, double> dropShare;

  /// Share of sittings that were movies.
  final double movieShare;

  /// Typical length of a movie watched through, in minutes.
  final double? typicalMovieMinutes;
  final Map<TonightCompany, double> companyShare;

  const HabitProfile({
    this.weight = 0,
    this.genreShare = const {},
    this.dropShare = const {},
    this.movieShare = 0.5,
    this.typicalMovieMinutes,
    this.companyShare = const {},
  });

  static const empty = HabitProfile();

  /// How much of this profile to believe, 0 to 1. A handful of sittings
  /// says little.
  double confidence({double prior = 6}) => weight / (weight + prior);

  /// This profile, pulled towards [other] where it knows little: [other]
  /// counts as [prior] sittings.
  HabitProfile blendedWith(HabitProfile other, {double prior = 6}) {
    final own = weight / (weight + prior);
    if (own >= 1) return this;
    Map<K, double> mix<K>(Map<K, double> a, Map<K, double> b) => {
      for (final key in {...a.keys, ...b.keys})
        key: (a[key] ?? 0) * own + (b[key] ?? 0) * (1 - own),
    };
    final minutes = typicalMovieMinutes == null
        ? other.typicalMovieMinutes
        : other.typicalMovieMinutes == null
        ? typicalMovieMinutes
        : typicalMovieMinutes! * own + other.typicalMovieMinutes! * (1 - own);
    return HabitProfile(
      weight: weight,
      genreShare: mix(genreShare, other.genreShare),
      dropShare: mix(dropShare, other.dropShare),
      movieShare: movieShare * own + other.movieShare * (1 - own),
      typicalMovieMinutes: minutes,
      companyShare: mix(companyShare, other.companyShare),
    );
  }

  /// How well [genres] match what was watched through, 0 to 1, minus a
  /// share of what was dropped.
  double genreFit(Set<TasteGenre> genres) {
    if (genres.isEmpty) return 0;
    var fit = 0.0;
    var drop = 0.0;
    for (final genre in genres) {
      fit += genreShare[genre] ?? 0;
      drop += dropShare[genre] ?? 0;
    }
    return fit - 0.5 * drop;
  }

  /// The company seen most, if one clearly leads.
  TonightCompany? get usualCompany {
    if (companyShare.isEmpty) return null;
    final best = companyShare.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    return best.value >= 0.5 ? best.key : null;
  }

  /// The genres seen most, best first.
  List<TasteGenre> get topGenres =>
      (genreShare.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .map((e) => e.key)
          .toList();

  static HabitProfile from(Iterable<JournalEntry> entries, DateTime now) {
    var weight = 0.0;
    final liked = <TasteGenre, double>{};
    final dropped = <TasteGenre, double>{};
    var movies = 0.0;
    var total = 0.0;
    final companies = <TonightCompany, double>{};
    var companyTotal = 0.0;
    final runtimes = <({double minutes, double weight})>[];

    for (final entry in entries) {
      final age = now.difference(entry.at).inHours / 24;
      // Tastes drift: a sitting three months old counts half.
      final w = math.pow(0.5, math.max(0, age) / 90).toDouble();
      weight += w;
      total += w;
      if (entry.mediaType == 'movie') movies += w;
      if (entry.company case final company?) {
        companies[company] = (companies[company] ?? 0) + w;
        companyTotal += w;
      }
      final outcome = entry.outcome;
      if (entry.genres.isNotEmpty) {
        final share = w / entry.genres.length;
        for (final genre in entry.genres) {
          if (outcome > 0) {
            liked[genre] = (liked[genre] ?? 0) + share * outcome;
          } else {
            dropped[genre] = (dropped[genre] ?? 0) + share * -outcome;
          }
        }
      }
      final minutes = entry.runtimeMinutes;
      if (entry.mediaType == 'movie' &&
          outcome > 0 &&
          minutes != null &&
          minutes > 0) {
        runtimes.add((minutes: minutes.toDouble(), weight: w));
      }
    }

    Map<K, double> normalize<K>(Map<K, double> map) {
      final sum = map.values.fold(0.0, (a, b) => a + b);
      if (sum <= 0) return const {};
      return {for (final e in map.entries) e.key: e.value / sum};
    }

    double? weightedMedian(List<({double minutes, double weight})> values) {
      if (values.isEmpty) return null;
      values.sort((a, b) => a.minutes.compareTo(b.minutes));
      final half = values.fold(0.0, (a, b) => a + b.weight) / 2;
      var run = 0.0;
      for (final value in values) {
        run += value.weight;
        if (run >= half) return value.minutes;
      }
      return values.last.minutes;
    }

    return HabitProfile(
      weight: weight,
      genreShare: normalize(liked),
      dropShare: normalize(dropped),
      movieShare: total > 0 ? movies / total : 0.5,
      typicalMovieMinutes: weightedMedian(runtimes),
      companyShare: companyTotal > 0
          ? {for (final e in companies.entries) e.key: e.value / companyTotal}
          : const {},
    );
  }
}

/// Habits by time slot, by company and by device, each leaning on the
/// broader picture where it has little to go on.
class HabitModel {
  final HabitProfile global;
  final Map<TonightSlot, HabitProfile> bySlot;
  final Map<DayBand, HabitProfile> byBand;
  final Map<TonightCompany, HabitProfile> byCompany;
  final Map<TonightDevice, HabitProfile> byDevice;

  const HabitModel({
    required this.global,
    this.bySlot = const {},
    this.byBand = const {},
    this.byCompany = const {},
    this.byDevice = const {},
  });

  static const empty = HabitModel(global: HabitProfile.empty);

  /// Sittings behind everything, discounted by age.
  double get weight => global.weight;

  factory HabitModel.build(Iterable<JournalEntry> entries, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final list = entries.where((e) => !e.at.isAfter(at)).toList();
    Map<K, HabitProfile> group<K>(K? Function(JournalEntry) keyOf) {
      final groups = <K, List<JournalEntry>>{};
      for (final entry in list) {
        final key = keyOf(entry);
        if (key == null) continue;
        (groups[key] ??= []).add(entry);
      }
      return {
        for (final e in groups.entries) e.key: HabitProfile.from(e.value, at),
      };
    }

    return HabitModel(
      global: HabitProfile.from(list, at),
      bySlot: group((e) => e.slot),
      byBand: group((e) => e.slot.band),
      byCompany: group((e) => e.company),
      byDevice: group((e) => e.device),
    );
  }

  /// The habits that fit an evening: the slot's own, leaning on the part of
  /// the day and then on everything, then nudged by who is there.
  HabitProfile forContext({
    required TonightSlot slot,
    TonightCompany? company,
    TonightDevice? device,
  }) {
    final band = (byBand[slot.band] ?? HabitProfile.empty).blendedWith(global);
    var profile = (bySlot[slot] ?? HabitProfile.empty).blendedWith(band);
    if (company != null) {
      final withCompany = byCompany[company];
      if (withCompany != null && withCompany.weight > 0) {
        // Who is there matters as much as when: an evening with the kids
        // looks like other evenings with the kids.
        profile = withCompany.blendedWith(profile, prior: 4);
      }
    } else if (device != null) {
      final onDevice = byDevice[device];
      if (onDevice != null && onDevice.weight > 0) {
        profile = profile.blendedWith(onDevice, prior: 12);
      }
    }
    return profile;
  }

  /// Who is usually around in this slot on this device, to preselect.
  TonightCompany? suggestCompany(TonightSlot slot, TonightDevice? device) {
    final inSlot = bySlot[slot];
    if (inSlot != null && inSlot.weight >= 3) {
      if (inSlot.usualCompany case final company?) return company;
    }
    if (device != null) {
      final onDevice = byDevice[device];
      if (onDevice != null && onDevice.weight >= 3) {
        if (onDevice.usualCompany case final company?) return company;
      }
    }
    return null;
  }
}
