import 'package:my_translator_app/src/rust/api/parse.dart';

/// Display text for the original cue covering whole-second [second] (D5, VF-04).
///
/// Coverage is the half-open interval `[startMs, endMs)` at `second * 1000` ms.
/// When several cues match, the first in [cues] order wins. Display text is
/// `textLines` joined with `\n` (cues-first Reader join). No covering cue →
/// empty string (VF-05 — allowed, not an error).
String cueTextAtSecond(List<CueDto> cues, int second) {
  final tMs = BigInt.from(second) * BigInt.from(1000);
  for (final cue in cues) {
    if (cue.startMs <= tMs && tMs < cue.endMs) {
      return cue.textLines.join('\n');
    }
  }
  return '';
}
