/// Unicode scalar (rune) slicing for Reader cue text.
///
/// Matches Rust `str::chars()` / DTO `char_start`/`char_end` (design D2).
/// Do not use [String.substring] with those indices — it is UTF-16 based.
int cueCharLength(String text) => text.runes.length;

String cueCharSlice(String text, int start, int end) {
  if (start < 0 || end < start) return '';
  final runes = text.runes;
  final len = runes.length;
  if (start >= len) return '';
  final safeEnd = end > len ? len : end;
  return String.fromCharCodes(runes.skip(start).take(safeEnd - start));
}
