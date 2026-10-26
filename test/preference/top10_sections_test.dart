import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/preference/home_section_config.dart';
import 'package:moonfin/preference/preference_constants.dart';

List<HomeSectionConfig> load(List<Map<String, Object>> saved) =>
    HomeSectionConfig.fromJsonString(jsonEncode(saved));

List<HomeSectionType> ordered(List<HomeSectionConfig> sections) => [
  for (final c in [...sections]..sort((a, b) => a.order.compareTo(b.order)))
    c.type,
];

void main() {
  test('a fresh install opens on the VJOD rows, one Top 10 for both', () {
    final enabled = [
      for (final c in HomeSectionConfig.defaults())
        if (c.enabled) c,
    ]..sort((a, b) => a.order.compareTo(b.order));
    final on = [for (final c in enabled) c.type];
    expect(on, [
      HomeSectionType.vjodMood,
      HomeSectionType.resume,
      HomeSectionType.nextUp,
      HomeSectionType.seerrMyRequests,
      HomeSectionType.seerrForYou,
      HomeSectionType.latestMedia,
      HomeSectionType.vjodUnwatchedGems,
      HomeSectionType.top10Movies,
      HomeSectionType.seerrBecause,
      HomeSectionType.seerrSagas,
      HomeSectionType.vjodThemeOfDay,
      HomeSectionType.seerrWatchlist,
      HomeSectionType.frenchMovies,
      HomeSectionType.vjodShortGems,
      HomeSectionType.vjodMiniSeries,
      HomeSectionType.seasonal,
      HomeSectionType.vjodOutsideHabits,
    ]);
    // Off rather than gone, so the settings can bring it back.
    expect(
      HomeSectionConfig.defaults().where(
        (c) => c.type == HomeSectionType.top10Series && !c.enabled,
      ),
      hasLength(1),
    );
  });

  test('the old Top 10 becomes the films one, with series right under it', () {
    final sections = load([
      {'type': 'resume', 'enabled': true, 'order': 0},
      {'type': 'top10', 'enabled': true, 'order': 1},
      {'type': 'nextup', 'enabled': true, 'order': 2},
    ]);
    final types = ordered(sections);
    final films = types.indexOf(HomeSectionType.top10Movies);
    // The VJOD mood comes first, above what was saved.
    expect(types.first, HomeSectionType.vjodMood);
    expect(films, 2);
    expect(types[films + 1], HomeSectionType.top10Series);
    expect(types.indexOf(HomeSectionType.nextUp), greaterThan(films + 1));
  });

  test('a Top 10 switched off keeps the series one off too', () {
    final sections = load([
      {'type': 'top10', 'enabled': false, 'order': 0},
    ]);
    final series = sections.firstWhere(
      (c) => c.type == HomeSectionType.top10Series,
    );
    expect(series.enabled, isFalse);
  });

  test('a layout already listing both is left alone', () {
    final sections = load([
      {'type': 'top10_series', 'enabled': false, 'order': 0},
      {'type': 'top10_movies', 'enabled': true, 'order': 5},
    ]);
    expect(
      sections.where((c) => c.type == HomeSectionType.top10Series),
      hasLength(1),
    );
    expect(
      sections.firstWhere((c) => c.type == HomeSectionType.top10Series).order,
      0,
    );
  });

  test('the French rows come right after the Top 10 series', () {
    final sections = load([
      {'type': 'top10_movies', 'enabled': true, 'order': 0},
      {'type': 'top10_series', 'enabled': true, 'order': 1},
      {'type': 'nextup', 'enabled': true, 'order': 2},
    ]);
    final types = ordered(sections);
    final series = types.indexOf(HomeSectionType.top10Series);
    expect(types[series + 1], HomeSectionType.frenchMovies);
    expect(types[series + 2], HomeSectionType.frenchSeries);
    expect(types[series + 3], HomeSectionType.frenchClassics);
    expect(types[series + 4], HomeSectionType.nextUp);
  });

  test('the French rows stay off when the Top 10 series is off', () {
    final sections = load([
      {'type': 'top10_series', 'enabled': false, 'order': 0},
    ]);
    for (final type in [
      HomeSectionType.frenchMovies,
      HomeSectionType.frenchSeries,
      HomeSectionType.frenchClassics,
    ]) {
      expect(sections.firstWhere((c) => c.type == type).enabled, isFalse);
    }
  });

  test('the VJOD rows join a saved layout where they belong', () {
    final sections = load([
      {'type': 'resume', 'enabled': true, 'order': 0},
      {'type': 'nextup', 'enabled': true, 'order': 1},
      {'type': 'top10_movies', 'enabled': true, 'order': 2},
      {'type': 'seerr_for_you', 'enabled': false, 'order': 3},
    ]);
    final types = ordered(sections);
    expect(types.first, HomeSectionType.vjodMood);
    expect(
      types[types.indexOf(HomeSectionType.nextUp) + 1],
      HomeSectionType.vjodUnwatchedGems,
    );
    expect(
      types.indexOf(HomeSectionType.vjodBinge),
      greaterThan(types.indexOf(HomeSectionType.vjodOutsideHabits)),
    );
    // Each VJOD row arrives as the recommended layout has it: the main
    // ones on, the extra moods off but ready in the settings.
    final recommended = {
      for (final c in HomeSectionConfig.defaults()) c.type: c.enabled,
    };
    for (final c in sections) {
      if (c.type.isVjodRow) {
        expect(c.enabled, recommended[c.type], reason: '${c.type}');
      }
    }
  });
}
