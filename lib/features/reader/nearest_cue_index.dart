import 'package:my_translator_app/src/rust/api/parse.dart';

/// Returns the list index of the cue whose [CueDto.startMs] is nearest to
/// [startMs] (absolute BigInt distance). On a tie, the lower list index wins.
///
/// Empty [cues] → `-1` (caller should no-op sync).
int nearestCueIndex(List<CueDto> cues, BigInt startMs) {
  if (cues.isEmpty) return -1;

  var bestIndex = 0;
  var bestDist = (cues[0].startMs - startMs).abs();

  for (var i = 1; i < cues.length; i++) {
    final dist = (cues[i].startMs - startMs).abs();
    if (dist < bestDist) {
      bestDist = dist;
      bestIndex = i;
    }
  }

  return bestIndex;
}
