import 'package:drift/drift.dart';

import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_format.dart';
import 'package:my_translator_app/data/library/library_exceptions.dart';

/// Drift-backed library documents (`library/documents`).
class DocumentRepository {
  DocumentRepository(this._db, {required this.contentStore});

  final AppDatabase _db;
  final DocumentContentStore contentStore;

  /// Imports a subtitle file into an existing folder. Rejects root / bad types.
  Future<Document> importIntoFolder({
    required int? folderId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (folderId == null) {
      throw LibraryValidationException(
        'Import requires a selected folder; documents cannot live at library root',
      );
    }
    final folder = await (_db.select(
      _db.folders,
    )..where((f) => f.id.equals(folderId))).getSingleOrNull();
    if (folder == null) {
      throw LibraryValidationException('Folder not found');
    }

    final format = formatFromFileName(fileName);
    if (format == null) {
      throw LibraryValidationException(
        'Unsupported file type. Use .srt, .vtt, .ass, or .ssa',
      );
    }

    final stored = await contentStore.store(fileName: fileName, bytes: bytes);
    final title = titleFromFileName(fileName);
    try {
      final id = await _db
          .into(_db.documents)
          .insert(
            DocumentsCompanion.insert(
              folderId: folderId,
              title: title,
              format: format,
              storageKey: Value(stored.storageKey),
              content: Value(stored.content),
            ),
          );
      return await (_db.select(
        _db.documents,
      )..where((d) => d.id.equals(id))).getSingle();
    } catch (e) {
      // Best-effort: avoid orphan sandbox files if the Drift insert fails.
      await contentStore.delete(stored.storageKey);
      rethrow;
    }
  }

  Future<List<Document>> listInFolder(int folderId) {
    return (_db.select(_db.documents)
          ..where((d) => d.folderId.equals(folderId))
          ..orderBy([(d) => OrderingTerm.asc(d.title)]))
        .get();
  }

  Future<Document?> getById(int id) {
    return (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(id))).getSingleOrNull();
  }

  Future<void> deleteDocument(int documentId) async {
    final doc = await getById(documentId);
    if (doc == null) {
      throw LibraryValidationException('Document not found');
    }
    await (_db.delete(
      _db.documents,
    )..where((d) => d.id.equals(documentId))).go();
    await contentStore.delete(doc.storageKey);
  }
}
