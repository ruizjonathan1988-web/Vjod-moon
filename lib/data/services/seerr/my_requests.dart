import 'seerr_api_models.dart';

/// Where one of the viewer's requests stands, in the order the My Requests
/// row lists them: what can be watched first, then what is on its way.
enum MyRequestState { ready, downloading, approved, pending, failed, declined }

/// One card of the My Requests row.
class MyRequestEntry {
  final SeerrRequest request;
  final MyRequestState state;

  /// Share of the download done, from 0 to 1, while [state] is downloading.
  final double? progress;

  const MyRequestEntry({
    required this.request,
    required this.state,
    this.progress,
  });

  SeerrMedia get media => request.media!;

  MyRequestEntry withState(MyRequestState state) =>
      MyRequestEntry(request: request, state: state);

  /// One card per title, however many requests it took.
  String get key => '${request.type}:${media.tmdbId ?? media.id}';

  /// What a "ready" announcement remembers, so each request is announced
  /// once.
  String get readyKey => 'req:${request.id}';
}

/// How long a request that came through stays in the row: long enough to
/// notice it, short enough that the row keeps meaning "what's new".
const myRequestsReadyWindow = Duration(days: 14);

/// How long a refused or failed request stays, so the viewer learns of it.
const myRequestsDeclinedWindow = Duration(days: 7);

/// Reads [request]'s state from the request and its media together: Seerr
/// marks a request completed before the library has scanned the file, and
/// keeps a request approved while Radarr or Sonarr is downloading it.
MyRequestState requestState(SeerrRequest request) {
  if (request.status == SeerrRequest.statusDeclined) {
    return MyRequestState.declined;
  }
  if (request.status == SeerrRequest.statusFailed) {
    return MyRequestState.failed;
  }
  final media = request.media;
  final mediaStatus = request.is4k ? media?.status4k : media?.status;
  final downloads = request.is4k ? media?.downloadStatus4k : media?.downloadStatus;
  if (downloads != null && downloads.isNotEmpty) {
    return MyRequestState.downloading;
  }
  if (mediaStatus == SeerrMediaStatus.available) return MyRequestState.ready;
  // A series request for some seasons leaves the series partly available
  // once those seasons are in, which is all that was asked.
  if (mediaStatus == SeerrMediaStatus.partiallyAvailable &&
      request.status == SeerrRequest.statusCompleted) {
    return MyRequestState.ready;
  }
  if (request.status == SeerrRequest.statusPending) {
    return MyRequestState.pending;
  }
  return MyRequestState.approved;
}

/// Share of [items] already downloaded, or null when nothing reports a size.
///
/// Sonarr lists a season pack once per episode with the same download id and
/// the whole pack's size, so each download id counts once.
double? downloadProgress(List<SeerrDownloadingItem>? items) {
  if (items == null || items.isEmpty) return null;
  final seen = <String>{};
  var size = 0;
  var left = 0;
  for (final item in items) {
    final id = item.downloadId;
    if (id != null && !seen.add(id)) continue;
    final itemSize = item.size ?? 0;
    if (itemSize <= 0) continue;
    size += itemSize;
    left += (item.sizeLeft ?? 0).clamp(0, itemSize);
  }
  if (size <= 0) return null;
  return ((size - left) / size).clamp(0.0, 1.0);
}

DateTime? _parse(String? value) =>
    value == null ? null : DateTime.tryParse(value);

/// When [request] last moved: the library add for what came through,
/// otherwise the request's own last change.
DateTime? _lastChange(SeerrRequest request, MyRequestState state) {
  final media = request.media;
  if (state == MyRequestState.ready) {
    final added = _parse(media?.mediaAddedAt);
    if (added != null) return added;
  }
  return _parse(request.updatedAt) ?? _parse(request.createdAt);
}

/// The viewer's requests as the row shows them: one card per title, what can
/// be watched first, then what is downloading, approved, awaiting approval,
/// and lastly what went wrong. Old successes and old refusals drop off.
List<MyRequestEntry> myRequestEntries(
  List<SeerrRequest> requests, {
  required DateTime now,
  int limit = 20,
}) {
  final byKey = <String, (MyRequestEntry, DateTime?)>{};
  for (final request in requests) {
    if (request.media == null) continue;
    final state = requestState(request);
    final changed = _lastChange(request, state);
    final window = switch (state) {
      MyRequestState.ready => myRequestsReadyWindow,
      MyRequestState.declined || MyRequestState.failed =>
        myRequestsDeclinedWindow,
      _ => null,
    };
    if (window != null &&
        (changed == null || now.difference(changed) > window)) {
      continue;
    }
    final media = request.media!;
    final entry = MyRequestEntry(
      request: request,
      state: state,
      progress: state == MyRequestState.downloading
          ? downloadProgress(
              request.is4k ? media.downloadStatus4k : media.downloadStatus,
            )
          : null,
    );
    final existing = byKey[entry.key];
    // Two requests for one title, such as two seasons: the one further
    // along speaks for both.
    if (existing == null || state.index < existing.$1.state.index) {
      byKey[entry.key] = (entry, changed);
    }
  }

  final sorted = byKey.values.toList()
    ..sort((a, b) {
      final byState = a.$1.state.index.compareTo(b.$1.state.index);
      if (byState != 0) return byState;
      final at = a.$2;
      final bt = b.$2;
      if (at == null && bt == null) return 0;
      if (at == null || bt == null) return at == null ? 1 : -1;
      return bt.compareTo(at);
    });
  return [for (final (entry, _) in sorted.take(limit)) entry];
}

/// Ready requests not announced yet. The first time ever, when nothing has
/// been [announced], nothing is new: the viewer saw those already.
List<MyRequestEntry> newlyReady(
  List<MyRequestEntry> entries,
  List<String>? announced,
) {
  if (announced == null) return const [];
  final known = announced.toSet();
  return [
    for (final entry in entries)
      if (entry.state == MyRequestState.ready && !known.contains(entry.readyKey))
        entry,
  ];
}

/// Titles still shown as approved or awaiting approval that the library
/// already holds, as the [MyRequestEntry.key]s worth asking the server about.
List<MyRequestEntry> libraryCandidates(List<MyRequestEntry> entries) => [
  for (final entry in entries)
    if (entry.state == MyRequestState.approved ||
        entry.state == MyRequestState.pending)
      entry,
];

/// Seerr learns that a request came through only when its own scan runs,
/// and keeps a series request approved until every season is in. A title the
/// library already holds is ready to watch whatever Seerr still says.
///
/// Requests older than [myRequestsReadyWindow] that turn out to be in the
/// library are dropped, since the row is for what is new.
List<MyRequestEntry> promoteInLibrary(
  List<MyRequestEntry> entries,
  Set<String> inLibrary, {
  required DateTime now,
}) {
  final promoted = <MyRequestEntry>[];
  for (final entry in entries) {
    final candidate =
        entry.state == MyRequestState.approved ||
        entry.state == MyRequestState.pending;
    if (!candidate || !inLibrary.contains(entry.key)) {
      promoted.add(entry);
      continue;
    }
    final changed =
        _parse(entry.request.updatedAt) ?? _parse(entry.request.createdAt);
    if (changed != null && now.difference(changed) > myRequestsReadyWindow) {
      continue;
    }
    promoted.add(entry.withState(MyRequestState.ready));
  }
  promoted.sort((a, b) => a.state.index.compareTo(b.state.index));
  return promoted;
}
