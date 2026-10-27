import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/recent_channels.dart';

void main() {
  test('newest first, no duplicates', () {
    var s = '';
    s = pushRecentChannel(s, 'a');
    s = pushRecentChannel(s, 'b');
    s = pushRecentChannel(s, 'a');
    expect(parseRecentChannels(s), ['a', 'b']);
  });

  test('capped', () {
    var s = '';
    for (var i = 0; i < 20; i++) {
      s = pushRecentChannel(s, '$i', max: 3);
    }
    expect(parseRecentChannels(s), ['19', '18', '17']);
  });

  test('ignores empty ids and blanks', () {
    expect(pushRecentChannel('a', ' '), 'a');
    expect(parseRecentChannels(' , a ,,b'), ['a', 'b']);
  });
}
