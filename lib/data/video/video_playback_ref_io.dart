import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Native: materialize durable bytes into the app sandbox and return the path.
Future<String> playbackRefFromMediaBytes({
  required Uint8List bytes,
  required String fileName,
  String? documentId,
}) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'video_extract'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final key = documentId ?? 'anon';
  final safeName = '${key}_restored_${p.basename(fileName)}';
  final out = File(p.join(dir.path, safeName));
  await out.writeAsBytes(bytes, flush: true);
  return out.absolute.path;
}
