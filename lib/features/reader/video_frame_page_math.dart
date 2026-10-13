/// Whole-video second paging for the Reader frame strip (design D4, VF-02).
///
/// Page indices are **1-based**. Seconds on a page are
/// `3*(page-1) .. min(3*page, totalSeconds)-1`.
///
/// Returns `0` when [totalSeconds] < 1 (strip must not be shown — VF-11).
int videoFramePageCount(int totalSeconds) {
  if (totalSeconds < 1) return 0;
  return (totalSeconds + 2) ~/ 3;
}

/// Whole-second indices shown on 1-based [page] for [totalSeconds] coverage.
///
/// Empty when [page] is out of range or [totalSeconds] < 1.
List<int> videoFrameSecondsForPage(int page, int totalSeconds) {
  final pages = videoFramePageCount(totalSeconds);
  if (pages == 0 || page < 1 || page > pages) return const [];

  final start = 3 * (page - 1);
  final endExclusive = 3 * page < totalSeconds ? 3 * page : totalSeconds;
  return [for (var s = start; s < endExclusive; s++) s];
}

/// First whole second on 1-based [page], or `-1` when the page is empty.
int videoFramePageFirstSecond(int page, int totalSeconds) {
  final seconds = videoFrameSecondsForPage(page, totalSeconds);
  return seconds.isEmpty ? -1 : seconds.first;
}
