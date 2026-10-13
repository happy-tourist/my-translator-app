import 'dart:typed_data';

/// Injectable usable-path resolve after pick (tests skip sandbox / path_provider).
typedef ResolveUsableVideoPathFn = Future<UsableVideoPath> Function(
  PickedVideoSource source, {
  String? documentId,
});

/// Filesystem path FFmpegKit may open (design D2).
///
/// [filesystemPath] is never a raw `content://` URI.
class UsableVideoPath {
  const UsableVideoPath({
    required this.filesystemPath,
    this.originalUri,
    this.copiedToSandbox = false,
  });

  /// Native: absolute path suitable for FFmpeg `-i`.
  /// Web: blob/object URL for `<video>.src` (not a real filesystem path).
  final String filesystemPath;

  /// Optional durable picker URI / original path for persist meta.
  final String? originalUri;

  /// True when bytes were copied into the app sandbox.
  final bool copiedToSandbox;
}

/// Input from [file_picker] after a video pick (native).
class PickedVideoSource {
  const PickedVideoSource({
    required this.fileName,
    this.pickerPath,
    this.originalUri,
    this.bytes,
    this.readBytes,
  });

  final String fileName;

  /// [PlatformFile.path] when scheme is `file`; often null for SAF/`content://`.
  final String? pickerPath;

  /// Full URI string when available (may be `content://` — persist only, not FFmpeg).
  final String? originalUri;

  /// In-memory bytes when already loaded.
  final Uint8List? bytes;

  /// Lazy byte reader (e.g. [PlatformFile.readAsBytes]) when [bytes] is null.
  final Future<Uint8List> Function()? readBytes;
}

/// True when [value] looks like an Android SAF / content URI (unsafe for FFmpeg `-i`).
bool isContentUri(String? value) {
  if (value == null || value.isEmpty) return false;
  final lower = value.toLowerCase();
  return lower.startsWith('content://');
}

/// True when [path] is a non-empty filesystem path and not a content URI.
bool isUsableFilesystemPath(String? path) {
  if (path == null || path.isEmpty) return false;
  if (isContentUri(path)) return false;
  return true;
}
