import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/viewmodels/live_tv_guide_view_model.dart';
import 'package:server_core/server_core.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockLiveTvApi extends Mock implements LiveTvApi {}

void main() {
  late _MockClient client;
  late _MockLiveTvApi liveTv;
  final asked = <List<String>>[];

  setUp(() {
    asked.clear();
    client = _MockClient();
    liveTv = _MockLiveTvApi();
    when(() => client.liveTvApi).thenReturn(liveTv);
    when(() => client.userId).thenReturn('user');
    when(
      () => liveTv.getChannels(
        sortBy: any(named: 'sortBy'),
        sortOrder: any(named: 'sortOrder'),
        fields: any(named: 'fields'),
        enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async => {
          'Items': [for (var i = 0; i < 400; i++) {'Id': 'c$i', 'Name': 'Ch $i'}],
        });
    when(
      () => liveTv.getGuide(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        channelIds: any(named: 'channelIds'),
        isMovie: any(named: 'isMovie'),
        isSeries: any(named: 'isSeries'),
        isSports: any(named: 'isSports'),
        isNews: any(named: 'isNews'),
        isKids: any(named: 'isKids'),
        fields: any(named: 'fields'),
        enableTotalRecordCount: any(named: 'enableTotalRecordCount'),
        enableImages: any(named: 'enableImages'),
        enableUserData: any(named: 'enableUserData'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((inv) async {
      final ids = (inv.namedArguments[#channelIds] as List<String>?) ?? const [];
      asked.add(ids);
      return {'Items': <dynamic>[]};
    });
  });

  test('petite box : 300 chaînes gardées au plus, les plus anciennes lâchées', () {
    expect(LiveTvGuideViewModel.programChannelCapFor(true), 300);
    expect(LiveTvGuideViewModel.programChannelCapFor(false), 1500);
  });

  test('en descendant dans 400 chaînes, le guide n’en garde que 100, et recharge une ligne lâchée', () async {
    final vm = LiveTvGuideViewModel(client)..programChannelCap = 100;
    await vm.load();
    while (vm.hasMorePrograms) {
      await vm.loadMorePrograms();
    }
    expect(vm.programsHighWater, 400);
    expect(vm.hasProgramsFor('c399'), isTrue, reason: 'les dernières chargées restent');
    expect(vm.hasProgramsFor('c0'), isFalse, reason: 'la première a été lâchée');
    expect(vm.needsReload('c0', 0), isTrue);
    expect(vm.needsReload('c399', 399), isFalse);

    asked.clear();
    await vm.reloadPrograms(['c0', 'c1']);
    expect(asked, [
      ['c0', 'c1'],
    ]);
    expect(vm.hasProgramsFor('c0'), isTrue);
    expect(vm.hasProgramsFor('c399'), isTrue, reason: 'une ligne rechargée ne chasse pas les plus récentes');
    vm.dispose();
  });
}
