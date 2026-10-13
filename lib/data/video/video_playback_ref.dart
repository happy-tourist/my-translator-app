import 'dart:typed_data';

import 'video_playback_ref_io.dart'
    if (dart.library.html) 'video_playback_ref_web.dart' as impl;

/// Builds a session playback/extract ref from durable stored video bytes.
///
/// Web: `blob:` object URL (recreated each session from Drift bytes).
/// Native: writes a temp/sandbox file and returns its path.
Future<String> playbackRefFromMediaBytes({
  required Uint8List bytes,
  required String fileName,
  String? documentId,
}) =>
    impl.playbackRefFromMediaBytes(
      bytes: bytes,
      fileName: fileName,
      documentId: documentId,
    );
