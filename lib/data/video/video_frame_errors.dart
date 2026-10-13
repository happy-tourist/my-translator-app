/// Typed video pick / probe / extract failures (VF-10 / VF-11).
///
/// Orchestration maps [userMessage] to SnackBar / inline surfaces — never raw
/// FFmpeg / DOM internals (`client-work-with-errors`).
enum VideoFrameErrorKind {
  /// Extension / container not MP4 or MKV (D8 / VF-11).
  unsupportedFormat,

  /// Duration probe failed or unusable (VF-11).
  probeFailed,

  /// Single-second JPEG extract failed (VF-10 slot placeholder).
  extractFailed,

  /// No readable filesystem / blob ref for extract (content:// rejected — D2).
  pathUnresolved,
}

/// User-safe exception for Reader video flows (SnackBar-ready [message]).
class VideoFrameException implements Exception {
  const VideoFrameException(this.kind, [String? message])
      : message = message ?? '';

  final VideoFrameErrorKind kind;

  /// Optional detail; prefer [userMessage] for UI.
  final String message;

  /// Locked SnackBar / inline copy for [kind].
  String get userMessage => videoFrameUserMessage(kind);

  @override
  String toString() => message.isEmpty ? userMessage : '$userMessage ($message)';
}

/// Locked EN user-visible copy (VF-11 / VF-10).
String videoFrameUserMessage(VideoFrameErrorKind kind) {
  switch (kind) {
    case VideoFrameErrorKind.unsupportedFormat:
      return 'Unsupported video type. Use MP4 or MKV.';
    case VideoFrameErrorKind.probeFailed:
      return "Couldn't read that video. Try another MP4 or MKV file.";
    case VideoFrameErrorKind.extractFailed:
      return "Couldn't extract a frame from that video.";
    case VideoFrameErrorKind.pathUnresolved:
      return "Couldn't access that video file.";
  }
}
