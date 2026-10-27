import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/arr_links.dart';

void main() {
  test('prefers externalUrl and appends movie/series + slug', () {
    final servers = [
      {'id': 1, 'externalUrl': 'https://radarr.example/', 'hostname': 'x'},
    ];
    expect(
      buildArrUrl(servers, serviceId: 1, slug: 'the-matrix', isMovie: true),
      'https://radarr.example/movie/the-matrix',
    );
  });

  test('builds from hostname/port/ssl/baseUrl when no externalUrl', () {
    final servers = [
      {
        'id': 2,
        'hostname': 'host',
        'port': 8989,
        'useSsl': false,
        'baseUrl': '/sonarr',
      },
    ];
    expect(
      buildArrUrl(servers, serviceId: 2, slug: 'show', isMovie: false),
      'http://host:8989/sonarr/series/show',
    );
  });

  test('matches the server by id, not just the first', () {
    final servers = [
      {'id': 1, 'externalUrl': 'http://a'},
      {'id': 5, 'externalUrl': 'http://b'},
    ];
    expect(
      buildArrUrl(servers, serviceId: 5, slug: 's', isMovie: true),
      'http://b/movie/s',
    );
  });

  test('null when slug missing or no server', () {
    expect(buildArrUrl([], serviceId: 1, slug: 's', isMovie: true), isNull);
    expect(
      buildArrUrl([{'id': 1, 'externalUrl': 'http://a'}],
          serviceId: 1, slug: '', isMovie: true),
      isNull,
    );
  });
}
