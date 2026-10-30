import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/web_iptv.dart';

void main() {
  group('catalogue sur le web', () {
    test('Ma TV en HTTPS est permis', () {
      expect(webMayUseCatalog(isMaTv: true, portal: 'https://seedbox.example.com/iptv-checker/tv/xc'), isTrue);
    });

    test('Ma TV en HTTP ne l\'est pas (contenu mixte)', () {
      expect(webMayUseCatalog(isMaTv: true, portal: 'http://seedbox.example.com/tv/xc'), isFalse);
    });

    test('un fournisseur Xtream direct ne l\'est jamais, même en HTTPS', () {
      expect(webMayUseCatalog(isMaTv: false, portal: 'https://fournisseur.example.com'), isFalse);
      expect(webMayUseCatalog(isMaTv: false, portal: 'http://kimora3.clndf.com'), isFalse);
    });

    test('adresse vide ou cassée', () {
      expect(webMayUseCatalog(isMaTv: true, portal: ''), isFalse);
      expect(webMayUseCatalog(isMaTv: true, portal: 'https://'), isFalse);
    });
  });

  group('formats lus par le navigateur', () {
    test('MKV et MP4 sont essayés', () {
      expect(webUnplayableReason('mkv'), isNull);
      expect(webUnplayableReason('mp4'), isNull);
      expect(webUnplayableReason('MP4'), isNull);
    });

    test('AVI, TS… sont refusés avec un message en français', () {
      final reason = webUnplayableReason('avi');
      expect(reason, contains('.avi'));
      expect(reason, contains('navigateur'));
      expect(webUnplayableReason('.ts'), isNotNull);
    });

    test('extension lue dans l\'adresse de lecture', () {
      expect(extensionOfUrl('https://h/tv/xc/movie/vjod/k/123.mkv?q=1080&src=2'), 'mkv');
      expect(extensionOfUrl('https://h/tv/xc/series/vjod/k/9001.AVI'), 'avi');
      expect(extensionOfUrl('https://h/tv/xc/movie/vjod/k/123'), '');
    });
  });
}
