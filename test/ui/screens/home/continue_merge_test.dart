// VJOD 4.23: un seul « Continuer » pour la bibliothèque, l'IPTV et le replay.
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/models/home_row.dart';
import 'package:moonfin/ui/screens/home/continue_merge.dart';

AggregatedItem _at(String id, DateTime? when, {String server = 'jf'}) => AggregatedItem(
  id: id,
  serverId: server,
  rawData: {
    'Name': id,
    if (when != null) 'UserData': {'LastPlayedDate': when.toUtc().toIso8601String()},
  },
);

void main() {
  final d = (int day) => DateTime.utc(2026, 11, day, 20);

  test('les titres commencés ailleurs prennent leur place selon la date', () {
    final lib = [_at('malcolm', d(3)), _at('dune', d(1)), _at('suite', null)];
    final extra = [_at('replay', d(2), server: 'seerr'), _at('film-iptv', d(4), server: 'seerr')];
    expect(mergeByLastWatched(lib, extra).map((i) => i.id), ['film-iptv', 'malcolm', 'replay', 'dune', 'suite']);
  });

  test('la rangée IPTV rejoint Continuer, sauf s’il n’y en a pas', () {
    final resume = HomeRow(id: 'resume', title: 'Continuer', rowType: HomeRowType.resume, items: [_at('malcolm', d(3))], totalCount: 1);
    final iptv = HomeRow(id: 'iptv_resume', title: 'Reprendre (IPTV)', rowType: HomeRowType.pluginDynamic, items: [_at('replay', d(4), server: 'seerr')]);
    final other = HomeRow(id: 'latest', title: 'Ajouts', rowType: HomeRowType.latestMedia, items: [_at('x', null)]);
    final folded = foldIntoContinue([resume, iptv, other], extraRowId: 'iptv_resume');
    expect(folded.map((r) => r.id), ['resume', 'latest']);
    expect(folded.first.items.map((i) => i.id), ['replay', 'malcolm']);
    expect(folded.first.totalCount, 2);
    expect(foldIntoContinue([iptv, other], extraRowId: 'iptv_resume').map((r) => r.id), ['iptv_resume', 'latest']);
  });
}
