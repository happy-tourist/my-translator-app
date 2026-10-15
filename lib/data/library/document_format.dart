/// Supported subtitle formats stored on [Documents.format].
const supportedSubtitleFormats = {'srt', 'vtt', 'ass'};

/// Stored format for EPUB documents (`library/documents` LD-24).
const documentFormatEpub = 'epub';

/// True when [format] is the EPUB book path (not subtitle cues).
bool isEpubFormat(String? format) => format == documentFormatEpub;

/// Maps a file name extension to a stored format, or null if unsupported.
///
/// `.ssa` is stored as `ass` (design D3). `.epub` → [documentFormatEpub].
String? formatFromFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  final ext = fileName.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'srt' => 'srt',
    'vtt' => 'vtt',
    'ass' || 'ssa' => 'ass',
    'epub' => documentFormatEpub,
    _ => null,
  };
}

/// Title derived from file name (basename without extension when present).
String titleFromFileName(String fileName) {
  final base = fileName.split(RegExp(r'[\\/]')).last;
  final dot = base.lastIndexOf('.');
  if (dot <= 0) return base;
  return base.substring(0, dot);
}

/// Shared reject copy for import / attach when extension is unknown (LD-03).
const unsupportedLibraryFileTypeMessage =
    'Unsupported file type. Use .srt, .vtt, .ass, .ssa, or .epub';

/// Reject copy when translation format family mismatches the original (LD-26).
const incompatibleTranslationFormatMessage =
    'Translation format must match the original (EPUB↔EPUB or subtitle↔subtitle)';

/// Notice when EPUB original and translation chapter counts differ (RS-16 / D5).
const mismatchedEpubChapterCountMessage =
    'Original and translation have different chapter counts';
