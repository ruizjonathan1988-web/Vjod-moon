import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/search_repository.dart';
import 'package:moonfin/data/viewmodels/search_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockItemsApi extends Mock implements ItemsApi {}

class _MockLiveTvApi extends Mock implements LiveTvApi {}

void main() {
  late _MockClient client;
  late _MockLiveTvApi liveTv;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    client = _MockClient();
    final itemsApi = _MockItemsApi();
    liveTv = _MockLiveTvApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.liveTvApi).thenReturn(liveTv);
    when(() => client.gamesApi).thenReturn(null);
    when(() => client.userId).thenReturn('u');
    when(
      () => itemsApi.getItems(
        searchTerm: any(named: 'searchTerm'),
        parentId: any(named: 'parentId'),
        includeItemTypes: any(named: 'includeItemTypes'),
        limit: any(named: 'limit'),
        recursive: any(named: 'recursive'),
        fields: any(named: 'fields'),
        studios: any(named: 'studios'),
      ),
    ).thenAnswer((_) async => {'Items': <dynamic>[]});
    when(
      () => itemsApi.getPersons(
        searchTerm: any(named: 'searchTerm'),
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
        enableImageTypes: any(named: 'enableImageTypes'),
      ),
    ).thenAnswer((_) async => {'Items': <dynamic>[]});
    when(
      () => liveTv.getChannels(
        fields: any(named: 'fields'),
        enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async => {
          'Items': [
            {'Id': 'c1', 'Name': 'TF1', 'Type': 'TvChannel'},
          ],
        });
  });

  tearDown(() => GetIt.instance.reset());

  test('avec Ma TV, la recherche ne charge pas les 12 000 chaînes du serveur une deuxième fois', () {
    fakeAsync((async) {
      final vm = SearchViewModel(SearchRepository(client), client)
        ..serverChannelsRedundant = () async => true;
      vm.warmUpChannels();
      vm.searchImmediate('tf1');
      async.elapse(const Duration(seconds: 2));
      verifyNever(
        () => liveTv.getChannels(
          fields: any(named: 'fields'),
          enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
          userId: any(named: 'userId'),
        ),
      );
      vm.dispose();
    });
  });

  test('sans Ma TV, les chaînes du serveur restent cherchées', () {
    fakeAsync((async) {
      final vm = SearchViewModel(SearchRepository(client), client)
        ..serverChannelsRedundant = () async => false;
      vm.searchImmediate('tf1');
      async.elapse(const Duration(seconds: 2));
      verify(
        () => liveTv.getChannels(
          fields: any(named: 'fields'),
          enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
          userId: any(named: 'userId'),
        ),
      ).called(1);
      vm.dispose();
    });
  });
}
