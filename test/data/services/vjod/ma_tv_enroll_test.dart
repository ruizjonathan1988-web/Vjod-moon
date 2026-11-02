// VJOD 4.13: each profile asks Ma TV (3.60) for its own key with its Jellyfin
// token; an older Ma TV keeps the shared key; a profile cut off is told so.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/auth/repositories/session_repository.dart';
import 'package:moonfin/data/services/vjod/tv_sources.dart';
import 'package:moonfin/preference/seerr_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Session extends Mock implements SessionRepository {}

void main() {
  late SeerrPreferences prefs;
  late _Session session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    final store = PreferenceStore();
    await store.init();
    session = _Session();
    when(() => session.activeUserId).thenReturn('u-lea');
    prefs = SeerrPreferences(store, session);
    GetIt.instance.registerSingleton<SeerrPreferences>(prefs);
    await saveTvSourcesServer(const TvSourcesServer(url: 'https://seedbox.example.com/iptv', key: 'INVITE'));
  });

  MockClient answer(int status, [Map<String, dynamic>? body]) => MockClient((req) async {
    expect(req.url.path, '/iptv/tv/api/enroll');
    expect(req.url.queryParameters['k'], 'INVITE');
    expect(jsonDecode(req.body)['token'], 'tok-lea');
    return http.Response(jsonEncode(body ?? {}), status);
  });

  test('la clé du profil remplace la clé partagée', () async {
    expect(TvSourcesClient().server!.key, 'INVITE');
    expect(await enrollMaTv(token: 'tok-lea', client: answer(200, {'key': 'PERSO-LEA'}), force: true), isTrue);
    expect(TvSourcesClient().server!.key, 'PERSO-LEA');
    expect(maTvAccessCut(), isFalse);
    // un autre profil sur le même appareil n'a pas cette clé
    when(() => session.activeUserId).thenReturn('u-tom');
    expect(TvSourcesClient().server!.key, 'INVITE');
  });

  test('Ma TV d\'avant la 3.60 : la clé partagée reste', () async {
    expect(await enrollMaTv(token: 'tok-lea', client: answer(404), force: true), isFalse);
    expect(TvSourcesClient().server!.key, 'INVITE');
  });

  test('profil coupé par l\'administrateur', () async {
    await enrollMaTv(token: 'tok-lea', client: answer(200, {'key': 'PERSO-LEA'}), force: true);
    expect(await enrollMaTv(token: 'tok-lea', client: answer(403), force: true), isTrue);
    expect(maTvAccessCut(), isTrue);
    expect(TvSourcesClient().server!.key, 'INVITE');
  });

  test('sans jeton Jellyfin : rien ne change', () async {
    expect(await enrollMaTv(token: null, force: true), isFalse);
    expect(TvSourcesClient().server!.key, 'INVITE');
  });
}
