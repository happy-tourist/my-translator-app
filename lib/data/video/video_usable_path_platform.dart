import 'video_usable_path.dart';
import 'video_usable_path_io.dart'
    if (dart.library.html) 'video_usable_path_web.dart'
    as impl;

/// After pick: usable filesystem path for FFmpeg, never raw `content://` (D2).
Future<UsableVideoPath> resolveUsableVideoPath(
  PickedVideoSource source, {
  String? documentId,
}) =>
    impl.resolveUsableVideoPath(source, documentId: documentId);
