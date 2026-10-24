import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/trakt/trakt_client.dart';

Map<String, Object?> movieEntry(Object? tmdb) => {
  'watcher_count': 10,
  'movie': {
    'title': 'Film',
    'ids': {'trakt': 1, 'tmdb': tmdb},
  },
};

void main() {
  group('parseTraktTitles', () {
    test('reads a recommendation list, where titles are not wrapped', () {
      final ids = parseTraktTitles([
        {
          'title': 'Film',
          'year': 2024,
          'ids': {'trakt': 3, 'tmdb': 550},
        },
        {
          'title': 'Other',
          'ids': {'tmdb': 603},
        },
      ], mediaType: 'movie');
      expect(ids, [550, 603]);
    });


    test('keeps the TMDB ids in chart order', () {
      final ids = parseTraktTitles([
        movieEntry(603),
        movieEntry(550),
      ], mediaType: 'movie');
      expect(ids, [603, 550]);
    });

    test('reads series under their own key', () {
      final ids = parseTraktTitles([
        {
          'watchers': 4,
          'show': {
            'title': 'Serie',
            'ids': {'tmdb': 1396},
          },
        },
      ], mediaType: 'tv');
      expect(ids, [1396]);
    });

    test('skips what Trakt could not match to TMDB', () {
      final ids = parseTraktTitles([
        movieEntry(null),
        movieEntry(603),
        {'movie': {'title': 'No ids'}},
        'junk',
      ], mediaType: 'movie');
      expect(ids, [603]);
    });

    test('a film is not read as a series', () {
      expect(parseTraktTitles([movieEntry(603)], mediaType: 'tv'), isEmpty);
    });

    test('an answer that is not a list gives an empty chart', () {
      expect(parseTraktTitles({'error': 'oops'}, mediaType: 'movie'), isEmpty);
      expect(parseTraktTitles(null, mediaType: 'movie'), isEmpty);
    });

    test('a title listed twice counts once', () {
      expect(
        parseTraktTitles([movieEntry(7), movieEntry(7)], mediaType: 'movie'),
        [7],
      );
    });
  });

  group('linking an account', () {
    test('reads the code to show the viewer', () {
      final code = TraktDeviceCode.fromJson({
        'device_code': 'abc',
        'user_code': 'JYJN2KEG',
        'verification_url': 'https://auth.trakt.tv/activate',
        'expires_in': 600,
        'interval': 6,
      });
      expect(code.userCode, 'JYJN2KEG');
      expect(code.expiresIn, const Duration(minutes: 10));
      expect(code.interval, const Duration(seconds: 6));
    });

    test('dates the tokens from when Trakt made them', () {
      final tokens = TraktTokens.fromJson({
        'access_token': 'a',
        'refresh_token': 'r',
        'expires_in': 86400,
        'created_at': 1792616857,
      });
      expect(
        tokens.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1792616857 * 1000)
            .add(const Duration(days: 1)),
      );
    });
  });
}
