import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'document_content_store.dart';

DocumentContentStore createStore() => _IoDocumentContentStore();

class _IoDocumentContentStore implements DocumentContentStore {
  @override
  Future<StoredDocumentBytes> store({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'library_docs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safeName =
        '${DateTime.now().microsecondsSinceEpoch}_'
        '${p.basename(fileName)}';
    final file = File(p.join(dir.path, safeName));
    await file.writeAsBytes(bytes, flush: true);
    return StoredDocumentBytes(storageKey: p.join('library_docs', safeName));
  }

  @override
  Future<void> delete(String? storageKey) async {
    if (storageKey == null || storageKey.isEmpty) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(p.join(docs.path, storageKey));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup after Drift commit (design D5).
    }
  }
}
