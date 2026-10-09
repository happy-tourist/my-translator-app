import 'dart:convert';
import 'dart:typed_data';

import 'document_content_store.dart';

DocumentContentStore createStore() => _WebDocumentContentStore();

class _WebDocumentContentStore implements DocumentContentStore {
  @override
  Future<StoredDocumentBytes> store({
    required String fileName,
    required Uint8List bytes,
  }) async {
    return StoredDocumentBytes(
      content: utf8.decode(bytes, allowMalformed: true),
    );
  }

  @override
  Future<void> delete(String? storageKey) async {}
}
