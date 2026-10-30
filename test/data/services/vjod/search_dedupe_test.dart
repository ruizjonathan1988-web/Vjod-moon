import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';
import 'package:moonfin/data/services/vjod/search_dedupe.dart';
import 'package:moonfin/data/services/vjod/xtream_catalog.dart';

XtreamTitle _iptv(String tmdb, String name) => XtreamTitle(
  kind: XtreamKind.movie,
  id: tmdb.isEmpty ? name : tmdb,
  name: name,
  tag: 'FR',
  poster: '',
  extension: 'mkv',
  searchKey: name.toLowerCase(),
  tmdbId: tmdb,
);

SeerrDiscoverItem _seerr(int id, {int? status, String type = 'movie'}) => SeerrDiscoverItem(
  id: id,
  mediaType: type,
  title: 'Titre $id',
  mediaInfo: status == null ? null : SeerrMediaInfo(tmdbId: id, status: status),
);

void main() {
  test('un titre sur le serveur ne réapparaît ni en IPTV ni à demander', () {
    final r = dedupeCatalogResults(
      libraryTmdbIds: {'438631'},
      provider: [_iptv('438631', 'Dune'), _iptv('693134', 'Dune 2')],
      seerr: [_seerr(438631), _seerr(693134), _seerr(841)],
    );
    expect(r.provider.map((t) => t.tmdbId), ['693134']);
    expect(r.seerr.map((s) => s.id), [841], reason: 'Dune 2 est en IPTV, Dune sur le serveur');
  });

  test('Seerr dit « disponible » : traité comme sur le serveur', () {
    final r = dedupeCatalogResults(
      libraryTmdbIds: const {},
      provider: [_iptv('100', 'Film')],
      seerr: [_seerr(100, status: SeerrMediaStatus.available), _seerr(200, status: SeerrMediaStatus.partiallyAvailable)],
    );
    expect(r.provider, isEmpty);
    expect(r.seerr, isEmpty);
  });

  test('demandé mais pas encore là : reste « à demander » (son statut s\'affiche)', () {
    final r = dedupeCatalogResults(
      libraryTmdbIds: const {},
      provider: const [],
      seerr: [_seerr(300, status: SeerrMediaStatus.pending)],
    );
    expect(r.seerr.map((s) => s.id), [300]);
  });

  test('un titre IPTV sans identifiant TMDB est gardé', () {
    final r = dedupeCatalogResults(
      libraryTmdbIds: const {'1'},
      provider: [_iptv('', 'Inconnu')],
      seerr: const [],
    );
    expect(r.provider, hasLength(1));
  });

  test('les personnes (acteurs, réalisateurs) restent', () {
    final r = dedupeCatalogResults(
      libraryTmdbIds: const {'5'},
      provider: [_iptv('5', 'x')],
      seerr: [_seerr(5, type: 'person')],
    );
    expect(r.seerr.map((s) => s.id), [5]);
  });
}
