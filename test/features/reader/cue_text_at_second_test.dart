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
  group('VF-04: end-second attachment', () {
    test('cueAttachmentSecond uses round(endMs/1000)', () {
      expect(
        cueAttachmentSecond(
          _cue(index: 0, startMs: 0, endMs: 51000, textLines: ['a']),
        ),
        51,
      );
      expect(
        cueAttachmentSecond(
          _cue(index: 0, startMs: 0, endMs: 51700, textLines: ['a']),
        ),
        52,
      );
      expect(
        cueAttachmentSecond(
          _cue(index: 0, startMs: 0, endMs: 400, textLines: ['a']),
        ),
        0,
      );
      expect(
        cueAttachmentSecond(
          _cue(index: 0, startMs: 0, endMs: 1500, textLines: ['a']),
        ),
        2,
      );
    });

    test('text only under rounded end second; start/middle empty', () {
      final cues = [
        _cue(
          index: 0,
          startMs: 1000,
          endMs: 3500,
          textLines: ['Hello', 'world'],
        ),
      ];
      // round(3500/1000)=4 → only second 4.
      expect(cueTextAtSecond(cues, 1), '');
      expect(cueTextAtSecond(cues, 2), '');
      expect(cueTextAtSecond(cues, 3), '');
      expect(cueTextAtSecond(cues, 4), 'Hello\nworld');
    });

    test('multi-cue same end second shows all texts', () {
      final cues = [
        _cue(index: 0, startMs: 0, endMs: 2000, textLines: ['first']),
        _cue(index: 1, startMs: 500, endMs: 2100, textLines: ['second']),
      ];
      // round(2000/1000)=2; round(2100/1000)=2.
      expect(cueTextAtSecond(cues, 2), 'first\nsecond');
      expect(cueIndicesAtEndSecond(cues, 2), [0, 1]);
      expect(cueTextAtSecond(cues, 0), '');
      expect(cueTextAtSecond(cues, 1), '');
    });

    test('empty when no cue ends on the second (VF-03)', () {
      final cues = [
        _cue(index: 0, startMs: 5000, endMs: 6000, textLines: ['later']),
      ];
      expect(cueTextAtSecond(cues, 1), '');
      expect(cueTextAtSecond(const [], 0), '');
      expect(cueIndexAtSecond(cues, 6), 0);
      expect(cueIndexAtSecond(cues, 1), isNull);
    });
  });
}
