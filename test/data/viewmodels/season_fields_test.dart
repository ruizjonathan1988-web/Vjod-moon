import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/viewmodels/item_detail_view_model.dart';

void main() {
  test('les saisons sont demandées avec CanDelete, pour pouvoir en supprimer une seule', () {
    expect(ItemDetailViewModel.seasonFields.split(','), contains('CanDelete'));
  });
}
