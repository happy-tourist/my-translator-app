import 'dart:js_interop';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:web/web.dart' as web;

/// Web: recreate a session object URL from durable Drift bytes.
Future<String> playbackRefFromMediaBytes({
  required Uint8List bytes,
  required String fileName,
  String? documentId,
}) async {
  final mime = _mimeForFileName(fileName);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime),
  );
  return web.URL.createObjectURL(blob);
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
