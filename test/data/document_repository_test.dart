import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/data/library/library_exceptions.dart';

import '../support/test_database.dart';

Uint8List _srtBytes([String text = 'Hi']) =>
    Uint8List.fromList(utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n$text\n'));

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
}
