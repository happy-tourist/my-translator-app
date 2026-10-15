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

/// Maps a UTF-16 code-unit offset (TextPainter / [TextPosition.offset]) to a
/// Unicode scalar index used by tokenize DTO spans.
int cueUtf16OffsetToCharIndex(String text, int utf16Offset) {
  if (utf16Offset <= 0) return 0;
  if (utf16Offset >= text.length) return cueCharLength(text);
  return text.substring(0, utf16Offset).runes.length;
}
