import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/data/library/library_exceptions.dart';

import '../support/test_database.dart';

void main() {
  late final db = createTestDatabase();
  late final store = MemoryDocumentContentStore();
  late final folders = FolderRepository(db, contentStore: store);
  late final documents = DocumentRepository(db, contentStore: store);

  tearDownAll(() async {
    await db.close();
  });

  tearDown(() async {
    await db.delete(db.documents).go();
    await db.delete(db.folders).go();
    store.files.clear();
  });

  test('LF-01: Create root folder', () async {
    final folder = await folders.createFolder(name: 'Сериалы');
    final root = await folders.listChildren(null);
    expect(root.map((f) => f.name), contains('Сериалы'));
    expect(folder.parentId, isNull);
  });

  test('LF-02: Create nested folder', () async {
    final parent = await folders.createFolder(name: 'Сериалы');
    final child = await folders.createFolder(name: 'S01', parentId: parent.id);
    expect(child.parentId, parent.id);
    final underParent = await folders.listChildren(parent.id);
    expect(underParent.map((f) => f.name), contains('S01'));
    final root = await folders.listChildren(null);
    expect(root.map((f) => f.name), isNot(contains('S01')));
  });

  test('LF-03: Reject empty name', () async {
    expect(
      () => folders.createFolder(name: '   '),
      throwsA(isA<LibraryValidationException>()),
    );
    expect(await folders.listChildren(null), isEmpty);
  });

  test('LF-04: List children of folder', () async {
    final parent = await folders.createFolder(name: 'Сериалы');
    await folders.createFolder(name: 'S01', parentId: parent.id);
    await folders.createFolder(name: 'S02', parentId: parent.id);
    final children = await folders.listChildren(parent.id);
    expect(children.map((f) => f.name).toList(), ['S01', 'S02']);
  });

  test('LF-05: Empty folder lists nothing', () async {
    final parent = await folders.createFolder(name: 'Empty');
    expect(await folders.listChildren(parent.id), isEmpty);
    expect(await documents.listInFolder(parent.id), isEmpty);
  });

  test('LF-06: Delete folder with nested content', () async {
    final parent = await folders.createFolder(name: 'Сериалы');
    final nested = await folders.createFolder(name: 'S01', parentId: parent.id);
    await documents.importIntoFolder(
      folderId: nested.id,
      fileName: 'episode1.srt',
      bytes: Uint8List.fromList(utf8.encode('1\n00:00:01,000 --> 00:00:02,000\nHi\n')),
    );
    await folders.deleteFolderCascade(parent.id);

    expect(await folders.listChildren(null), isEmpty);
    expect(await folders.getById(parent.id), isNull);
    expect(await folders.getById(nested.id), isNull);
    expect(await documents.listInFolder(nested.id), isEmpty);
  });
}
