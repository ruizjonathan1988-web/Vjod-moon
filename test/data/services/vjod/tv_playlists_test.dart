import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/tv_playlists.dart';

void main() {
  group('TvPlaylist.m3uUrl', () {
    test('an M3U source returns its own trimmed URL', () {
      const p = TvPlaylist(
        id: '1',
        name: 'FR gratuit',
        url: '  https://iptv-org.github.io/iptv/countries/fr.m3u  ',
      );
      expect(p.m3uUrl, 'https://iptv-org.github.io/iptv/countries/fr.m3u');
    });

    test('an Xtream source builds the get.php URL and trims trailing slashes',
        () {
      const p = TvPlaylist(
        id: '2',
        name: 'Mon portail',
        url: 'http://host.example:8080//',
        kind: TvPlaylistKind.xtream,
        username: 'a b',
        password: 'p@ss',
      );
      expect(
        p.m3uUrl,
        'http://host.example:8080/get.php'
        '?username=a%20b&password=p%40ss&type=m3u_plus&output=ts',
      );
    });

    test('an incomplete Xtream source yields an empty link', () {
      const p = TvPlaylist(
        id: '3',
        name: 'Incomplet',
        url: 'http://host.example:8080',
        kind: TvPlaylistKind.xtream,
        username: 'only-user',
      );
      expect(p.m3uUrl, '');
    });
  });

  group('TvPlaylists encode/decode', () {
    test('round-trips a mixed list', () {
      final list = [
        const TvPlaylist(id: '1', name: 'A', url: 'https://a/x.m3u'),
        const TvPlaylist(
          id: '2',
          name: 'B',
          url: 'http://b:80',
          kind: TvPlaylistKind.xtream,
          username: 'u',
          password: 'p',
          epgUrl: 'https://b/epg.xml',
        ),
      ];
      final back = TvPlaylists.decode(TvPlaylists.encode(list));
      expect(back.length, 2);
      expect(back[0].kind, TvPlaylistKind.m3u);
      expect(back[1].username, 'u');
      expect(back[1].epgUrl, 'https://b/epg.xml');
    });

    test('empty or malformed input decodes to an empty list', () {
      expect(TvPlaylists.decode(null), isEmpty);
      expect(TvPlaylists.decode(''), isEmpty);
      expect(TvPlaylists.decode('not json'), isEmpty);
      expect(TvPlaylists.decode('{"not":"a list"}'), isEmpty);
    });

    test('skips entries missing an id, name or url', () {
      const json =
          '[{"name":"no id","url":"u"},{"id":"ok","name":"n","url":"u"}]';
      final back = TvPlaylists.decode(json);
      expect(back.length, 1);
      expect(back.single.id, 'ok');
    });
  });
}
