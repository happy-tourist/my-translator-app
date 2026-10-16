import 'package:drift/drift.dart';

import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_format.dart';
import 'package:my_translator_app/data/library/library_exceptions.dart';

/// Saved original-pane reading position (`library/documents` LD-17 / LD-28).
///
/// Format-gated semantics for [startMs]:
/// - subtitle documents: cue `startMs` (milliseconds);
/// - EPUB (`documentFormatEpub`): **0-based chapter index** (design D6).
class ReadingAnchor {
  const ReadingAnchor({required this.startMs, this.alignment});

  /// Subtitle cue start ms, or EPUB 0-based chapter index (see class docs).
  final int startMs;

  /// Optional `itemLeadingEdge` in `0.0…1.0` (cue list or paragraph list).
  final double? alignment;
}

/// Persisted video attachment on an original document (`library/documents` LD-20).
class VideoAttachment {
  const VideoAttachment({
    this.videoUri,
    this.sandboxPath,
    required this.durationSec,
    this.lastFramePage,
    this.hasStoredMedia = false,
    this.mediaFileName,
  });

  /// Durable platform ref / bookmark (may become a dead link — LD-22).
  final String? videoUri;

  /// Optional sandbox extract path (native usable filesystem path).
  final String? sandboxPath;

  /// Probed duration in whole seconds (≥ 1 when timeline is shown).
  final int durationSec;

  /// Optional last viewed timeline second (0-based). Column historically named
  /// `last_frame_page`; reused as `last_second` (design D7).
  final int? lastFramePage;

  /// True when full video bytes are stored in [DocumentVideoMedia] (Web reopen).
  final bool hasStoredMedia;

  /// Original file name for MIME / sandbox restore when [hasStoredMedia].
  final String? mediaFileName;
}

/// Durable full-video payload in Drift (`DocumentVideoMedia`).
class StoredVideoMedia {
  const StoredVideoMedia({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

/// Drift-backed library documents (`library/documents`).
class DocumentRepository {
  DocumentRepository(this._db, {required this.contentStore});

  final AppDatabase _db;
  final DocumentContentStore contentStore;

  /// Imports a subtitle or EPUB file into a folder or library root.
  /// [folderId] null = root (LD-02). Rejects bad types (LD-03 / LD-24).
  Future<Document> importIntoFolder({
    required int? folderId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (folderId != null) {
      final folder = await (_db.select(
        _db.folders,
      )..where((f) => f.id.equals(folderId))).getSingleOrNull();
      if (folder == null) {
        throw LibraryValidationException('Folder not found');
      }
    }

    final format = formatFromFileName(fileName);
    if (format == null) {
      throw LibraryValidationException(unsupportedLibraryFileTypeMessage);
    }

    final stored = await contentStore.store(
      fileName: fileName,
      bytes: bytes,
      format: format,
    );
    final title = titleFromFileName(fileName);
    try {
      final id = await _db
          .into(_db.documents)
          .insert(
            DocumentsCompanion.insert(
              folderId: Value(folderId),
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

  /// Visible documents at [folderId] (null = root). Hides translation satellites.
  Future<List<Document>> listVisible({int? folderId}) async {
    final hiddenIds = await _hiddenTranslationIds();
    final query = _db.select(_db.documents)
      ..where(
        (d) => folderId == null
            ? d.folderId.isNull()
            : d.folderId.equals(folderId),
      )
      ..orderBy([(d) => OrderingTerm.asc(d.title)]);
    if (hiddenIds.isNotEmpty) {
      query.where((d) => d.id.isNotIn(hiddenIds));
    }
    return query.get();
  }

  /// Visible documents in [folderId] (thin wrapper over [listVisible]).
  Future<List<Document>> listInFolder(int folderId) =>
      listVisible(folderId: folderId);

  Future<Document?> getById(int id) {
    return (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(id))).getSingleOrNull();
  }

  /// Loads raw document bytes for Reader open (design D5 / D6).
  ///
  /// Web / content mode: format-gated decode (UTF-8 subtitles; base64 EPUB).
  /// Native: sandbox file via [DocumentContentStore.load] using [Document.storageKey].
  Future<Uint8List> loadBytes(Document doc) async {
    final content = doc.content;
    if (content != null) {
      return decodeWebDocumentContent(content, format: doc.format);
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
      throw LibraryValidationException(unsupportedLibraryFileTypeMessage);
    }
    // LD-26 / D5: EPUB↔EPUB or subtitle↔subtitle only (no mixed link).
    if (isEpubFormat(original.format) != isEpubFormat(format)) {
      throw LibraryValidationException(incompatibleTranslationFormatMessage);
    }

    final stored = await contentStore.store(
      fileName: fileName,
      bytes: bytes,
      format: format,
    );
    final title = titleFromFileName(fileName);
    try {
      return await _db.transaction(() async {
        final translationId = await _db
            .into(_db.documents)
            .insert(
              DocumentsCompanion.insert(
                folderId: Value(original.folderId),
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

  /// Persists the original document's reading anchor (LD-17 / LD-28 / D6).
  ///
  /// [startMs] is cue start ms for subtitles, or 0-based chapter index for EPUB
  /// (same Drift column; format-gated at call sites). Best-effort — must not
  /// block UI when the row is missing.
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

  /// Loads the saved reading anchor for [documentId], or null (LD-17 / LD-28).
  ///
  /// Callers interpret [ReadingAnchor.startMs] by document format (chapter
  /// index when EPUB).
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
    Uint8List? mediaBytes,
    String? mediaFileName,
  }) async {
    final original = await getById(documentId);
    if (original == null) {
      throw LibraryValidationException('Document not found');
    }
    if (durationSec < 0) {
      throw LibraryValidationException('Video duration must not be negative');
    }
    if (lastFramePage != null && lastFramePage < 0) {
      throw LibraryValidationException('Last second must be ≥ 0');
    }
    if (mediaBytes != null && mediaBytes.isEmpty) {
      throw LibraryValidationException('Video media bytes must not be empty');
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
      if (mediaBytes != null) {
        await _db.into(_db.documentVideoMedia).insertOnConflictUpdate(
              DocumentVideoMediaCompanion.insert(
                documentId: Value(documentId),
                bytes: mediaBytes,
                fileName: mediaFileName ?? 'video.mp4',
              ),
            );
      } else if (clearFrameCache) {
        // Replace without new bytes → drop stale media (LD-23-ish).
        await _clearVideoMedia(documentId);
      }
    });
  }

  /// Persists optional last timeline second without touching JPEG cache
  /// (D7 `last_second` via `video_last_frame_page` column).
  Future<void> saveVideoLastFramePage({
    required int documentId,
    required int lastFramePage,
  }) async {
    final original = await getById(documentId);
    if (original == null) {
      throw LibraryValidationException('Document not found');
    }
    if (lastFramePage < 0) {
      throw LibraryValidationException('Last second must be ≥ 0');
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
      await _clearVideoMedia(documentId);
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
  /// (dead link keeps meta + cache — LD-22). Prefer [getVideoMedia] +
  /// [playbackRefFromMediaBytes] on Web after reload.
  Future<VideoAttachment?> getVideoAttachment(int documentId) async {
    final doc = await getById(documentId);
    if (doc == null) return null;
    final durationSec = doc.videoDurationSec;
    if (durationSec == null) return null;
    final media = await (_db.select(_db.documentVideoMedia)
          ..where((m) => m.documentId.equals(documentId)))
        .getSingleOrNull();
    return VideoAttachment(
      videoUri: doc.videoUri,
      sandboxPath: doc.videoSandboxPath,
      durationSec: durationSec,
      lastFramePage: doc.videoLastFramePage,
      hasStoredMedia: media != null,
      mediaFileName: media?.fileName,
    );
  }

  /// Full video bytes when stored for durable reopen (schema 6).
  Future<StoredVideoMedia?> getVideoMedia(int documentId) async {
    final row = await (_db.select(_db.documentVideoMedia)
          ..where((m) => m.documentId.equals(documentId)))
        .getSingleOrNull();
    if (row == null) return null;
    return StoredVideoMedia(bytes: row.bytes, fileName: row.fileName);
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
      // LD-18: clear JPEG frame cache + video media before removing the original.
      await _clearFrameCache(documentId);
      await _clearVideoMedia(documentId);
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

  Future<void> _clearVideoMedia(int documentId) async {
    await (_db.delete(
      _db.documentVideoMedia,
    )..where((m) => m.documentId.equals(documentId))).go();
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
