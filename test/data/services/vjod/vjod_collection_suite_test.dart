import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/vjod_collection_service.dart';
import 'package:moonfin/data/services/vjod/vjod_collections.dart';

void main() {
  test('Séries Disney+ : la suite reprend sans le seuil de 100 votes', () {
    final disney = vjodCollectionById('disneyplus')!;
    final rest = VjodCollectionService.relaxedCollection(disney)!;
    expect(rest.query.network, disney.query.network);
    expect(rest.query.mediaType, 'tv');
    expect(rest.query.voteCountGte, VjodCollectionService.relaxedVoteCount);
    expect(rest.id, isNot(disney.id), reason: 'ses pages se gardent à part');
  });

  test('une note minimum reste (les pépites restent des pépites)', () {
    const c = VjodCollection(
      id: 'pepites',
      family: VjodFamily.platforms,
      titleFr: 'Pépites',
      titleEn: 'Gems',
      query: VjodQuery(voteAverageGte: 7.5, voteCountGte: 300),
    );
    final rest = VjodCollectionService.relaxedCollection(c)!;
    expect(rest.query.voteAverageGte, 7.5);
    expect(rest.query.voteCountGte, VjodCollectionService.relaxedVoteCount);
  });

  test('sans seuil de votes : rien à prolonger', () {
    const c = VjodCollection(
      id: 'x',
      family: VjodFamily.platforms,
      titleFr: 'X',
      titleEn: 'X',
      query: VjodQuery(network: 1),
    );
    expect(VjodCollectionService.relaxedCollection(c), isNull);
  });
}
