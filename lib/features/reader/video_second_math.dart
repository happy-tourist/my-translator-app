/// Pure second-timeline math for Reader video frames (design D4, VF-02 / VF-05).
///
/// Timeline length is whole-video seconds `[0, durationSeconds-1]`. Page-of-3
/// strip math is not acceptance for the UX revision.
library;

/// Number of second rows in the timeline (`floor(duration)` coverage).
///
/// Returns `0` when [durationSeconds] < 1 (timeline must not be shown — VF-11).
int videoTimelineSecondCount(int durationSeconds) {
  if (durationSeconds < 1) return 0;
  return durationSeconds;
}

/// Whether [second] is a valid row index for a timeline of [durationSeconds].
bool isValidTimelineSecond(int second, int durationSeconds) {
  return durationSeconds >= 1 && second >= 0 && second < durationSeconds;
}

/// Clamp reading time to a timeline second index (VF-05 / VF-13).
///
/// Uses `floor(readingTimeMs / 1000)` then clamps into
/// `[0, durationSeconds - 1]`. Returns `-1` when [durationSeconds] < 1
/// (caller must not show a timeline).
int clampReadingTimeToSecond(int readingTimeMs, int durationSeconds) {
  if (durationSeconds < 1) return -1;
  var second = readingTimeMs < 0 ? 0 : readingTimeMs ~/ 1000;
  if (second >= durationSeconds) {
    second = durationSeconds - 1;
  }
  return second;
}
