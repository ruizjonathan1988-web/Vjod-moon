// VJOD 5.8: a fiche ready before it is opened. When a poster stays selected
// on the TV for a moment, its page is asked for in the background; pressing
// OK then finds it already there, as on the big platforms.
import 'dart:async';

class ItemPrefetch {
  ItemPrefetch._();

  /// How long a poster must stay selected before its fiche is asked for.
  static const dwell = Duration(milliseconds: 400);

  /// How long a fiche asked in advance stays good to use.
  static const keep = Duration(minutes: 2);

  static const _max = 30;
  static final _pages = <String, ({DateTime at, Future<Map<String, dynamic>> page})>{};
  static Timer? _timer;

  /// The poster of [itemId] is selected: once it has stayed so for [dwell],
  /// [fetch] asks for its fiche.
  static void selected(String? itemId, Future<Map<String, dynamic>> Function(String id) fetch) {
    _timer?.cancel();
    if (itemId == null || itemId.isEmpty) return;
    _timer = Timer(dwell, () => warm(itemId, fetch, DateTime.now()));
  }

  /// Asks for the fiche of [itemId] now, unless it was asked recently.
  static void warm(String itemId, Future<Map<String, dynamic>> Function(String id) fetch, DateTime now) {
    final have = _pages[itemId];
    if (have != null && now.difference(have.at) < keep) return;
    final page = fetch(itemId);
    // A failure only means the fiche asks for itself, as before.
    page.catchError((_) {
      _pages.remove(itemId);
      return <String, dynamic>{};
    });
    _pages[itemId] = (at: now, page: page);
    while (_pages.length > _max) {
      _pages.remove(_pages.keys.first);
    }
  }

  /// The fiche of [itemId] asked in advance, if still good; taken once.
  static Future<Map<String, dynamic>>? take(String itemId, DateTime now) {
    final have = _pages.remove(itemId);
    if (have == null || now.difference(have.at) >= keep) return null;
    return have.page;
  }

  static void reset() {
    _timer?.cancel();
    _pages.clear();
  }
}
