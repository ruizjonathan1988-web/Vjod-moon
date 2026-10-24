import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/seerr/my_requests.dart';
import 'package:moonfin/data/services/seerr/seerr_api_models.dart';

final _now = DateTime.utc(2026, 10, 20, 12);

String _daysAgo(int days) =>
    _now.subtract(Duration(days: days)).toIso8601String();

SeerrRequest _request(
  int id, {
  int tmdbId = 0,
  String type = 'movie',
  int status = SeerrRequest.statusApproved,
  int? mediaStatus = SeerrMediaStatus.processing,
  List<SeerrDownloadingItem>? downloads,
  String? updated,
  String? added,
}) => SeerrRequest(
  id: id,
  status: status,
  type: type,
  createdAt: updated ?? _daysAgo(1),
  updatedAt: updated ?? _daysAgo(1),
  media: SeerrMedia(
    id: id,
    tmdbId: tmdbId == 0 ? 1000 + id : tmdbId,
    status: mediaStatus,
    downloadStatus: downloads,
    mediaAddedAt: added,
    title: 'Title $id',
  ),
);

void main() {
  group('requestState', () {
    test('reads the request and its media together', () {
      expect(
        requestState(_request(1, status: SeerrRequest.statusDeclined)),
        MyRequestState.declined,
      );
      expect(
        requestState(_request(2, status: SeerrRequest.statusFailed)),
        MyRequestState.failed,
      );
      expect(
        requestState(
          _request(3, status: SeerrRequest.statusPending, mediaStatus: null),
        ),
        MyRequestState.pending,
      );
      expect(requestState(_request(4)), MyRequestState.approved);
      expect(
        requestState(
          _request(5, mediaStatus: SeerrMediaStatus.available),
        ),
        MyRequestState.ready,
      );
      expect(
        requestState(
          _request(
            6,
            downloads: const [
              SeerrDownloadingItem(size: 100, sizeLeft: 40, downloadId: 'a'),
            ],
          ),
        ),
        MyRequestState.downloading,
      );
    });

    test('a season request is ready once its seasons are in', () {
      expect(
        requestState(
          _request(
            7,
            type: 'tv',
            status: SeerrRequest.statusCompleted,
            mediaStatus: SeerrMediaStatus.partiallyAvailable,
          ),
        ),
        MyRequestState.ready,
      );
      expect(
        requestState(
          _request(
            8,
            type: 'tv',
            mediaStatus: SeerrMediaStatus.partiallyAvailable,
          ),
        ),
        MyRequestState.approved,
      );
    });
  });

  group('downloadProgress', () {
    test('counts a season pack once', () {
      final progress = downloadProgress(const [
        SeerrDownloadingItem(size: 1000, sizeLeft: 250, downloadId: 'pack'),
        SeerrDownloadingItem(size: 1000, sizeLeft: 250, downloadId: 'pack'),
        SeerrDownloadingItem(size: 1000, sizeLeft: 750, downloadId: 'ep'),
      ]);
      expect(progress, closeTo(0.5, 1e-9));
    });

    test('says nothing without sizes', () {
      expect(downloadProgress(null), isNull);
      expect(downloadProgress(const [SeerrDownloadingItem()]), isNull);
    });
  });

  group('myRequestEntries', () {
    test('lists what can be watched first, then what is on its way', () {
      final entries = myRequestEntries([
        _request(1, status: SeerrRequest.statusPending, mediaStatus: null),
        _request(
          2,
          downloads: const [SeerrDownloadingItem(size: 10, sizeLeft: 5)],
        ),
        _request(
          3,
          mediaStatus: SeerrMediaStatus.available,
          added: _daysAgo(2),
        ),
        _request(4),
        _request(
          5,
          status: SeerrRequest.statusDeclined,
          updated: _daysAgo(1),
        ),
      ], now: _now);
      expect(entries.map((e) => e.request.id), [3, 2, 4, 1, 5]);
      expect(entries[1].progress, closeTo(0.5, 1e-9));
    });

    test('old successes and old refusals drop off', () {
      final entries = myRequestEntries([
        _request(
          1,
          mediaStatus: SeerrMediaStatus.available,
          added: _daysAgo(30),
        ),
        _request(
          2,
          status: SeerrRequest.statusDeclined,
          updated: _daysAgo(10),
        ),
        _request(3, updated: _daysAgo(60)),
      ], now: _now);
      // Still waiting after two months: worth seeing.
      expect(entries.map((e) => e.request.id), [3]);
    });

    test('one card per title, the furthest along speaks', () {
      final entries = myRequestEntries([
        _request(1, type: 'tv', tmdbId: 1396),
        _request(
          2,
          type: 'tv',
          tmdbId: 1396,
          status: SeerrRequest.statusCompleted,
          mediaStatus: SeerrMediaStatus.available,
          added: _daysAgo(1),
        ),
      ], now: _now);
      expect(entries, hasLength(1));
      expect(entries.single.state, MyRequestState.ready);
    });
  });

  group('newlyReady', () {
    final entries = myRequestEntries([
      _request(1, mediaStatus: SeerrMediaStatus.available, added: _daysAgo(1)),
      _request(2, mediaStatus: SeerrMediaStatus.available, added: _daysAgo(1)),
      _request(3),
    ], now: _now);

    test('the first look announces nothing', () {
      expect(newlyReady(entries, null), isEmpty);
    });

    test('announces each ready request once', () {
      final fresh = newlyReady(entries, ['req:1']);
      expect(fresh.map((e) => e.request.id), [2]);
    });
  });

  group('promoteInLibrary', () {
    test('a title the library holds is ready whatever Seerr says', () {
      final entries = myRequestEntries([
        _request(1, type: 'tv', tmdbId: 500),
        _request(2, tmdbId: 600, status: SeerrRequest.statusPending, mediaStatus: null),
        _request(
          3,
          tmdbId: 700,
          downloads: const [SeerrDownloadingItem(size: 10, sizeLeft: 5)],
        ),
      ], now: _now);
      final promoted = promoteInLibrary(
        entries,
        {'tv:500', 'movie:700'},
        now: _now,
      );
      final byId = {for (final e in promoted) e.request.id: e.state};
      expect(byId[1], MyRequestState.ready);
      // Not in the library yet.
      expect(byId[2], MyRequestState.pending);
      // A download under way still reads as one.
      expect(byId[3], MyRequestState.downloading);
      expect(promoted.first.request.id, 1);
    });

    test('an old request found in the library drops off', () {
      final entries = myRequestEntries([
        _request(1, tmdbId: 500, updated: _daysAgo(40)),
      ], now: _now);
      expect(
        promoteInLibrary(entries, {'movie:500'}, now: _now),
        isEmpty,
      );
    });
  });
}
