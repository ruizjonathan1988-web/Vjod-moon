import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/tv_playlists.dart';
import 'package:moonfin/data/services/vjod/xtream_catalog.dart';

void main() {
  group('splitProviderName', () {
    test('reads the usual language prefixes', () {
      expect(splitProviderName('FR - Dune (2021)'), (tag: 'FR', name: 'Dune (2021)'));
      expect(splitProviderName('|EN| The Office'), (tag: 'EN', name: 'The Office'));
      expect(splitProviderName('[RU] Брат'), (tag: 'RU', name: 'Брат'));
      expect(splitProviderName('MULTI-LANG - Amélie'), (tag: 'MULTI-LANG', name: 'Amélie'));
    });

    test('leaves a name without prefix whole', () {
      expect(splitProviderName('Amélie'), (tag: '', name: 'Amélie'));
      expect(splitProviderName('Mission: Impossible'), (tag: '', name: 'Mission: Impossible'));
      expect(splitProviderName('FBI: Most Wanted'), (tag: '', name: 'FBI: Most Wanted'));
      expect(splitProviderName('X-Men'), (tag: '', name: 'X-Men'));
    });
  });

  group('parseVodStreams', () {
    test('keeps films with an id and a name, once each', () {
      final body = jsonEncode([
        {'stream_id': 12, 'name': 'FR - Dune', 'stream_icon': 'http://i/d.jpg', 'container_extension': 'mkv'},
        {'stream_id': '12', 'name': 'FR - Dune again'},
        {'stream_id': 13, 'name': 'EN - Heat'},
        {'name': 'no id'},
        'junk',
      ]);
      final films = parseVodStreams(body);
      expect(films.map((f) => f.id), ['12', '13']);
      expect(films.first.extension, 'mkv');
      expect(films.first.tag, 'FR');
      expect(films.last.extension, 'mp4');
      expect(films.first.kind, XtreamKind.movie);
    });
  });

  group('parseSeriesInfo', () {
    test('reads episodes keyed by season', () {
      final body = jsonEncode({
        'info': {'plot': 'Une série', 'cover': 'http://c'},
        'episodes': {
          '2': [
            {'id': '22', 'episode_num': 2, 'title': 'FR - Deux', 'container_extension': 'mp4'},
            {'id': '21', 'episode_num': 1, 'title': 'Un'},
          ],
          '1': [
            {'id': '11', 'episode_num': '1', 'title': '', 'info': {'plot': 'p'}},
          ],
        },
      });
      final info = parseSeriesInfo(body);
      expect(info.seasonNumbers, [1, 2]);
      expect(info.seasons[2]!.map((e) => e.id), ['21', '22']);
      expect(info.seasons[2]!.last.title, 'Deux');
      expect(info.seasons[1]!.single.title, 'Épisode 1');
      expect(info.seasons[1]!.single.extension, 'mkv');
      expect(info.plot, 'Une série');
    });

    test('reads episodes sent as a list of seasons', () {
      final body = jsonEncode({
        'episodes': [
          [
            {'id': '5', 'season': 3, 'episode_num': 1, 'title': 'A'},
          ],
        ],
      });
      expect(parseSeriesInfo(body).seasonNumbers, [3]);
    });

    test('survives an empty answer', () {
      expect(parseSeriesInfo('[]').seasons, isEmpty);
    });
  });

  group('searchTitles', () {
    final all = parseVodStreams(jsonEncode([
      {'stream_id': 1, 'name': 'FR - Dune : Deuxième partie'},
      {'stream_id': 2, 'name': 'EN - Dune'},
      {'stream_id': 3, 'name': 'FR - Les dunes'},
      {'stream_id': 4, 'name': 'FR - Amélie'},
    ]));

    test('ranks a name starting with the query first, shorter first', () {
      expect(searchTitles(all, 'dune').map((t) => t.id), ['2', '1', '3']);
    });

    test('ignores accents and needs every word', () {
      expect(searchTitles(all, 'amelie').single.id, '4');
      expect(searchTitles(all, 'dune partie').single.id, '1');
    });

    test('a one-letter query finds nothing', () {
      expect(searchTitles(all, 'd'), isEmpty);
    });
  });

  group('XtreamCatalog', () {
    test('uses the first complete Xtream source and builds play URLs', () {
      final catalog = XtreamCatalog.forPlaylists(const [
        TvPlaylist(id: 'a', name: 'm3u', url: 'http://m3u'),
        TvPlaylist(id: 'b', name: 'x', url: 'http://p:8080/', kind: TvPlaylistKind.xtream),
        TvPlaylist(
          id: 'c',
          name: 'x',
          url: 'http://p:8080/',
          kind: TvPlaylistKind.xtream,
          username: 'u',
          password: 'p w',
        ),
      ])!;
      final film = parseVodStreams(jsonEncode([
        {'stream_id': 9, 'name': 'Dune', 'container_extension': 'mkv'},
      ])).single;
      expect(catalog.movieUrl(film), 'http://p:8080/movie/u/p%20w/9.mkv');
      expect(
        catalog.episodeUrl(const XtreamEpisode(id: '7', season: 1, number: 1, title: 't', extension: 'mp4')),
        'http://p:8080/series/u/p%20w/7.mp4',
      );
    });

    test('no Xtream source, no catalogue', () {
      expect(XtreamCatalog.forPlaylists(const []), isNull);
    });
  });

  group('titleMatchKey', () {
    test('drops accents, bracketed years, quality tags and punctuation', () {
      expect(titleMatchKey('Dune : Deuxième Partie (2024) [4K]'), 'dune deuxieme partie');
      expect(titleMatchKey("Le Fabuleux Destin d'Amélie Poulain - 2001"), 'le fabuleux destin d amelie poulain');
    });

    test('keeps a bare number that is part of the title', () {
      expect(titleMatchKey('Blade Runner 2049'), 'blade runner 2049');
      expect(titleMatchKey('1917'), '1917');
    });
  });

  group('findProviderCopies', () {
    final all = [
      ...parseVodStreams(jsonEncode([
        {'stream_id': 1, 'name': 'FR - Dune : Deuxième partie (2024)'},
        {'stream_id': 2, 'name': 'EN - Dune: Part Two', 'tmdb': '693134'},
        {'stream_id': 3, 'name': 'FR - Dune (1984)'},
        {'stream_id': 4, 'name': 'FR - Dune (2021)'},
        {'stream_id': 5, 'name': 'FR - Blade Runner'},
        {'stream_id': 6, 'name': 'FR - Blade Runner 2049 (2017)'},
        {'stream_id': 7, 'name': 'EN - Dune 2021'},
        {'stream_id': 8, 'name': 'FR - Dune', 'tmdb': '841'},
      ])),
      ...parseSeriesList(jsonEncode([
        {'series_id': 50, 'name': 'FR - Dune (2021)'},
      ])),
    ];

    test('finds every language by TMDB id, then by title and year', () {
      final copies = findProviderCopies(
        all,
        kind: XtreamKind.movie,
        tmdbId: 693134,
        titles: ['Dune : Deuxième partie'],
        year: 2024,
      );
      expect(copies.map((c) => c.id), ['2', '1']);
    });

    test('the year tells remakes apart, a bare year counts only when it is the one', () {
      final copies = findProviderCopies(
        all,
        kind: XtreamKind.movie,
        tmdbId: 438631,
        titles: ['Dune'],
        year: 2021,
      );
      // 8 is filed under another TMDB id, 3 is from 1984, 50 is a series.
      expect(copies.map((c) => c.id), ['4', '7']);
    });

    test('Blade Runner 2049 is not Blade Runner', () {
      final copies = findProviderCopies(
        all,
        kind: XtreamKind.movie,
        titles: ['Blade Runner 2049'],
        year: 2017,
      );
      expect(copies.map((c) => c.id), ['6']);
    });

    test('nothing to look for, nothing found', () {
      expect(findProviderCopies(all, kind: XtreamKind.movie), isEmpty);
    });
  });

  group('languages', () {
    final copies = parseVodStreams(jsonEncode([
      {'stream_id': 1, 'name': 'EN - Dune'},
      {'stream_id': 2, 'name': 'RU - Dune'},
      {'stream_id': 3, 'name': 'Dune'},
      {'stream_id': 4, 'name': 'FR - Dune'},
      {'stream_id': 5, 'name': 'ZH - Dune'},
    ]));

    test('the profile languages come first, in its order', () {
      expect(
        orderByLanguages(copies, ['FR', 'RU']).map((c) => c.id),
        ['4', '2', '1', '3', '5'],
      );
    });

    test('no preference keeps the provider order', () {
      expect(orderByLanguages(copies, const []).map((c) => c.id), ['1', '2', '3', '4', '5']);
    });

    test('CN and ZH, EN and UK are one language', () {
      expect(isPreferredLanguage('ZH', ['CN']), isTrue);
      expect(isPreferredLanguage('UK', ['EN']), isTrue);
      expect(isPreferredLanguage('RU', ['EN']), isFalse);
      expect(isPreferredLanguage('FR', const []), isFalse);
    });

    test('search puts the profile language first among equal matches', () {
      expect(searchTitles(copies, 'dune', preferredTags: ['RU']).first.id, '2');
    });
  });

  group('languageName', () {
    test('spells the language out in French', () {
      expect(languageName('RU'), 'Russe');
      expect(languageName('ZH'), 'Chinois');
      expect(languageName('UK'), 'Anglais');
      expect(languageName('MULTI-LANG'), 'Multilingue');
      expect(languageName('XYZ'), 'XYZ');
    });

    test('a play button reads naturally', () {
      expect(languageButtonPhrase('RU'), 'en russe');
      expect(languageButtonPhrase('MULTI-LANG'), '· Multilingue');
      expect(languageButtonPhrase('XYZ'), '· XYZ');
      expect(languageButtonPhrase(''), '');
    });
  });

  group('catalogue saved on the device', () {
    test('reads back what it wrote', () {
      final titles = [
        ...parseVodStreams(jsonEncode([
          {'stream_id': 1, 'name': 'RU - Брат (1997)', 'stream_icon': 'http://i', 'container_extension': 'mkv', 'tmdb': '20992'},
        ])),
        ...parseSeriesList(jsonEncode([
          {'series_id': 2, 'name': 'EN - The Office'},
        ])),
      ];
      final back = decodeCatalogCache(
        encodeCatalogCache((fetchedAtMs: 1234, titles: titles)),
      )!;
      expect(back.fetchedAtMs, 1234);
      expect(back.titles.length, 2);
      final film = back.titles.first;
      expect([film.kind, film.id, film.name, film.tag, film.poster, film.extension, film.tmdbId, film.year],
          [XtreamKind.movie, '1', 'Брат (1997)', 'RU', 'http://i', 'mkv', '20992', 1997]);
      expect(back.titles.last.kind, XtreamKind.series);
      expect(back.titles.last.year, isNull);
      expect(searchTitles(back.titles, 'office').single.id, '2');
    });

    test('anything else reads as nothing', () {
      expect(decodeCatalogCache('not json'), isNull);
      expect(decodeCatalogCache('{"v":2}'), isNull);
    });

    test('the file name is stable and hides the account', () {
      final key = catalogCacheKey('http://p:8080', 'user');
      expect(key, catalogCacheKey('http://p:8080', 'user'));
      expect(key, isNot(catalogCacheKey('http://p:8080', 'other')));
      expect(key, matches(RegExp(r'^[0-9a-f]{8}$')));
    });
  });
}
