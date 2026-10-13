import 'package:my_translator_app/src/rust/api/parse.dart';

/// Whole-second attachment for a cue: `round(endMs / 1000)` (design D5, VF-04).
///
/// Ordinary arithmetic rounding (half away from zero via [num.round]).
int cueAttachmentSecond(CueDto cue) {
  return (cue.endMs.toInt() / 1000).round();
}

/// Indices of original cues whose rounded end second equals [second].
///
/// Order matches [cues]. Empty when none attach to [second].
List<int> cueIndicesAtEndSecond(List<CueDto> cues, int second) {
  final out = <int>[];
  for (var i = 0; i < cues.length; i++) {
    if (cueAttachmentSecond(cues[i]) == second) {
      out.add(i);
    }
  }
  return out;
}

/// First cue index attaching to [second], or `null` when none (VF-04).
int? cueIndexAtSecond(List<CueDto> cues, int second) {
  final indices = cueIndicesAtEndSecond(cues, second);
  return indices.isEmpty ? null : indices.first;
}

/// Display text under frame [second]: all cues with `round(endMs/1000) == second`.
///
/// Each cue's `textLines` joined with `\n`; multiple cues joined with `\n`
/// (VF-04). Empty when none attach — frame still shown (VF-03).
String cueTextAtSecond(List<CueDto> cues, int second) {
  final parts = <String>[];
  for (final cue in cues) {
    if (cueAttachmentSecond(cue) == second) {
      parts.add(cue.textLines.join('\n'));
    }
  }
  return parts.join('\n');
}
