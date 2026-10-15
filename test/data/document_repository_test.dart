import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_format.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/data/library/library_exceptions.dart';

import '../support/test_database.dart';

Uint8List _srtBytes([String text = 'Hi']) =>
    Uint8List.fromList(utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n$text\n'));

/// Synthetic ZIP/EPUB-like bytes that UTF-8 roundtrip would corrupt (LD-27).
Uint8List _epubLikeBytes() => Uint8List.fromList([
      0x50, 0x4B, 0x03, 0x04, // ZIP local file header
      0x00, 0xFF, 0xFE, 0x80, 0x81, 0x00, 0x7F, 0xC0,
      for (var i = 0; i < 32; i++) i * 7 & 0xFF,
    ]);

void main() {
  late final db = createTestDatabase();
  late MemoryDocumentContentStore store;
  late FolderRepository folders;
  late DocumentRepository documents;

  setUp(() {
    store = MemoryDocumentContentStore(storeAsContent: true);
    folders = FolderRepository(db, contentStore: store);
    documents = DocumentRepository(db, contentStore: store);
  });

  tearDownAll(() async {
    await db.close();
  });

  tearDown(() async {
    await db.delete(db.documentVideoFrames).go();
    await db.delete(db.documents).go();
    await db.delete(db.folders).go();
  });

  test('LD-01: Import valid subtitle file', () async {
    final folder = await folders.createFolder(name: 'S01');
    final doc = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'episode1.srt',
      bytes: _srtBytes(),
    );
    expect(doc.title, 'episode1');
    expect(doc.format, 'srt');
    expect(doc.folderId, folder.id);
    final listed = await documents.listInFolder(folder.id);
    expect(listed.map((d) => d.title), contains('episode1'));
  });

  test('LD-02: Reject import without folder', () async {
    expect(
      () => documents.importIntoFolder(
        folderId: null,
        fileName: 'episode1.srt',
        bytes: _srtBytes(),
      ),
      throwsA(isA<LibraryValidationException>()),
    );
  });

  test('LD-03: Reject unsupported file type', () async {
    final folder = await folders.createFolder(name: 'S01');
    expect(
      () => documents.importIntoFolder(
        folderId: folder.id,
        fileName: 'notes.txt',
        bytes: Uint8List.fromList(utf8.encode('hello')),
      ),
      throwsA(
        isA<LibraryValidationException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported'),
        ),
      ),
    );
    expect(await documents.listInFolder(folder.id), isEmpty);
  });

  test('LD-04: List documents after import', () async {
    final folder = await folders.createFolder(name: 'S01');
    await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'a.srt',
      bytes: _srtBytes('a'),
    );
    await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'b.vtt',
      bytes: Uint8List.fromList(utf8.encode('WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nb\n')),
    );
    final listed = await documents.listInFolder(folder.id);
    expect(listed.map((d) => d.title).toList(), ['a', 'b']);
  });

  test('LD-05: Delete one document', () async {
    final folder = await folders.createFolder(name: 'S01');
    final keep = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'keep.srt',
      bytes: _srtBytes('keep'),
    );
    final drop = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'episode1.srt',
      bytes: _srtBytes('drop'),
    );
    await documents.deleteDocument(drop.id);
    final listed = await documents.listInFolder(folder.id);
    expect(listed.map((d) => d.id), [keep.id]);
    expect(await folders.getById(folder.id), isNotNull);
  });

  test('LD-07: Import ASS/SSA file as format ass', () async {
    final folder = await folders.createFolder(name: 'S01');
    final ssa = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'show.ssa',
      bytes: Uint8List.fromList(utf8.encode('[Script Info]\n')),
    );
    final ass = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'show.ass',
      bytes: Uint8List.fromList(utf8.encode('[Script Info]\n')),
    );
    expect(ssa.format, 'ass');
    expect(ass.format, 'ass');
  });

  test('LD-09: Web import stores content (no filesystem path)', () async {
    final webStore = MemoryDocumentContentStore(storeAsContent: true);
    final webDocs = DocumentRepository(db, contentStore: webStore);
    final folder = await folders.createFolder(name: 'S01');
    final doc = await webDocs.importIntoFolder(
      folderId: folder.id,
      fileName: 'web.srt',
      bytes: _srtBytes('web'),
    );
    expect(doc.content, isNotNull);
    expect(doc.content, contains('web'));
    expect(doc.storageKey, isNull);
  });

  test('loadBytes: Web content path encodes UTF-8', () async {
    final folder = await folders.createFolder(name: 'S01');
    final doc = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'web.srt',
      bytes: _srtBytes('web'),
    );
    final loaded = await documents.loadBytes(doc);
    expect(utf8.decode(loaded), contains('web'));
  });

  test('loadBytes: native storageKey path reads store', () async {
    final keyStore = MemoryDocumentContentStore(storeAsContent: false);
    final keyDocs = DocumentRepository(db, contentStore: keyStore);
    final folder = await folders.createFolder(name: 'S01');
    final bytes = _srtBytes('native');
    final doc = await keyDocs.importIntoFolder(
      folderId: folder.id,
      fileName: 'native.srt',
      bytes: bytes,
    );
    expect(doc.storageKey, isNotNull);
    expect(doc.content, isNull);
    final loaded = await keyDocs.loadBytes(doc);
    expect(loaded, bytes);
  });

  test('LD-12: Hidden translation not listed', () async {
    final folder = await folders.createFolder(name: 'S01');
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original'),
    );
    final translation = await documents.attachTranslation(
      originalDocumentId: original.id,
      fileName: 'ru.srt',
      bytes: _srtBytes('перевод'),
    );
    final listed = await documents.listInFolder(folder.id);
    expect(listed.map((d) => d.id), [original.id]);
    expect(listed.map((d) => d.id), isNot(contains(translation.id)));
    expect(await documents.getById(translation.id), isNotNull);
  });

  test('LD-13: Persist translation linked to original', () async {
    final folder = await folders.createFolder(name: 'S01');
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original'),
    );
    final translationBytes = _srtBytes('перевод');
    final translation = await documents.attachTranslation(
      originalDocumentId: original.id,
      fileName: 'ru.srt',
      bytes: translationBytes,
    );
    expect(translation.folderId, folder.id);
    expect(translation.title, 'ru');
    expect(translation.format, 'srt');

    final reloadedOriginal = await documents.getById(original.id);
    expect(reloadedOriginal!.translationDocumentId, translation.id);

    final linked = await documents.loadLinkedTranslation(reloadedOriginal);
    expect(linked, isNotNull);
    expect(linked!.id, translation.id);
    final loaded = await documents.loadBytes(linked);
    expect(utf8.decode(loaded), contains('перевод'));
  });

  test('LD-14: Delete translation unlinks and removes', () async {
    final folder = await folders.createFolder(name: 'S01');
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original'),
    );
    final translation = await documents.attachTranslation(
      originalDocumentId: original.id,
      fileName: 'ru.srt',
      bytes: _srtBytes('перевод'),
    );
    final translationStorageKey = translation.storageKey;

    await documents.detachAndDeleteTranslation(original.id);

    final reloadedOriginal = await documents.getById(original.id);
    expect(reloadedOriginal, isNotNull);
    expect(reloadedOriginal!.translationDocumentId, isNull);
    expect(await documents.getById(translation.id), isNull);

    final listed = await documents.listInFolder(folder.id);
    expect(listed.map((d) => d.id), [original.id]);

    if (translationStorageKey != null) {
      expect(store.files.containsKey(translationStorageKey), isFalse);
    }
  });

  test('LD-15: Delete original cascades translation', () async {
    final folder = await folders.createFolder(name: 'S01');
    final keep = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'keep.srt',
      bytes: _srtBytes('keep'),
    );
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original'),
    );
    final translation = await documents.attachTranslation(
      originalDocumentId: original.id,
      fileName: 'ru.srt',
      bytes: _srtBytes('перевод'),
    );

    await documents.deleteDocument(original.id);

    expect(await documents.getById(original.id), isNull);
    expect(await documents.getById(translation.id), isNull);
    final listed = await documents.listInFolder(folder.id);
    expect(listed.map((d) => d.id), [keep.id]);
  });

  test('LD-17: Persist and load reading anchor for original', () async {
    final folder = await folders.createFolder(name: 'S01');
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original'),
    );

    expect(await documents.loadReadingAnchor(original.id), isNull);

    await documents.saveReadingAnchor(
      documentId: original.id,
      startMs: 4500,
      alignment: 0.25,
    );

    final loaded = await documents.loadReadingAnchor(original.id);
    expect(loaded, isNotNull);
    expect(loaded!.startMs, 4500);
    expect(loaded.alignment, closeTo(0.25, 1e-9));

    final reloaded = await documents.getById(original.id);
    expect(reloaded!.lastReadStartMs, 4500);
    expect(reloaded.lastReadAlignment, closeTo(0.25, 1e-9));
  });

  test('LD-20: Persist video durable link and frame cache', () async {
    final folder = await folders.createFolder(name: 'S01');
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original'),
    );

    expect(await documents.getVideoAttachment(original.id), isNull);

    await documents.attachVideo(
      documentId: original.id,
      videoUri: 'file:///videos/ep1.mp4',
      sandboxPath: '/tmp/sandbox/ep1.mp4',
      durationSec: 120,
      lastFramePage: 2,
    );

    final jpeg = Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9, 0x01]);
    await documents.putFrameCache(
      documentId: original.id,
      second: 0,
      jpegBytes: jpeg,
    );
    await documents.putFrameCache(
      documentId: original.id,
      second: 3,
      jpegBytes: Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9, 0x03]),
    );

    final attachment = await documents.getVideoAttachment(original.id);
    expect(attachment, isNotNull);
    expect(attachment!.videoUri, 'file:///videos/ep1.mp4');
    expect(attachment.sandboxPath, '/tmp/sandbox/ep1.mp4');
    expect(attachment.durationSec, 120);
    expect(attachment.lastFramePage, 2);

    expect(
      await documents.getFrameCache(documentId: original.id, second: 0),
      jpeg,
    );
    expect(
      await documents.getFrameCache(documentId: original.id, second: 3),
      Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9, 0x03]),
    );
    expect(
      await documents.getFrameCache(documentId: original.id, second: 1),
      isNull,
    );
  });

  test('LD-21: Remove video clears attachment and frame cache', () async {
    final folder = await folders.createFolder(name: 'S01');
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original'),
    );
    await documents.attachVideo(
      documentId: original.id,
      videoUri: 'file:///videos/ep1.mp4',
      durationSec: 30,
    );
    await documents.putFrameCache(
      documentId: original.id,
      second: 0,
      jpegBytes: Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]),
    );

    await documents.detachVideo(original.id);

    expect(await documents.getVideoAttachment(original.id), isNull);
    expect(
      await documents.getFrameCache(documentId: original.id, second: 0),
      isNull,
    );
    expect(await documents.getById(original.id), isNotNull);
    final listed = await documents.listInFolder(folder.id);
    expect(listed.map((d) => d.id), [original.id]);
  });

  test('LD-18: Delete original cascades video attachment', () async {
    final folder = await folders.createFolder(name: 'S01');
    final keep = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'keep.srt',
      bytes: _srtBytes('keep'),
    );
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original'),
    );
    await documents.attachVideo(
      documentId: original.id,
      videoUri: 'file:///videos/ep1.mp4',
      durationSec: 60,
    );
    await documents.putFrameCache(
      documentId: original.id,
      second: 5,
      jpegBytes: Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9, 0x05]),
    );

    await documents.deleteDocument(original.id);

    expect(await documents.getById(original.id), isNull);
    expect(await documents.getVideoAttachment(original.id), isNull);
    expect(
      await documents.getFrameCache(documentId: original.id, second: 5),
      isNull,
    );
    final leftoverFrames = await db.select(db.documentVideoFrames).get();
    expect(leftoverFrames, isEmpty);
    final listed = await documents.listInFolder(folder.id);
    expect(listed.map((d) => d.id), [keep.id]);
  });

  test('LD-22: Dead video link keeps cached frames and allows re-pick',
      () async {
    final folder = await folders.createFolder(name: 'S01');
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original'),
    );
    await documents.attachVideo(
      documentId: original.id,
      videoUri: 'file:///gone/missing.mp4',
      durationSec: 90,
    );
    final cached = Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9, 0x0A]);
    await documents.putFrameCache(
      documentId: original.id,
      second: 0,
      jpegBytes: cached,
    );

    // Dead link: meta still returned; repository does not wipe cache.
    final dead = await documents.getVideoAttachment(original.id);
    expect(dead, isNotNull);
    expect(dead!.videoUri, 'file:///gone/missing.mp4');
    expect(
      await documents.getFrameCache(documentId: original.id, second: 0),
      cached,
    );

    // Re-pick restores a usable link without wiping prior JPEG (LD-22).
    await documents.attachVideo(
      documentId: original.id,
      videoUri: 'file:///videos/repick.mp4',
      sandboxPath: '/tmp/sandbox/repick.mp4',
      durationSec: 90,
      clearFrameCache: false,
    );
    expect(
      await documents.getFrameCache(documentId: original.id, second: 0),
      cached,
    );
    final newJpeg = Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9, 0x0B]);
    await documents.putFrameCache(
      documentId: original.id,
      second: 6,
      jpegBytes: newJpeg,
    );
    expect(
      await documents.getFrameCache(documentId: original.id, second: 6),
      newJpeg,
    );
    final repicked = await documents.getVideoAttachment(original.id);
    expect(repicked!.videoUri, 'file:///videos/repick.mp4');
  });

  test('LD-23: Replace video clears previous frame cache', () async {
    final folder = await folders.createFolder(name: 'S01');
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original'),
    );
    final translation = await documents.attachTranslation(
      originalDocumentId: original.id,
      fileName: 'ru.srt',
      bytes: _srtBytes('перевод'),
    );

    await documents.attachVideo(
      documentId: original.id,
      videoUri: 'file:///videos/old.mp4',
      durationSec: 40,
    );
    await documents.putFrameCache(
      documentId: original.id,
      second: 1,
      jpegBytes: Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9, 0x11]),
    );
    await documents.putFrameCache(
      documentId: original.id,
      second: 2,
      jpegBytes: Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9, 0x22]),
    );

    await documents.attachVideo(
      documentId: original.id,
      videoUri: 'file:///videos/new.mp4',
      sandboxPath: '/tmp/sandbox/new.mp4',
      durationSec: 55,
      lastFramePage: 1,
    );

    final attachment = await documents.getVideoAttachment(original.id);
    expect(attachment!.videoUri, 'file:///videos/new.mp4');
    expect(attachment.sandboxPath, '/tmp/sandbox/new.mp4');
    expect(attachment.durationSec, 55);
    expect(
      await documents.getFrameCache(documentId: original.id, second: 1),
      isNull,
    );
    expect(
      await documents.getFrameCache(documentId: original.id, second: 2),
      isNull,
    );
    expect(await documents.getById(original.id), isNotNull);
    expect(await documents.getById(translation.id), isNotNull);
    final reloaded = await documents.getById(original.id);
    expect(reloaded!.translationDocumentId, translation.id);
  });

  test('LD-20b: attachVideo stores durable media bytes for reopen', () async {
    final folder = await folders.createFolder(name: 'Videos');
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'ep.srt',
      bytes: _srtBytes('hello'),
    );
    final media = Uint8List.fromList(List<int>.generate(64, (i) => i));

    await documents.attachVideo(
      documentId: original.id,
      videoUri: 'blob:dead-after-reload',
      sandboxPath: 'drift-media',
      durationSec: 12,
      mediaBytes: media,
      mediaFileName: 'clip.mp4',
    );

    final attachment = await documents.getVideoAttachment(original.id);
    expect(attachment!.hasStoredMedia, isTrue);
    expect(attachment.mediaFileName, 'clip.mp4');
    expect(attachment.sandboxPath, 'drift-media');

    final stored = await documents.getVideoMedia(original.id);
    expect(stored, isNotNull);
    expect(stored!.fileName, 'clip.mp4');
    expect(stored.bytes, media);

    await documents.detachVideo(original.id);
    expect(await documents.getVideoMedia(original.id), isNull);
    expect(await documents.getVideoAttachment(original.id), isNull);
  });

  test('LD-03 / LD-24: accept .epub; reject still lists epub in message', () async {
    expect(formatFromFileName('book.epub'), documentFormatEpub);
    expect(formatFromFileName('notes.txt'), isNull);

    final folder = await folders.createFolder(name: 'Books');
    final doc = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'novel.epub',
      bytes: _epubLikeBytes(),
    );
    expect(doc.format, documentFormatEpub);
    expect(doc.title, 'novel');
    final listed = await documents.listInFolder(folder.id);
    expect(listed.map((d) => d.format), contains(documentFormatEpub));

    try {
      await documents.importIntoFolder(
        folderId: folder.id,
        fileName: 'notes.txt',
        bytes: Uint8List.fromList(utf8.encode('nope')),
      );
      fail('expected LibraryValidationException');
    } on LibraryValidationException catch (e) {
      expect(e.message, contains('.epub'));
      expect(e.message, contains('Unsupported'));
    }
  });

  test('LD-27: Web EPUB bytes roundtrip binary-safe (base64 content)', () async {
    final webStore = MemoryDocumentContentStore(storeAsContent: true);
    final webDocs = DocumentRepository(db, contentStore: webStore);
    final folder = await folders.createFolder(name: 'WebBooks');
    final bytes = _epubLikeBytes();

    final doc = await webDocs.importIntoFolder(
      folderId: folder.id,
      fileName: 'bin.epub',
      bytes: bytes,
    );
    expect(doc.content, isNotNull);
    expect(doc.storageKey, isNull);
    // Must be base64, not a UTF-8-lossy decode of ZIP bytes.
    expect(doc.content, base64Encode(bytes));

    final loaded = await webDocs.loadBytes(doc);
    expect(loaded, bytes);

    // Regression: subtitle Web path still UTF-8 text, not base64.
    final srt = await webDocs.importIntoFolder(
      folderId: folder.id,
      fileName: 'sub.srt',
      bytes: _srtBytes('web-utf8'),
    );
    expect(srt.content, contains('web-utf8'));
    expect(utf8.decode(await webDocs.loadBytes(srt)), contains('web-utf8'));
  });

  test('LD-27b: native sandbox EPUB roundtrip without UTF-8', () async {
    final keyStore = MemoryDocumentContentStore(storeAsContent: false);
    final keyDocs = DocumentRepository(db, contentStore: keyStore);
    final folder = await folders.createFolder(name: 'NativeBooks');
    final bytes = _epubLikeBytes();
    final doc = await keyDocs.importIntoFolder(
      folderId: folder.id,
      fileName: 'native.epub',
      bytes: bytes,
    );
    expect(doc.storageKey, isNotNull);
    expect(doc.content, isNull);
    expect(await keyDocs.loadBytes(doc), bytes);
  });

  test('LD-26: Reject non-EPUB translation for EPUB original', () async {
    final folder = await folders.createFolder(name: 'Books');
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'novel.epub',
      bytes: _epubLikeBytes(),
    );

    expect(
      () => documents.attachTranslation(
        originalDocumentId: original.id,
        fileName: 'ru.srt',
        bytes: _srtBytes('перевод'),
      ),
      throwsA(
        isA<LibraryValidationException>().having(
          (e) => e.message,
          'message',
          contains('EPUB'),
        ),
      ),
    );

    final translation = await documents.attachTranslation(
      originalDocumentId: original.id,
      fileName: 'ru.epub',
      bytes: _epubLikeBytes(),
    );
    expect(translation.format, documentFormatEpub);
    final reloaded = await documents.getById(original.id);
    expect(reloaded!.translationDocumentId, translation.id);
  });

  test('LD-26b: Reject EPUB translation for subtitle original', () async {
    final folder = await folders.createFolder(name: 'S01');
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original'),
    );
    expect(
      () => documents.attachTranslation(
        originalDocumentId: original.id,
        fileName: 'ru.epub',
        bytes: _epubLikeBytes(),
      ),
      throwsA(isA<LibraryValidationException>()),
    );
  });

  test('LD-28: EPUB reading anchor stores chapter index', () async {
    final folder = await folders.createFolder(name: 'Books');
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'novel.epub',
      bytes: _epubLikeBytes(),
    );

    await documents.saveReadingAnchor(
      documentId: original.id,
      startMs: 3, // chapter index
      alignment: 0.5,
    );
    final loaded = await documents.loadReadingAnchor(original.id);
    expect(loaded, isNotNull);
    expect(loaded!.startMs, 3);
    expect(loaded.alignment, closeTo(0.5, 1e-9));

    final row = await documents.getById(original.id);
    expect(row!.format, documentFormatEpub);
    expect(row.lastReadStartMs, 3);
  });
}
