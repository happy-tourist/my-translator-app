import 'dart:js_interop';

import 'package:path/path.dart' as p;
import 'package:web/web.dart' as web;

import 'video_frame_errors.dart';
import 'video_usable_path.dart';

/// Web: build a blob object URL for canvas extract (design D2).
///
/// [UsableVideoPath.filesystemPath] holds the object URL (not a real FS path).
Future<UsableVideoPath> resolveUsableVideoPath(
  PickedVideoSource source, {
  String? documentId,
}) async {
  final bytes = source.bytes ?? await source.readBytes?.call();
  if (bytes == null || bytes.isEmpty) {
    throw const VideoFrameException(VideoFrameErrorKind.pathUnresolved);
  }

  final mime = _mimeForFileName(source.fileName);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  final objectUrl = web.URL.createObjectURL(blob);

  return UsableVideoPath(
    filesystemPath: objectUrl,
    originalUri: source.originalUri ?? objectUrl,
    copiedToSandbox: false,
  );
}

String _mimeForFileName(String fileName) {
  final ext = p.extension(fileName).toLowerCase();
  switch (ext) {
    case '.mkv':
      return 'video/x-matroska';
    case '.mp4':
    default:
      return 'video/mp4';
  }
}
