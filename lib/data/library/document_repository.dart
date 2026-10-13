import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_format.dart';
import 'package:my_translator_app/data/library/library_exceptions.dart';

/// Saved original-pane reading position (`library/documents` LD-17).
class ReadingAnchor {
  const ReadingAnchor({required this.startMs, this.alignment});

  /// Cue start time in milliseconds (fits i64; compare to [CueDto.startMs] as BigInt).
  final int startMs;

  /// Optional `itemLeadingEdge` in `0.0…1.0`.
  final double? alignment;
}

/// Persisted video attachment on an original document (`library/documents` LD-20).
class VideoAttachment {
  const VideoAttachment({
    this.videoUri,
    this.sandboxPath,
    required this.durationSec,
    this.lastFramePage,
  });

  /// Durable platform ref / bookmark (may become a dead link — LD-22).
  final String? videoUri;

  /// Optional sandbox extract path (native usable filesystem path).
  final String? sandboxPath;

  /// Probed duration in whole seconds (≥ 1 when strip is shown).
  final int durationSec;

  /// Optional last viewed frame-strip page (1-based).
  final int? lastFramePage;
}

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

  /// Persists the original document's reading anchor (LD-17 / D9).
  ///
  /// No-op if [documentId] is missing (best-effort; D10 — must not block UI).
  Future<void> saveReadingAnchor({
    required int documentId,
    required int startMs,
    double? alignment,
  }) async {
    final clampedAlignment = alignment?.clamp(0.0, 1.0);
    await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
        .write(
          DocumentsCompanion(
            lastReadStartMs: Value(startMs),
            lastReadAlignment: Value(clampedAlignment?.toDouble()),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  /// Loads the saved reading anchor for [documentId], or null (LD-17).
  Future<ReadingAnchor?> loadReadingAnchor(int documentId) async {
    final doc = await getById(documentId);
    if (doc == null) return null;
    final startMs = doc.lastReadStartMs;
    if (startMs == null) return null;
    return ReadingAnchor(
      startMs: startMs,
      alignment: doc.lastReadAlignment,
    );
  }

  /// Attaches (or replaces) video meta on the original (LD-20 / LD-23).
  ///
  /// Default [clearFrameCache] `true` replaces link/duration and clears prior
  /// JPEG frames (LD-23). Pass `false` for dead-link re-pick so visited-second
  /// JPEG remain usable (LD-22).
  Future<void> attachVideo({
    required int documentId,
    String? videoUri,
    String? sandboxPath,
    required int durationSec,
    int? lastFramePage,
    bool clearFrameCache = true,
  }) async {
    final original = await getById(documentId);
    if (original == null) {
      throw LibraryValidationException('Document not found');
    }
    if (durationSec < 0) {
      throw LibraryValidationException('Video duration must not be negative');
    }

    await _db.transaction(() async {
      if (clearFrameCache) {
        await _clearFrameCache(documentId);
      }
      await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
          .write(
            DocumentsCompanion(
              videoUri: Value(videoUri),
              videoSandboxPath: Value(sandboxPath),
              videoDurationSec: Value(durationSec),
              videoLastFramePage: Value(lastFramePage),
              updatedAt: Value(DateTime.now()),
            ),
          );
    });
  }

  /// Persists optional strip page without touching JPEG cache (D7 last_frame_page).
  Future<void> saveVideoLastFramePage({
    required int documentId,
    required int lastFramePage,
  }) async {
    final original = await getById(documentId);
    if (original == null) {
      throw LibraryValidationException('Document not found');
    }
    if (lastFramePage < 1) {
      throw LibraryValidationException('Frame page must be ≥ 1');
    }
    if (original.videoDurationSec == null) {
      return;
    }
    await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
        .write(
          DocumentsCompanion(
            videoLastFramePage: Value(lastFramePage),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  /// Clears video link and JPEG frame cache; original remains (LD-21).
  Future<void> detachVideo(int documentId) async {
    final original = await getById(documentId);
    if (original == null) {
      throw LibraryValidationException('Document not found');
    }

    await _db.transaction(() async {
      await _clearFrameCache(documentId);
      await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
          .write(
            DocumentsCompanion(
              videoUri: const Value(null),
              videoSandboxPath: const Value(null),
              videoDurationSec: const Value(null),
              videoLastFramePage: const Value(null),
              updatedAt: Value(DateTime.now()),
            ),
          );
    });
  }

  /// Returns saved video attachment meta, or null when none (LD-19 / LD-20).
  ///
  /// Does not validate that [VideoAttachment.videoUri] is still readable
  /// (dead link keeps meta + cache — LD-22).
  Future<VideoAttachment?> getVideoAttachment(int documentId) async {
    final doc = await getById(documentId);
    if (doc == null) return null;
    final durationSec = doc.videoDurationSec;
    if (durationSec == null) return null;
    return VideoAttachment(
      videoUri: doc.videoUri,
      sandboxPath: doc.videoSandboxPath,
      durationSec: durationSec,
      lastFramePage: doc.videoLastFramePage,
    );
  }

  /// Upserts a JPEG frame for [second] on [documentId] (LD-20).
  Future<void> putFrameCache({
    required int documentId,
    required int second,
    required Uint8List jpegBytes,
  }) async {
    if (second < 0) {
      throw LibraryValidationException('Frame second must not be negative');
    }
    final original = await getById(documentId);
    if (original == null) {
      throw LibraryValidationException('Document not found');
    }

    await _db
        .into(_db.documentVideoFrames)
        .insertOnConflictUpdate(
          DocumentVideoFramesCompanion.insert(
            documentId: documentId,
            second: second,
            jpegBytes: jpegBytes,
          ),
        );
  }

  /// Loads a cached JPEG for [second], or null if missing (LD-20 / LD-22).
  Future<Uint8List?> getFrameCache({
    required int documentId,
    required int second,
  }) async {
    final row =
        await (_db.select(_db.documentVideoFrames)..where(
              (f) => f.documentId.equals(documentId) & f.second.equals(second),
            ))
            .getSingleOrNull();
    return row?.jpegBytes;
  }

  /// Deletes a document; cascades translation (LD-15) and video (LD-18).
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
      // LD-18: clear JPEG frame cache before removing the original row.
      await _clearFrameCache(documentId);
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

  Future<void> _clearFrameCache(int documentId) async {
    await (_db.delete(
      _db.documentVideoFrames,
    )..where((f) => f.documentId.equals(documentId))).go();
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
