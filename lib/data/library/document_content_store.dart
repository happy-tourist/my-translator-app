import 'dart:convert';
import 'dart:typed_data';

import 'package:my_translator_app/data/library/document_format.dart';

/// Result of persisting subtitle / EPUB bytes (native path and/or Drift content).
class StoredDocumentBytes {
  const StoredDocumentBytes({this.storageKey, this.content});

  /// Relative sandbox key on native; null on Web.
  final String? storageKey;

  /// Inline text for Web: UTF-8 for subtitles; base64 for EPUB (D6 / LD-27).
  final String? content;
}

/// Platform split for document bytes (design D6 / LD-09 / LD-27).
abstract class DocumentContentStore {
  Future<StoredDocumentBytes> store({
    required String fileName,
    required Uint8List bytes,
    String? format,
  });

  /// Reads sandbox bytes by [storageKey] (native / memory-key mode).
  Future<Uint8List> load(String storageKey);

  Future<void> delete(String? storageKey);
}

/// Encodes Web inline [Documents.content] for [format] (D6).
String encodeWebDocumentContent(Uint8List bytes, {String? format}) {
  if (isEpubFormat(format)) {
    return base64Encode(bytes);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// Decodes Web inline [Documents.content] for [format] (D6 / LD-27).
Uint8List decodeWebDocumentContent(String content, {required String format}) {
  if (isEpubFormat(format)) {
    return Uint8List.fromList(base64Decode(content));
  }
  return Uint8List.fromList(utf8.encode(content));
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
    String? format,
  }) async {
    if (storeAsContent) {
      return StoredDocumentBytes(
        content: encodeWebDocumentContent(bytes, format: format),
      );
    }
    final key = 'library_docs/${++_seq}_$fileName';
    files[key] = bytes;
    return StoredDocumentBytes(storageKey: key);
  }

  @override
  Future<Uint8List> load(String storageKey) async {
    final bytes = files[storageKey];
    if (bytes == null) {
      throw StateError('Document content not found for key: $storageKey');
    }
    return bytes;
  }

  @override
  Future<void> delete(String? storageKey) async {
    if (storageKey != null) {
      files.remove(storageKey);
    }
  }
}
