import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/ui/widgets/top_toolbar.dart';

void main() {
  test('sans serveur connecté, « Connecter un appareil » n’est pas proposé', () {
    expect(vjodOffersQuickConnect(), isFalse);
  });
}
