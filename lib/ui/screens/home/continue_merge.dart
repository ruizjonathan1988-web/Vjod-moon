// VJOD 4.23: one « Continuer » for everything under way. The IPTV films and
// series and the replay episodes started on Ma TV join the library's row,
// in the order they were last watched, instead of a row of their own.
import '../../../data/models/aggregated_item.dart';
import '../../../data/models/home_row.dart';

/// [rows] with the row [extraRowId] folded into the first « Continuer » row
/// (resume type). Without a « Continuer » on the Home, the extra row stays.
List<HomeRow> foldIntoContinue(List<HomeRow> rows, {required String extraRowId}) {
  final extraAt = rows.indexWhere((r) => r.id == extraRowId);
  if (extraAt < 0) return rows;
  final resumeAt = rows.indexWhere((r) => r.rowType == HomeRowType.resume);
  if (resumeAt < 0) return rows;
  final extra = rows[extraAt];
  final resume = rows[resumeAt];
  final items = mergeByLastWatched(resume.items, extra.items);
  final out = <HomeRow>[];
  for (var i = 0; i < rows.length; i++) {
    if (i == extraAt) continue;
    out.add(i == resumeAt
        ? resume.copyWith(items: items, totalCount: resume.totalCount + extra.items.length)
        : rows[i]);
  }
  return out;
}

/// [library] keeps its own order; each of [extra] goes before the first
/// library title watched before it (a title with no date counts as older).
List<AggregatedItem> mergeByLastWatched(List<AggregatedItem> library, List<AggregatedItem> extra) {
  if (extra.isEmpty) return library;
  int ms(AggregatedItem i) => i.lastPlayedDate?.millisecondsSinceEpoch ?? 0;
  final pending = [...extra]..sort((a, b) => ms(b).compareTo(ms(a)));
  final seen = {for (final i in library) i.id};
  pending.removeWhere((i) => seen.contains(i.id));
  final out = <AggregatedItem>[];
  var p = 0;
  for (final item in library) {
    while (p < pending.length && ms(pending[p]) > ms(item)) {
      out.add(pending[p++]);
    }
    out.add(item);
  }
  out.addAll(pending.skip(p));
  return out;
}
