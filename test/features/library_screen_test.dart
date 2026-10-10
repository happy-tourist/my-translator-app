import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/features/upload/library_screen.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';

import '../support/test_database.dart';

Uint8List _srtBytes([String text = 'Hi']) =>
    Uint8List.fromList(utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n$text\n'));

ParsedSubtitles _okParsed([String text = 'Hi']) => ParsedSubtitles(
  format: 'srt',
  cues: [
    CueDto(
      index: 0,
      startMs: BigInt.from(1000),
      endMs: BigInt.from(2000),
      textLines: [text],
    ),
  ],
);

void main() {
  late final db = createTestDatabase();
  late MemoryDocumentContentStore store;
  late FolderRepository folders;
  late DocumentRepository documents;

  setUp(() {
    store = MemoryDocumentContentStore();
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

  Future<void> pumpLibrary(
    WidgetTester tester, {
    LibraryFilePicker? filePicker,
    ParseSubtitlesFn? parseSubtitles,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          folderRepository: folders,
          documentRepository: documents,
          filePicker: filePicker,
          parseSubtitles: parseSubtitles,
        ),
      ),
    );
    // LF-08: loading then content/empty
    expect(find.byKey(const Key('libraryLoading')), findsOneWidget);
    await tester.pumpAndSettle();
  }

  testWidgets('LF-08: List loading then empty/content', (tester) async {
    await pumpLibrary(tester);
    expect(find.byKey(const Key('libraryLoading')), findsNothing);
    expect(find.byKey(const Key('libraryEmpty')), findsOneWidget);
  });

  testWidgets('LF-05: Empty folder shows empty UI without error', (tester) async {
    final parent = await folders.createFolder(name: 'Empty');
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          folderRepository: folders,
          documentRepository: documents,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('libraryFolder_${parent.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('libraryEmpty')), findsOneWidget);
    expect(find.byKey(const Key('libraryListError')), findsNothing);
    expect(find.text('This folder is empty'), findsOneWidget);
  });

  testWidgets('LF-03: Reject empty folder name in UI', (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.byKey(const Key('libraryCreateFolderButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('libraryFolderNameField')), '   ');
    await tester.tap(find.byKey(const Key('libraryCreateFolderConfirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('must not be empty'), findsOneWidget);
    expect(await folders.listChildren(null), isEmpty);
  });

  testWidgets('LF-07: Cancel cascade delete keeps data', (tester) async {
    final parent = await folders.createFolder(name: 'Сериалы');
    final nested = await folders.createFolder(name: 'S01', parentId: parent.id);
    await documents.importIntoFolder(
      folderId: nested.id,
      fileName: 'ep.srt',
      bytes: _srtBytes(),
    );

    await pumpLibrary(tester);
    await tester.tap(find.byKey(Key('libraryDeleteFolder_${parent.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('libraryCascadeDeleteDialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('libraryCascadeDeleteCancel')));
    await tester.pumpAndSettle();

    expect(await folders.getById(parent.id), isNotNull);
    expect(await folders.getById(nested.id), isNotNull);
    expect(await documents.listInFolder(nested.id), hasLength(1));
    expect(find.text('Сериалы'), findsOneWidget);
  });

  testWidgets('LD-02: Import CTA absent at library root', (tester) async {
    await pumpLibrary(tester);
    expect(find.byKey(const Key('libraryImportButton')), findsNothing);
  });

  testWidgets('LD-03: Unsupported type shows UI message', (tester) async {
    final folder = await folders.createFolder(name: 'S01');
    await pumpLibrary(
      tester,
      filePicker: () async => PickedLibraryFile(
        fileName: 'notes.txt',
        bytes: Uint8List.fromList(utf8.encode('nope')),
      ),
    );
    await tester.tap(find.byKey(Key('libraryFolder_${folder.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('libraryImportButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('libraryImportButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unsupported'), findsOneWidget);
    expect(await documents.listInFolder(folder.id), isEmpty);
  });

  testWidgets('LD-04: List documents after import', (tester) async {
    final folder = await folders.createFolder(name: 'S01');
    await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'a.srt',
      bytes: _srtBytes('a'),
    );
    await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'b.srt',
      bytes: _srtBytes('b'),
    );
    await pumpLibrary(tester);
    await tester.tap(find.byKey(Key('libraryFolder_${folder.id}')));
    await tester.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('LD-10: Open document opens Reader after successful parse', (
    tester,
  ) async {
    final folder = await folders.createFolder(name: 'S01');
    final doc = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'ep.srt',
      bytes: _srtBytes('Hello cue'),
    );
    await pumpLibrary(
      tester,
      parseSubtitles: ({required bytes, formatHint}) async =>
          _okParsed('Hello cue'),
    );
    await tester.tap(find.byKey(Key('libraryFolder_${folder.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('libraryDocument_${doc.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerScreen')), findsOneWidget);
    expect(find.text('Hello cue'), findsOneWidget);
    expect(find.text('00:00:01,000 → 00:00:02,000'), findsOneWidget);
    expect(find.text('Reader later'), findsNothing);
  });

  testWidgets('LD-11 / RC-05: Failed open stays in Library with error', (
    tester,
  ) async {
    final folder = await folders.createFolder(name: 'S01');
    final doc = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'bad.srt',
      bytes: _srtBytes(),
    );
    await pumpLibrary(
      tester,
      parseSubtitles: ({required bytes, formatHint}) async {
        throw ParseErrorKind.empty;
      },
    );
    await tester.tap(find.byKey(Key('libraryFolder_${folder.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('libraryDocument_${doc.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerScreen')), findsNothing);
    expect(find.byKey(const Key('libraryList')), findsOneWidget);
    expect(find.byKey(const Key('libraryErrorSnack')), findsOneWidget);
    expect(
      find.text('No subtitle cues found in this file'),
      findsOneWidget,
    );
  });
}
