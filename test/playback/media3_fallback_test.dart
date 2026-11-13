import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/playback/media3_fallback.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moonfin/ui/screens/vjod_tv/tv_engine.dart' show tvExoWanted;

void main() {
  group('Media3 → mpv quand un format passe mal sur l\'appareil', () {
    test('la clé d\'un format : vidéo, plage, son choisi', () {
      final streams = <Map<String, dynamic>>[
        {'Type': 'Video', 'Codec': 'HEVC', 'VideoRangeType': 'HDR10'},
        {'Type': 'Audio', 'Codec': 'aac', 'Index': 1},
        {'Type': 'Audio', 'Codec': 'EAC3', 'Index': 2},
      ];
      expect(Media3Fallback.formatKey(streams, 2), 'hevc/HDR10/eac3');
      expect(Media3Fallback.formatKey(streams, null), 'hevc/HDR10/aac');
      expect(Media3Fallback.formatKey(const [], null), '?/?/?');
    });

    test('un plantage natif compte seulement si Media3 lisait', () {
      expect(Media3Fallback.isMedia3NativeCrash({'reason': 'native crash', 'state': 'hc=media3-main v=hevc route=/player/iptv'}), isTrue);
      expect(Media3Fallback.isMedia3NativeCrash({'reason': 'native crash', 'state': 'hc=none route=/home'}), isFalse);
      expect(Media3Fallback.isMedia3NativeCrash({'reason': 'ANR', 'state': 'hc=media3-main'}), isFalse);
    });

    test('deux rafales d\'images perdues font basculer, une seule fois ; les petites pertes ne comptent pas', () {
      final w = StutterWatch();
      expect(w.add(5, 1000), isFalse, reason: 'quelques images à un saut');
      expect(w.add(60, 120000), isFalse, reason: 'étalées sur deux minutes');
      expect(w.add(50, 8000), isFalse);
      expect(w.add(45, 10000), isTrue);
      expect(w.add(80, 5000), isFalse, reason: 'déjà basculé');
    });

    test('un plantage pendant un film : ce format passe sur mpv, et c\'est retenu', () async {
      SharedPreferences.setMockInitialValues({});
      final f = Media3Fallback.instance;
      await f.load();
      await f.playing('hevc/HDR10/eac3');
      expect(await f.afterExit({'reason': 'native crash', 'state': 'hc=media3-main'}), 'hevc/HDR10/eac3');
      expect(f.avoided, contains('hevc/HDR10/eac3'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(Media3Fallback.avoidKey), ['hevc/HDR10/eac3']);
      expect(await f.afterExit({'reason': 'ANR', 'state': 'hc=media3-main'}), isNull);
    });

    test('plantage d\u2019ExoPlayer en IPTV (XGIMI) : l\u2019IPTV passe sur mpv, aucun format du serveur n\u2019est accusé', () async {
      SharedPreferences.setMockInitialValues({});
      final f = Media3Fallback.instance;
      await f.load();
      await f.playing('h264/SDR/eac3'); // le dernier film du serveur
      await f.playing(Media3Fallback.iptvMark); // puis une chaîne en IPTV
      expect(await f.afterExit({'reason': 'native crash', 'state': 'hc=media3-main v=avc a=mp4a-latm route=/player/iptv'}), 'IPTV');
      expect(f.iptvAvoidsExo, isTrue);
      expect(f.avoided, isNot(contains('h264/SDR/eac3')));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(Media3Fallback.iptvAvoidKey), isTrue);
      await f.load();
      expect(f.iptvAvoidsExo, isTrue, reason: 'retenu après un redémarrage');
    });

    test('choix du lecteur IPTV : Auto passe sur mpv après un plantage ici, ExoPlayer choisi reste ExoPlayer', () {
      expect(tvExoWanted('auto', false), isTrue);
      expect(tvExoWanted('auto', true), isFalse);
      expect(tvExoWanted('exo', true), isTrue);
      expect(tvExoWanted('mpv', false), isFalse);
    });
  });
}
