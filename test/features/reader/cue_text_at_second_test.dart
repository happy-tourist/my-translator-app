import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/features/reader/cue_text_at_second.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';

CueDto _cue({
  required int index,
  required int startMs,
  required int endMs,
  required List<String> textLines,
}) {
  return CueDto(
    index: index,
    startMs: BigInt.from(startMs),
    endMs: BigInt.from(endMs),
    textLines: textLines,
  );
}

void main() {
  group('VF-04: cueTextAtSecond', () {
    test('returns joined textLines when interval covers second', () {
      final cues = [
        _cue(
          index: 0,
          startMs: 500,
          endMs: 2500,
          textLines: ['Hello', 'world'],
        ),
      ];
      // t=1 → 1000ms inside [500, 2500); t=2 → 2000ms inside; t=0 → 0ms before start.
      expect(cueTextAtSecond(cues, 1), 'Hello\nworld');
      expect(cueTextAtSecond(cues, 2), 'Hello\nworld');
      expect(cueTextAtSecond(cues, 0), '');
    });

    test('half-open [startMs, endMs): endMs exclusive', () {
      final cues = [
        _cue(
          index: 0,
          startMs: 1000,
          endMs: 2000,
          textLines: ['A'],
        ),
      ];
      expect(cueTextAtSecond(cues, 1), 'A');
      expect(cueTextAtSecond(cues, 2), '');
    });

    test('first covering cue in list order wins', () {
      final cues = [
        _cue(index: 0, startMs: 0, endMs: 3000, textLines: ['first']),
        _cue(index: 1, startMs: 1000, endMs: 2000, textLines: ['second']),
      ];
      expect(cueTextAtSecond(cues, 1), 'first');
    });

    test('empty when no cue covers the second (VF-05)', () {
      final cues = [
        _cue(index: 0, startMs: 5000, endMs: 6000, textLines: ['later']),
      ];
      expect(cueTextAtSecond(cues, 1), '');
      expect(cueTextAtSecond(const [], 0), '');
    });
  });
}
