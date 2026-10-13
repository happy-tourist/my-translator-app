import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'video_frame_errors.dart';
import 'video_usable_path.dart';

/// Allowed Reader video extensions (design D8) — lowercase, no leading dot.
const Set<String> kReaderVideoExtensions = {'mp4', 'mkv'};

/// Injectable video pick for Reader (design D8) — separate from translation
/// [filePicker] so VF-01 / VF-11 tests do not touch split load.
typedef ReaderVideoPicker = Future<PickedReaderVideo?> Function();

/// Successful video pick payload (cancel → `null`, not an error).
class PickedReaderVideo {
  const PickedReaderVideo({
    required this.fileName,
    this.pickerPath,
    this.originalUri,
    this.bytes,
    this.readBytes,
  });

  final String fileName;

  /// [PlatformFile.path] when scheme is `file`.
  final String? pickerPath;

  /// Full URI string when available (may be `content://` — persist only).
  final String? originalUri;

  /// In-memory bytes when already loaded (web / small files).
  final Uint8List? bytes;

  /// Lazy byte reader when [bytes] is null.
  final Future<Uint8List> Function()? readBytes;

  /// Maps to native/web [resolveUsableVideoPath] input.
  PickedVideoSource toPickedVideoSource() => PickedVideoSource(
        fileName: fileName,
        pickerPath: pickerPath,
        originalUri: originalUri,
        bytes: bytes,
        readBytes: readBytes,
      );
}

/// True when [fileName] has a supported `.mp4` / `.mkv` extension (D8).
bool isSupportedReaderVideoFileName(String fileName) {
  final ext = p.extension(fileName).toLowerCase();
  if (ext.isEmpty) return false;
  final withoutDot = ext.startsWith('.') ? ext.substring(1) : ext;
  return kReaderVideoExtensions.contains(withoutDot);
}

/// Production picker: MP4/MKV filter + post-check (VF-11 on unsupported).
///
/// User cancel → `null` (silent). Unsupported extension → [VideoFrameException].
Future<PickedReaderVideo?> defaultReaderVideoPicker() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: kReaderVideoExtensions.toList(growable: false),
  );
  if (files.isEmpty) return null;

  final file = files.first;
  final name = file.name;
  if (!isSupportedReaderVideoFileName(name)) {
    throw const VideoFrameException(VideoFrameErrorKind.unsupportedFormat);
  }

  final uri = file.uri;
  final pickerPath = file.path;
  final originalUri = uri.toString();

  return PickedReaderVideo(
    fileName: name,
    pickerPath: pickerPath,
    originalUri: originalUri,
    readBytes: file.readAsBytes,
  );
}
