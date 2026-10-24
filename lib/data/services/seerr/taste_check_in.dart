import '../tonight/evening_journal.dart';
import 'taste_profile.dart';

/// What the viewer thought of something watched to the end.
enum CheckInVerdict { loved, good, meh, disliked }

/// Why the viewer stopped something early.
enum DropReason { notNow, tooSlow, tooDark, notMyGenre, later }

/// A past choice the monthly check-in asks to confirm.
sealed class StillTrue {
  const StillTrue();
}

class StillAvoided extends StillTrue {
  final TasteGenre genre;
  const StillAvoided(this.genre);
}

class StillNoSubtitles extends StillTrue {
  const StillNoSubtitles();
}

class StillNoViolence extends StillTrue {
  const StillNoViolence();
}

/// The sittings worth asking about this month: the last film or series
/// watched to the end, and the last one dropped early. Each is asked about
/// once, and only if its TMDB id is known.
({JournalEntry? finished, JournalEntry? dropped}) checkInSittings({
  required List<JournalEntry> journal,
  required TasteProfile profile,
  Set<String> asked = const {},
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final seen = profile.seenKeys;
  JournalEntry? finished;
  JournalEntry? dropped;
  for (final entry in journal.reversed) {
    if (entry.backfilled || entry.tmdbKey == null) continue;
    if (at.difference(entry.at) > const Duration(days: 45)) break;
    if (asked.contains(checkInKey(entry))) continue;
    if (seen.contains(entry.tmdbKey)) continue;
    if (finished == null && entry.finished) {
      finished = entry;
    } else if (dropped == null && !entry.finished && _droppedEarly(entry)) {
      dropped = entry;
    }
    if (finished != null && dropped != null) break;
  }
  return (finished: finished, dropped: dropped);
}

bool _droppedEarly(JournalEntry entry) {
  final runtime = entry.runtimeMinutes;
  if (entry.episodes > 1) return false;
  if (runtime == null || runtime <= 0) return entry.watchedMinutes < 25;
  return entry.watchedMinutes / runtime < 0.3;
}

/// What marks a sitting as asked about.
String checkInKey(JournalEntry entry) =>
    '${entry.itemId}@${entry.at.toUtc().toIso8601String()}';

/// The oldest choice still standing that is worth a second look.
StillTrue? stillTrueQuestion(TasteProfile profile) {
  if (profile.avoided.isNotEmpty) {
    return StillAvoided(profile.avoided.first);
  }
  if (profile.subtitles == TasteSubtitles.never) {
    return const StillNoSubtitles();
  }
  if (profile.violence == TasteViolence.none) return const StillNoViolence();
  return null;
}

TastePick _pickOf(JournalEntry entry) => TastePick(
  tmdbId: entry.tmdbId!,
  mediaType: entry.mediaType,
  title: entry.title,
  genres: entry.genres,
);

/// The profile once the viewer said what they thought of [entry].
TasteProfile applyVerdict(
  TasteProfile profile,
  JournalEntry entry,
  CheckInVerdict verdict,
) {
  final pick = _pickOf(entry);
  List<TastePick> without(List<TastePick> list) =>
      [for (final p in list) if (p.key != pick.key) p];
  switch (verdict) {
    case CheckInVerdict.loved:
      // A new all-time favourite; the oldest steps back past five.
      final pivots = [...without(profile.pivots), pick];
      return profile.copyWith(
        pivots: pivots.length > 5 ? pivots.sublist(pivots.length - 5) : pivots,
      );
    case CheckInVerdict.good:
      return profile.copyWith(favorites: [...without(profile.favorites), pick]);
    case CheckInVerdict.meh:
      return profile.copyWith(meh: [...without(profile.meh), pick]);
    case CheckInVerdict.disliked:
      return profile.copyWith(disliked: [...without(profile.disliked), pick]);
  }
}

/// The profile once the viewer said why they stopped [entry].
TasteProfile applyDropReason(
  TasteProfile profile,
  JournalEntry entry,
  DropReason reason,
) {
  switch (reason) {
    case DropReason.notNow:
    case DropReason.later:
      return profile;
    case DropReason.tooSlow:
      final axes = {...profile.axes};
      axes[TasteAxis.slowFast] =
          ((axes[TasteAxis.slowFast] ?? 0) + 0.5).clamp(-2.0, 2.0);
      return profile.copyWith(axes: axes);
    case DropReason.tooDark:
      return profile.copyWith(
        violence: switch (profile.violence) {
          TasteViolence.fine => TasteViolence.justified,
          _ => TasteViolence.none,
        },
      );
    case DropReason.notMyGenre:
      return applyVerdict(profile, entry, CheckInVerdict.disliked);
  }
}

/// The profile once the viewer said a past choice no longer holds.
TasteProfile releaseChoice(TasteProfile profile, StillTrue question) =>
    switch (question) {
      StillAvoided(:final genre) => profile.copyWith(
        avoided: {...profile.avoided}..remove(genre),
      ),
      StillNoSubtitles() => profile.copyWith(
        subtitles: TasteSubtitles.depends,
      ),
      StillNoViolence() => profile.copyWith(
        violence: TasteViolence.justified,
      ),
    };
