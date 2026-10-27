import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/vjod/channel_grouping.dart';

void main() {
  test('channelBaseKey merges quality variants but keeps real numbers', () {
    expect(channelBaseKey('M6'), channelBaseKey('M6 HD'));
    expect(channelBaseKey('M6 HD'), channelBaseKey('M6 FHD'));
    expect(channelBaseKey('France 2'), isNot(channelBaseKey('France 3')));
    expect(channelBaseKey('Canal+'), isNot(channelBaseKey('Canal+ Sport')));
    expect(channelBaseKey('beIN Sports 1 HD'),
        isNot(channelBaseKey('beIN Sports 2')));
  });

  test('channelQualityRank orders UHD < FHD < HD < plain < SD', () {
    expect(channelQualityRank('M6 UHD') < channelQualityRank('M6 FHD'), isTrue);
    expect(channelQualityRank('M6 FHD') < channelQualityRank('M6 HD'), isTrue);
    expect(channelQualityRank('M6 HD') < channelQualityRank('M6'), isTrue);
    expect(channelQualityRank('M6') < channelQualityRank('M6 SD'), isTrue);
  });

  test('groupChannelIndices collapses duplicates, best variant first', () {
    final names = ['M6 SD', 'TF1', 'M6 FHD', 'M6', 'France 3'];
    final groups = groupChannelIndices(names);
    // Three groups: M6 (first appearance), TF1, France 3.
    expect(groups.length, 3);
    // The M6 group holds all three M6 variants, FHD first, SD last.
    final m6 = groups.firstWhere((g) => names[g.first].startsWith('M6'));
    expect(m6.length, 3);
    expect(names[m6.first], 'M6 FHD');
    expect(names[m6.last], 'M6 SD');
    // Group order follows first appearance: M6, TF1, France 3.
    expect(names[groups[0].first].startsWith('M6'), isTrue);
    expect(names[groups[1].first], 'TF1');
    expect(names[groups[2].first], 'France 3');
  });
}
