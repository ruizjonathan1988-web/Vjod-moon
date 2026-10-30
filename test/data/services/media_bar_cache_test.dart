import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/media_bar_slide_item.dart';
import 'package:moonfin/data/services/media_bar_cache_store.dart';
import 'package:moonfin/util/startup_timeline.dart';

void main() {
  test('a banner slide comes back the same from the cache', () {
    const slide = MediaBarSlideItem(
      itemId: 'abc',
      serverId: 'srv',
      title: 'Dune',
      overview: 'Sable',
      backdropUrl: 'https://x/backdrop',
      year: 2021,
      genres: ['SF', 'Aventure'],
      runtime: Duration(minutes: 155),
      communityRating: 8.1,
      criticRating: 83,
      tmdbId: '438631',
      itemType: 'Movie',
      remoteTrailers: [
        {'Url': 'https://y/t'},
      ],
      kicker: 'Ce soir',
      role: MediaBarSlideItem.rolePick,
      progress: 0.4,
    );
    final json = jsonDecode(jsonEncode(MediaBarCacheStore.slideToJson(slide)))
        as Map<String, dynamic>;
    final back = MediaBarCacheStore.slideFromJson(json)!;
    expect(back.itemId, 'abc');
    expect(back.title, 'Dune');
    expect(back.genres, ['SF', 'Aventure']);
    expect(back.runtime, const Duration(minutes: 155));
    expect(back.communityRating, 8.1);
    expect(back.criticRating, 83);
    expect(back.remoteTrailers.single['Url'], 'https://y/t');
    expect(back.role, MediaBarSlideItem.rolePick);
    expect(back.progress, 0.4);
  });

  test('a broken slide is skipped', () {
    expect(MediaBarCacheStore.slideFromJson({'title': 'x'}), isNull);
  });

  test('start-up times read in seconds', () {
    expect(StartupTimeline.seconds(4400), '4,4 s');
    expect(StartupTimeline.seconds(12050), '12,1 s');
  });

  test('nothing is timed when the chronometer was never started', () {
    StartupTimeline.mark('Accueil affiché');
    // no throw, no state: finishing without a start saves nothing
    expect(StartupTimeline.finish('fin'), completes);
  });
}
