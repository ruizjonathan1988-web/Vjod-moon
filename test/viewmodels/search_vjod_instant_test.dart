import 'dart:async';

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

void main() {
  late _MockClient client;
  late _MockItemsApi itemsApi;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));
    client = _MockClient();
    itemsApi = _MockItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.gamesApi).thenReturn(null);
  });

  tearDown(() => GetIt.instance.reset());

  void itemsFor(String term, List<(String, String)> items) {
    when(
      () => itemsApi.getItems(
        searchTerm: term,
        parentId: any(named: 'parentId'),
        includeItemTypes: any(named: 'includeItemTypes'),
        limit: any(named: 'limit'),
        recursive: any(named: 'recursive'),
        fields: any(named: 'fields'),
        studios: any(named: 'studios'),
      ),
    ).thenAnswer(
      (_) async => {
        'Items': [
          for (final (id, type) in items) {'Id': id, 'Type': type, 'Name': id},
        ],
      },
    );
  }

  Completer<Map<String, dynamic>> peopleFor(String term) {
    final people = Completer<Map<String, dynamic>>();
    when(
      () => itemsApi.getPersons(
        searchTerm: term,
        limit: any(named: 'limit'),
        fields: any(named: 'fields'),
        enableImageTypes: any(named: 'enableImageTypes'),
      ),
    ).thenAnswer((_) => people.future);
    return people;
  }

  test('VJOD : une lettre de plus filtre aussitôt, une recherche déjà faite revient tout de suite', () {
    fakeAsync((async) {
      itemsFor('ali', [('Alien', 'Movie'), ('Aladdin', 'Movie')]);
      itemsFor('alie', [('Alien', 'Movie')]);
      peopleFor('ali').complete({'Items': []});
      peopleFor('alie').complete({'Items': []});
      final vm = SearchViewModel(SearchRepository(client), client);

      vm.searchDebounced('ali');
      async.elapse(const Duration(milliseconds: 300));
      expect(vm.state, SearchState.ready);
      expect(vm.results.expand((g) => g.items).map((i) => i.name), ['Alien', 'Aladdin']);

      // une lettre de plus : filtré sans attendre le serveur
      vm.searchDebounced('alie');
      expect(vm.results.expand((g) => g.items).map((i) => i.name), ['Alien']);
      async.elapse(const Duration(milliseconds: 300));
      expect(vm.state, SearchState.ready);

      // la lettre effacée : la recherche d'avant revient aussitôt
      vm.searchDebounced('ali');
      expect(vm.state, SearchState.ready);
      expect(vm.results.expand((g) => g.items).map((i) => i.name), ['Alien', 'Aladdin']);
      async.elapse(const Duration(seconds: 2));
      vm.dispose();
    });
  });
}
