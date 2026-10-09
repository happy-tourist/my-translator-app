/// Supported subtitle formats stored on [Documents.format].
const supportedSubtitleFormats = {'srt', 'vtt', 'ass'};

/// Maps a file name extension to a stored format, or null if unsupported.
///
/// `.ssa` is stored as `ass` (design D3).
String? formatFromFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  final ext = fileName.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'srt' => 'srt',
    'vtt' => 'vtt',
    'ass' || 'ssa' => 'ass',
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
