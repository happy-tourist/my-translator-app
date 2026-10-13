/// Pure reading-time → whole-second helpers for Reader video frames (VF-05).
///
/// Coverage is whole-video seconds `[0, durationSeconds-1]`. Paging of those
/// seconds is in [video_frame_page_math.dart].
library;

import 'package:my_translator_app/features/reader/video_frame_page_math.dart';

export 'package:my_translator_app/features/reader/video_frame_page_math.dart';

/// Clamp reading time to a whole-second index (VF-05 / VF-13).
///
/// Uses `floor(readingTimeMs / 1000)` then clamps into
/// `[0, durationSeconds - 1]`. Returns `-1` when [durationSeconds] < 1
/// (caller must not show video pages).
int clampReadingTimeToSecond(int readingTimeMs, int durationSeconds) {
  if (durationSeconds < 1) return -1;
  var second = readingTimeMs < 0 ? 0 : readingTimeMs ~/ 1000;
  if (second >= durationSeconds) {
    second = durationSeconds - 1;
  }
  return second;
}

/// 1-based page containing the clamped reading second (VF-05 / VF-13).
int clampReadingTimeToPage(int readingTimeMs, int durationSeconds) {
  final second = clampReadingTimeToSecond(readingTimeMs, durationSeconds);
  if (second < 0) return 1;
  return videoFramePageForSecond(second, durationSeconds);
}
