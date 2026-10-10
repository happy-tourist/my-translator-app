import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/features/reader/nearest_cue_index.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';

CueDto _cue(int index, BigInt startMs) {
  return CueDto(
    index: index,
    startMs: startMs,
    endMs: startMs + BigInt.from(500),
    textLines: ['cue $index'],
  );
}

void main() {
  test('RS-05: nearestCueIndex picks cue with closest startMs', () {
    final cues = [
      _cue(0, BigInt.from(1000)),
      _cue(1, BigInt.from(3000)),
      _cue(2, BigInt.from(5000)),
    ];

    expect(nearestCueIndex(cues, BigInt.from(1000)), 0);
    expect(nearestCueIndex(cues, BigInt.from(2900)), 1);
    expect(nearestCueIndex(cues, BigInt.from(4500)), 2);
  });

  test('RS-05: equal distance prefers lower list index', () {
    final cues = [
      _cue(0, BigInt.from(1000)),
      _cue(1, BigInt.from(3000)),
    ];
    // Midpoint: |2000-1000| == |2000-3000| → index 0.
    expect(nearestCueIndex(cues, BigInt.from(2000)), 0);
  });

  test('nearestCueIndex returns -1 for empty list', () {
    expect(nearestCueIndex(const [], BigInt.from(1000)), -1);
  });

  test('nearestCueIndex compares BigInt without toInt truncation', () {
    final large = BigInt.parse('9223372036854775808'); // > int64 max
    final cues = [
      _cue(0, large),
      _cue(1, large + BigInt.from(1000)),
      _cue(2, large + BigInt.from(5000)),
    ];
    final anchor = large + BigInt.from(900);
    expect(nearestCueIndex(cues, anchor), 1);
  });
}
