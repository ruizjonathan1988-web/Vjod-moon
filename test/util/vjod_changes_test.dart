import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/util/vjod_build.dart';
import 'package:moonfin/util/vjod_changes.dart';

void main() {
  test('la version affichée est la première de la liste des nouveautés', () {
    expect(vjodReleases, isNotEmpty);
    expect(vjodReleases.first.version, VjodBuild.version);
    expect(vjodReleases.first.changes, isNotEmpty);
  });

  test('chaque version n’apparaît qu’une fois', () {
    final seen = <String>{};
    for (final r in vjodReleases) {
      expect(seen.add(r.version), isTrue, reason: r.version);
    }
  });

  test('le numéro lu dans le titre de la release', () {
    expect(vjodVersionFromTitle('VJOD 4.1'), '4.1');
    expect(vjodVersionFromTitle('VJOD 4.12.1'), '4.12.1');
    expect(vjodVersionFromTitle('Dernière version perso'), isNull);
    expect(vjodVersionFromTitle(null), isNull);
  });

  test('les nouveautés lues dans les notes de la release', () {
    expect(vjodChangesFromNotes('- Recherche plus visible\n- Profil simple\nautre ligne'), ['Recherche plus visible', 'Profil simple']);
    expect(vjodChangesFromNotes(null), isEmpty);
  });

  test('le commit lu dans les notes de la release Mac', () {
    expect(vjodCommitFromNotes('commit 9e73f6c\n- Profil simple'), '9e73f6c');
    expect(vjodCommitFromNotes('- Profil simple'), isNull);
    expect(vjodCommitFromNotes(null), isNull);
  });

  test('5.0 sur un appareil resté en 4.12 : toutes les versions depuis, la plus récente d\'abord', () {
    expect(compareVjodVersions('4.9', '4.12'), lessThan(0));
    expect(compareVjodVersions('5.0', '4.51'), greaterThan(0));
    final since = vjodReleasesSince('4.12', '5.0');
    expect(since.first.version, '5.0');
    expect(since.last.version, '4.13');
    expect(since.any((r) => r.version == '4.12'), isFalse);
    expect(vjodReleasesSince(null, '5.0').map((r) => r.version), ['5.0'], reason: 'première installation');
    expect(vjodReleasesSince('4.51', '5.0').map((r) => r.version), ['5.0']);
  });
}
