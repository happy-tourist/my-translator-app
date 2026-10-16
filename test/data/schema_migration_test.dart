import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../support/test_database.dart';

void main() {
  test('schemaVersion is 7', () {
    final db = createTestDatabase();
    addTearDown(db.close);
    expect(db.schemaVersion, 7);
  });

  test('schema 7: clean DB creates and accepts root documents', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    expect(db.schemaVersion, 7);

    final store = MemoryDocumentContentStore(storeAsContent: true);
    final documents = DocumentRepository(db, contentStore: store);
    final doc = await documents.importIntoFolder(
      folderId: null,
      fileName: 'root.srt',
      bytes: Uint8List.fromList('1\n00:00:01,000 --> 00:00:02,000\nHi\n'.codeUnits),
    );
    expect(doc.folderId, isNull);
    final listed = await documents.listVisible(folderId: null);
    expect(listed.map((d) => d.id), [doc.id]);
  });

  test('schema 7: upgrade 6→7 keeps document rows', () async {
    final tempDir = await Directory.systemTemp.createTemp('tr_schema7_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final dbFile = File(p.join(tempDir.path, 'v6.sqlite'));

    final raw = sqlite3.sqlite3.open(dbFile.path);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    raw.execute('''
      CREATE TABLE folders (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER NULL REFERENCES folders (id),
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    raw.execute('''
      CREATE TABLE documents (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        folder_id INTEGER NOT NULL REFERENCES folders (id),
        title TEXT NOT NULL,
        format TEXT NOT NULL,
        storage_key TEXT NULL,
        content TEXT NULL,
        translation_document_id INTEGER NULL REFERENCES documents (id),
        last_read_start_ms INTEGER NULL,
        last_read_alignment REAL NULL,
        video_uri TEXT NULL,
        video_sandbox_path TEXT NULL,
        video_duration_sec INTEGER NULL,
        video_last_frame_page INTEGER NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    raw.execute(
      'INSERT INTO folders (id, parent_id, name, created_at, updated_at) '
      "VALUES (1, NULL, 'S01', $now, $now);",
    );
    raw.execute(
      'INSERT INTO documents '
      '(id, folder_id, title, format, content, created_at, updated_at) '
      "VALUES (1, 1, 'episode1', 'srt', 'cue', $now, $now);",
    );
    raw.execute('PRAGMA user_version = 6;');
    raw.close();

    final db = createFileTestDatabase(dbFile);
    addTearDown(db.close);
    expect(db.schemaVersion, 7);

    final rows = await db.select(db.documents).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, 1);
    expect(rows.single.folderId, 1);
    expect(rows.single.title, 'episode1');
    expect(rows.single.content, 'cue');

    // After recreate, nullable folderId accepts root inserts.
    final store = MemoryDocumentContentStore(storeAsContent: true);
    final documents = DocumentRepository(db, contentStore: store);
    final root = await documents.importIntoFolder(
      folderId: null,
      fileName: 'root.srt',
      bytes: Uint8List.fromList('1\n00:00:01,000 --> 00:00:02,000\nHi\n'.codeUnits),
    );
    expect(root.folderId, isNull);
  });
}
