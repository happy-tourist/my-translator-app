import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'video_frame_errors.dart';
import 'video_usable_path.dart';

/// Native: prefer readable picker path; else sandbox copy (design D2).
Future<UsableVideoPath> resolveUsableVideoPath(
  PickedVideoSource source, {
  String? documentId,
}) async {
  final originalUri = source.originalUri ?? source.pickerPath;

  final candidate = source.pickerPath;
  if (isUsableFilesystemPath(candidate)) {
    final file = File(candidate!);
    if (await file.exists()) {
      try {
        // Touch-read to ensure the path is readable before handing to FFmpeg.
        final raf = await file.open(mode: FileMode.read);
        await raf.close();
        return UsableVideoPath(
          filesystemPath: file.absolute.path,
          originalUri: originalUri,
          copiedToSandbox: false,
        );
      } catch (_) {
        // Fall through to sandbox copy.
      }
    }
  }

  final bytes = source.bytes ?? await source.readBytes?.call();
  if (bytes == null || bytes.isEmpty) {
    // content:// without readable path/bytes — never hand URI to FFmpeg (D2).
    throw const VideoFrameException(VideoFrameErrorKind.pathUnresolved);
  }

  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'video_extract'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  final key = documentId ?? 'anon';
  final safeName =
      '${key}_${DateTime.now().microsecondsSinceEpoch}_'
      '${p.basename(source.fileName)}';
  final out = File(p.join(dir.path, safeName));
  await out.writeAsBytes(bytes, flush: true);

  return UsableVideoPath(
    filesystemPath: out.absolute.path,
    originalUri: originalUri,
    copiedToSandbox: true,
  );
}
