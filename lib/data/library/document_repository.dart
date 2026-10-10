import 'dart:convert';

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

  /// Visible documents in [folderId] (hides linked translation satellites).
  Future<List<Document>> listInFolder(int folderId) async {
    final hiddenIds = await _hiddenTranslationIds();
    final query = _db.select(_db.documents)
      ..where((d) => d.folderId.equals(folderId))
      ..orderBy([(d) => OrderingTerm.asc(d.title)]);
    if (hiddenIds.isNotEmpty) {
      query.where((d) => d.id.isNotIn(hiddenIds));
    }
    return query.get();
  }

  Future<Document?> getById(int id) {
    return (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(id))).getSingleOrNull();
  }

  /// Loads raw subtitle bytes for Reader open (design D5).
  ///
  /// Web / content mode: `utf8.encode(doc.content!)`.
  /// Native: sandbox file via [DocumentContentStore.load] using [Document.storageKey].
  Future<Uint8List> loadBytes(Document doc) async {
    final content = doc.content;
    if (content != null) {
      return Uint8List.fromList(utf8.encode(content));
    }
    final key = doc.storageKey;
    if (key == null || key.isEmpty) {
      throw StateError('Document has no content or storage key');
    }
    return contentStore.load(key);
  }

  /// Stores a translation in the original's folder and links it (LD-13).
  Future<Document> attachTranslation({
    required int originalDocumentId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final original = await getById(originalDocumentId);
    if (original == null) {
      throw LibraryValidationException('Document not found');
    }
    if (original.translationDocumentId != null) {
      throw LibraryValidationException(
        'Translation already attached; delete it before loading another',
      );
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
      return await _db.transaction(() async {
        final translationId = await _db
            .into(_db.documents)
            .insert(
              DocumentsCompanion.insert(
                folderId: original.folderId,
                title: title,
                format: format,
                storageKey: Value(stored.storageKey),
                content: Value(stored.content),
              ),
            );
        await (_db.update(_db.documents)
              ..where((d) => d.id.equals(originalDocumentId)))
            .write(
              DocumentsCompanion(
                translationDocumentId: Value(translationId),
                updatedAt: Value(DateTime.now()),
              ),
            );
        return await (_db.select(
          _db.documents,
        )..where((d) => d.id.equals(translationId))).getSingle();
      });
    } catch (e) {
      await contentStore.delete(stored.storageKey);
      rethrow;
    }
  }

  /// Removes linked translation storage and clears the original link (LD-14).
  Future<void> detachAndDeleteTranslation(int originalDocumentId) async {
    final original = await getById(originalDocumentId);
    if (original == null) {
      throw LibraryValidationException('Document not found');
    }
    final translationId = original.translationDocumentId;
    if (translationId == null) {
      return;
    }

    final translation = await getById(translationId);
    await _db.transaction(() async {
      await (_db.update(_db.documents)
            ..where((d) => d.id.equals(originalDocumentId)))
          .write(
            const DocumentsCompanion(
              translationDocumentId: Value(null),
            ),
          );
      await (_db.delete(
        _db.documents,
      )..where((d) => d.id.equals(translationId))).go();
    });
    if (translation != null) {
      await contentStore.delete(translation.storageKey);
    }
  }

  /// Linked translation document for Reader restore, or null (LD-16).
  Future<Document?> loadLinkedTranslation(Document original) async {
    final translationId = original.translationDocumentId;
    if (translationId == null) {
      return null;
    }
    return getById(translationId);
  }

  /// Deletes a document; cascades a linked hidden translation (LD-15).
  Future<void> deleteDocument(int documentId) async {
    final doc = await getById(documentId);
    if (doc == null) {
      throw LibraryValidationException('Document not found');
    }

    final translationId = doc.translationDocumentId;
    Document? translation;
    if (translationId != null) {
      translation = await getById(translationId);
    }

    await _db.transaction(() async {
      if (translationId != null) {
        await (_db.update(_db.documents)
              ..where((d) => d.id.equals(documentId)))
            .write(
              const DocumentsCompanion(
                translationDocumentId: Value(null),
              ),
            );
        await (_db.delete(
          _db.documents,
        )..where((d) => d.id.equals(translationId))).go();
      }
      // If this row was someone's translation, clear that link first.
      await (_db.update(_db.documents)
            ..where((d) => d.translationDocumentId.equals(documentId)))
          .write(
            const DocumentsCompanion(
              translationDocumentId: Value(null),
            ),
          );
      await (_db.delete(
        _db.documents,
      )..where((d) => d.id.equals(documentId))).go();
    });

    await contentStore.delete(doc.storageKey);
    if (translation != null) {
      await contentStore.delete(translation.storageKey);
    }
  }

  Future<List<int>> _hiddenTranslationIds() async {
    final linked = await (_db.select(_db.documents)
          ..where((d) => d.translationDocumentId.isNotNull()))
        .get();
    return linked
        .map((d) => d.translationDocumentId)
        .whereType<int>()
        .toList();
  }
}
