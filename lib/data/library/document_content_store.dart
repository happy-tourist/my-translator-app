import 'dart:convert';
import 'dart:typed_data';

/// Result of persisting subtitle bytes (native path and/or Drift content).
class StoredDocumentBytes {
  const StoredDocumentBytes({this.storageKey, this.content});

  /// Relative sandbox key on native; null on Web.
  final String? storageKey;

  /// Inline UTF-8 text for Web (and optional native fallback).
  final String? content;
}

/// Platform split for subtitle bytes (design D6 / LD-09).
abstract class DocumentContentStore {
  Future<StoredDocumentBytes> store({
    required String fileName,
    required Uint8List bytes,
  });

  Future<void> delete(String? storageKey);
}

/// In-memory store for unit/widget tests.
class MemoryDocumentContentStore implements DocumentContentStore {
  MemoryDocumentContentStore({this.storeAsContent = true});

  final Map<String, Uint8List> files = {};
  var _seq = 0;

  /// When true, persist as Drift [content] (Web); else as [storageKey].
  final bool storeAsContent;

  @override
  Future<StoredDocumentBytes> store({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (storeAsContent) {
      return StoredDocumentBytes(
        content: utf8.decode(bytes, allowMalformed: true),
      );
    }
    final key = 'library_docs/${++_seq}_$fileName';
    files[key] = bytes;
    return StoredDocumentBytes(storageKey: key);
  }

  @override
  Future<void> delete(String? storageKey) async {
    if (storageKey != null) {
      files.remove(storageKey);
    }
  }
}
