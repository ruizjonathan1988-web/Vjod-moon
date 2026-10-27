import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/data/utils/own_copy_first.dart';
import 'package:moonfin/util/provider_stream.dart';

AggregatedItem _item(String id, String path, {String? tmdb, String type = 'Movie'}) =>
    AggregatedItem(
      id: id,
      serverId: 's',
      rawData: {
        'Name': 'Dune',
        'Type': type,
        'ProductionYear': 2021,
        'Path': path,
        if (tmdb != null) 'ProviderIds': {'Tmdb': tmdb},
      },
    );

void main() {
  test('a provider stream is told from a file of the server', () {
    expect(isProviderStreamPath('/home/u/media/Fournisseur/Movies/Dune (2021)/Dune.strm'), isTrue);
    expect(isProviderStreamPath('/home/u/media/Fournisseur/Series/Dark'), isTrue);
    expect(isProviderStreamPath('/data/movies/X/X.strm'), isTrue);
    expect(isProviderStreamPath('/home/u/media/Films/Dune (2021)/Dune.mkv'), isFalse);
    // A title alone never makes a stream, only the folders it sits in.
    expect(isProviderStreamPath('/home/u/media/Films/IPTV.mkv'), isFalse);
    expect(isProviderStreamPath(null), isFalse);
    expect(copyRankOfPath('/media/Films/Dune/Dune.mkv'), 0);
    expect(copyRankOfPath('/media/Russian Movies/Dune/Dune.mkv'), 1);
    expect(copyRankOfPath('/media/Fournisseur/Dune/Dune.strm'), 2);
  });

  test('the server own copy hides the provider stream of the same title', () {
    final stream = _item('a', '/m/Fournisseur/Dune/Dune.strm', tmdb: '438631');
    final own = _item('b', '/m/Films/Dune/Dune.mkv', tmdb: '438631');
    final other = _item('c', '/m/Fournisseur/Other/Other.strm', tmdb: '1');
    final kept = withoutStreamDuplicates([stream, own, other]);
    expect(kept.map((i) => i.id), ['b', 'c']);
    // Without a copy of its own the stream stays.
    expect(withoutStreamDuplicates([stream, other]).length, 2);
    expect(_item('a', '/m/Fournisseur/Dune/Dune.strm').isProviderStream, isTrue);
  });
}
