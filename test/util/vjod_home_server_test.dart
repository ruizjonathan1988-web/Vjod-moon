import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/server_url.dart';
import 'package:moonfin/util/vjod_home_server.dart';

void main() {
  test('le serveur de la maison est en https', () {
    expect(Uri.parse(vjodHomeServerUrl).isScheme('https'), isTrue);
    expect(normalizeServerBaseUrl(vjodHomeServerUrl), isNotEmpty);
  });

  test('proposé seul au premier lancement, sans aucun serveur enregistré', () {
    expect(shouldOfferHomeServer(hasServers: false, alreadyOffered: false), isTrue);
  });

  test('jamais si un serveur est déjà enregistré (autre serveur choisi)', () {
    expect(shouldOfferHomeServer(hasServers: true, alreadyOffered: false), isFalse);
  });

  test('une seule fois : retiré pour un autre serveur, il ne revient pas', () {
    expect(shouldOfferHomeServer(hasServers: false, alreadyOffered: true), isFalse);
  });
}
