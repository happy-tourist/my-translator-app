import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:path/path.dart' as p;

import '../support/test_database.dart';

Uint8List _srtBytes([String text = 'Hi']) =>
    Uint8List.fromList(utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n$text\n'));

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tr_persist_');
    dbFile = File(p.join(tempDir.path, 'translation_reader_test.sqlite'));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('LD-06: Documents survive close/reopen of the same Drift DB', () async {
    final store = MemoryDocumentContentStore(storeAsContent: true);

    final db1 = createFileTestDatabase(dbFile);
    final folders1 = FolderRepository(db1, contentStore: store);
    final documents1 = DocumentRepository(db1, contentStore: store);
    final folder = await folders1.createFolder(name: 'Season 1');
    final imported = await documents1.importIntoFolder(
      folderId: folder.id,
      fileName: 'episode1.srt',
      bytes: _srtBytes('Survive'),
    );
    expect(imported.title, 'episode1');
    await db1.close();

    final db2 = createFileTestDatabase(dbFile);
    final documents2 = DocumentRepository(
      db2,
      contentStore: MemoryDocumentContentStore(storeAsContent: true),
    );
    final listed = await documents2.listInFolder(folder.id);
    expect(listed, hasLength(1));
    expect(listed.single.title, 'episode1');
    expect(listed.single.format, 'srt');
    expect(listed.single.folderId, folder.id);
    expect(listed.single.content, contains('Survive'));
    await db2.close();
  });

  test('DE-08: Dictionary entries survive close/reopen of the same Drift DB',
      () async {
    final db1 = createFileTestDatabase(dbFile);
    final dictionary1 = DictionaryRepository(db1);
    await dictionary1.add(
      lemma: 'Run',
      surfaceKey: 'Run',
      translation: 'бежать',
      context: 'He was running',
    );
    await db1.close();

    final db2 = createFileTestDatabase(dbFile);
    final dictionary2 = DictionaryRepository(db2);
    final list = await dictionary2.list();
    expect(list, hasLength(1));
    expect(list.single.lemma, 'run');
    expect(list.single.translation, 'бежать');
    expect(list.single.context, 'He was running');
    final hit = await dictionary2.lookup('RUN');
    expect(hit, isNotNull);
    expect(hit!.id, list.single.id);
    await db2.close();
  });

  test('LD-20: Video attachment and frame cache survive close/reopen', () async {
    final store = MemoryDocumentContentStore(storeAsContent: true);
    final jpeg = Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9, 0x42]);

    final db1 = createFileTestDatabase(dbFile);
    final folders1 = FolderRepository(db1, contentStore: store);
    final documents1 = DocumentRepository(db1, contentStore: store);
    final folder = await folders1.createFolder(name: 'Season 1');
    final original = await documents1.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original'),
    );
    await documents1.attachVideo(
      documentId: original.id,
      videoUri: 'file:///videos/ep1.mp4',
      sandboxPath: '/tmp/sandbox/ep1.mp4',
      durationSec: 45,
      lastFramePage: 3,
    );
    await documents1.putFrameCache(
      documentId: original.id,
      second: 2,
      jpegBytes: jpeg,
    );
    final docId = original.id;
    final folderId = folder.id;
    await db1.close();

    final db2 = createFileTestDatabase(dbFile);
    final documents2 = DocumentRepository(
      db2,
      contentStore: MemoryDocumentContentStore(storeAsContent: true),
    );
    final attachment = await documents2.getVideoAttachment(docId);
    expect(attachment, isNotNull);
    expect(attachment!.videoUri, 'file:///videos/ep1.mp4');
    expect(attachment.sandboxPath, '/tmp/sandbox/ep1.mp4');
    expect(attachment.durationSec, 45);
    expect(attachment.lastFramePage, 3);
    expect(
      await documents2.getFrameCache(documentId: docId, second: 2),
      jpeg,
    );
    final listed = await documents2.listInFolder(folderId);
    expect(listed, hasLength(1));
    await db2.close();
  });
}
