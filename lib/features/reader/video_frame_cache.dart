import 'dart:typed_data';

import 'package:my_translator_app/data/library/document_repository.dart';

/// Injectable JPEG frame cache for the Reader strip (design D4 / D9).
///
/// Production wires DocumentRepository get/put frame cache; tests use
/// [MemoryVideoFrameCache].
abstract class VideoFrameCache {
  Future<Uint8List?> get(int second);

  Future<void> put(int second, Uint8List jpegBytes);
}

/// In-memory cache for widget/unit tests (no Drift).
class MemoryVideoFrameCache implements VideoFrameCache {
  final Map<int, Uint8List> _store = {};

  Map<int, Uint8List> get entries => Map.unmodifiable(_store);

  @override
  Future<Uint8List?> get(int second) async => _store[second];

  @override
  Future<void> put(int second, Uint8List jpegBytes) async {
    _store[second] = jpegBytes;
  }
}

/// Drift-backed cache for production Reader sessions (LD-20 / LD-22).
class DocumentRepositoryVideoFrameCache implements VideoFrameCache {
  DocumentRepositoryVideoFrameCache(this._repo, this.documentId);

  final DocumentRepository _repo;
  final int documentId;

  @override
  Future<Uint8List?> get(int second) =>
      _repo.getFrameCache(documentId: documentId, second: second);

  @override
  Future<void> put(int second, Uint8List jpegBytes) => _repo.putFrameCache(
        documentId: documentId,
        second: second,
        jpegBytes: jpegBytes,
      );
}
