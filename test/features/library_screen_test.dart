import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/data/library/document_format.dart';
import 'package:my_translator_app/data/library/parse_error_messages.dart';
import 'package:my_translator_app/features/reader/tokenize_cues_fn.dart';
import 'package:my_translator_app/features/upload/library_screen.dart';
import 'package:my_translator_app/src/rust/api/epub.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';
import 'package:my_translator_app/src/rust/api/tokenize.dart';

import '../support/test_database.dart';

Future<List<CueTokensDto>> _emptyTokenize(List<String> texts) async => [
      for (var i = 0; i < texts.length; i++)
        CueTokensDto(cueIndex: i, tokens: const []),
    ];

Future<List<CueTokensDto>> _identityMark({
  required List<CueTokensDto> cues,
  required List<String> vocabLemmas,
}) async =>
    cues;

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

ParsedEpub _okEpub({
  String title = 'Chapter 1',
  String paragraph = 'Once upon a time',
}) =>
    ParsedEpub(
      chapters: [
        EpubChapterDto(
          index: 0,
          title: title,
          paragraphs: [paragraph],
        ),
        EpubChapterDto(
          index: 1,
          title: 'Chapter 2',
          paragraphs: ['Second chapter body'],
        ),
      ],
    );

Uint8List _epubLikeBytes() => Uint8List.fromList([
      0x50, 0x4B, 0x03, 0x04, 0x00, 0xFF, 0xFE, 0x80,
    ]);

void main() {
  late final db = createTestDatabase();
  late MemoryDocumentContentStore store;
  late FolderRepository folders;
  late DocumentRepository documents;
  late DictionaryRepository dictionary;

  setUp(() {
    store = MemoryDocumentContentStore();
    folders = FolderRepository(db, contentStore: store);
    documents = DocumentRepository(db, contentStore: store);
    dictionary = DictionaryRepository(db);
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
    ParseEpubFn? parseEpub,
    TokenizeCuesFn? tokenizeCues,
    MarkVocabTokensFn? markVocabTokens,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          folderRepository: folders,
          documentRepository: documents,
          dictionaryRepository: dictionary,
          filePicker: filePicker,
          parseSubtitles: parseSubtitles,
          parseEpub: parseEpub,
          tokenizeCues: tokenizeCues ?? _emptyTokenize,
          markVocabTokens: markVocabTokens ?? _identityMark,
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
          dictionaryRepository: dictionary,
          tokenizeCues: _emptyTokenize,
          markVocabTokens: _identityMark,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('libraryFolder_${parent.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('libraryEmpty')), findsOneWidget);
    expect(find.byKey(const Key('libraryListError')), findsNothing);
    expect(find.text('This folder is empty'), findsOneWidget);
    // Empty folder (not root): Create folder in body; Import only via AppBar.
    expect(find.byKey(const Key('libraryEmptyCreateFolder')), findsOneWidget);
    expect(find.byKey(const Key('libraryEmptyImport')), findsNothing);
    expect(find.byKey(const Key('libraryImportButton')), findsOneWidget);
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

  testWidgets('LF-11: Empty root shows import and create folder', (tester) async {
    await pumpLibrary(tester);
    expect(find.byKey(const Key('libraryEmpty')), findsOneWidget);
    expect(find.byKey(const Key('libraryEmptyCreateFolder')), findsOneWidget);
    expect(find.byKey(const Key('libraryEmptyImport')), findsOneWidget);
    expect(find.byKey(const Key('libraryImportButton')), findsOneWidget);
    expect(find.byKey(const Key('libraryCreateFolderButton')), findsOneWidget);
  });

  testWidgets('LF-09: Root lists folders and documents together', (tester) async {
    final folder = await folders.createFolder(name: 'Сериалы');
    final doc = await documents.importIntoFolder(
      folderId: null,
      fileName: 'episode.srt',
      bytes: _srtBytes('episode'),
    );

    await pumpLibrary(tester);

    expect(find.byKey(const Key('libraryList')), findsOneWidget);
    expect(find.byKey(Key('libraryFolder_${folder.id}')), findsOneWidget);
    expect(find.byKey(Key('libraryDocument_${doc.id}')), findsOneWidget);
    expect(find.text('Сериалы'), findsOneWidget);
    expect(find.text('episode'), findsOneWidget);

    // Folders first, then documents (LF-09 order).
    final folderY = tester.getTopLeft(find.byKey(Key('libraryFolder_${folder.id}'))).dy;
    final docY = tester.getTopLeft(find.byKey(Key('libraryDocument_${doc.id}'))).dy;
    expect(folderY, lessThan(docY));
  });

  testWidgets('LD-02: Import at library root succeeds', (tester) async {
    await pumpLibrary(
      tester,
      filePicker: () async => PickedLibraryFile(
        fileName: 'root.srt',
        bytes: _srtBytes('root cue'),
      ),
    );
    expect(find.byKey(const Key('libraryImportButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('libraryImportButton')));
    await tester.pumpAndSettle();

    final listed = await documents.listVisible(folderId: null);
    expect(listed, hasLength(1));
    expect(listed.first.title, 'root');
    expect(listed.first.folderId, isNull);
    expect(find.byKey(Key('libraryDocument_${listed.first.id}')), findsOneWidget);
    expect(find.text('root'), findsOneWidget);
  });

  testWidgets('LD-30: Open root document opens Reader', (tester) async {
    final doc = await documents.importIntoFolder(
      folderId: null,
      fileName: 'root.srt',
      bytes: _srtBytes('root cue'),
    );
    await pumpLibrary(
      tester,
      parseSubtitles: ({required bytes, formatHint}) async =>
          _okParsed('root cue'),
    );
    await tester.tap(find.byKey(Key('libraryDocument_${doc.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerScreen')), findsOneWidget);
    expect(find.text('root cue'), findsOneWidget);
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

  testWidgets('LD-12: Hidden translation not listed in folder UI', (tester) async {
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

    await pumpLibrary(tester);
    await tester.tap(find.byKey(Key('libraryFolder_${folder.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('libraryDocument_${original.id}')), findsOneWidget);
    expect(find.text('original'), findsOneWidget);
    expect(find.byKey(Key('libraryDocument_${translation.id}')), findsNothing);
    expect(find.text('ru'), findsNothing);
  });

  testWidgets('LD-16 / RS-09: Open original loads linked translation for Reader', (
    tester,
  ) async {
    final folder = await folders.createFolder(name: 'S01');
    final original = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original cue'),
    );
    await documents.attachTranslation(
      originalDocumentId: original.id,
      fileName: 'ru.srt',
      bytes: _srtBytes('translation cue'),
    );

    await pumpLibrary(
      tester,
      parseSubtitles: ({required bytes, formatHint}) async {
        final text = utf8.decode(bytes);
        final cueText = text.contains('translation cue')
            ? 'translation cue'
            : 'original cue';
        return ParsedSubtitles(
          format: 'srt',
          cues: [
            CueDto(
              index: 0,
              startMs: BigInt.from(1000),
              endMs: BigInt.from(2000),
              textLines: [cueText],
            ),
          ],
        );
      },
    );
    await tester.tap(find.byKey(Key('libraryFolder_${folder.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('libraryDocument_${original.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerScreen')), findsOneWidget);
    expect(find.text('original cue'), findsOneWidget);

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerTranslationCueList')), findsOneWidget);
    expect(find.text('translation cue'), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationEmpty')), findsNothing);
    expect(find.byKey(const Key('readerTranslationLoad')), findsNothing);
  });

  testWidgets('LD-24: Import valid EPUB file into folder', (tester) async {
    final folder = await folders.createFolder(name: 'S01');
    await pumpLibrary(
      tester,
      filePicker: () async => PickedLibraryFile(
        fileName: 'novel.epub',
        bytes: _epubLikeBytes(),
      ),
    );
    await tester.tap(find.byKey(Key('libraryFolder_${folder.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('libraryImportButton')));
    await tester.pumpAndSettle();

    final listed = await documents.listInFolder(folder.id);
    expect(listed, hasLength(1));
    expect(listed.first.format, documentFormatEpub);
    expect(listed.first.title, 'novel');
    expect(find.text('novel'), findsOneWidget);
    expect(find.text(documentFormatEpub), findsOneWidget);
  });

  testWidgets('LD-25: Open EPUB opens Reader in book mode', (tester) async {
    final folder = await folders.createFolder(name: 'S01');
    final doc = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'novel.epub',
      bytes: _epubLikeBytes(),
    );
    await pumpLibrary(
      tester,
      parseEpub: ({required bytes}) async => _okEpub(),
      parseSubtitles: ({required bytes, formatHint}) async {
        fail('subtitle parse must not run for EPUB open');
      },
    );
    await tester.tap(find.byKey(Key('libraryFolder_${folder.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('libraryDocument_${doc.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerScreen')), findsOneWidget);
    expect(find.byKey(const Key('readerBookPane')), findsOneWidget);
    expect(find.text('Once upon a time'), findsOneWidget);
    expect(find.byKey(const Key('readerLoadVideo')), findsNothing);
    expect(find.byKey(const Key('readerCueList')), findsNothing);
  });

  testWidgets('LD-11: Failed EPUB open stays in Library with error', (
    tester,
  ) async {
    final folder = await folders.createFolder(name: 'S01');
    final doc = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'bad.epub',
      bytes: _epubLikeBytes(),
    );
    await pumpLibrary(
      tester,
      parseEpub: ({required bytes}) async {
        throw EpubParseErrorKind.empty;
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
      find.text(messageForEpubParseError(EpubParseErrorKind.empty)),
      findsOneWidget,
    );
  });

  testWidgets('LD-28: EPUB open restores chapter index from reading anchor', (
    tester,
  ) async {
    final folder = await folders.createFolder(name: 'S01');
    final doc = await documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'novel.epub',
      bytes: _epubLikeBytes(),
    );
    await documents.saveReadingAnchor(documentId: doc.id, startMs: 1);
    await pumpLibrary(
      tester,
      parseEpub: ({required bytes}) async => _okEpub(),
    );
    await tester.tap(find.byKey(Key('libraryFolder_${folder.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('libraryDocument_${doc.id}')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerBookPane')), findsOneWidget);
    expect(find.text('Second chapter body'), findsOneWidget);
    // Chapter pager mirrors VideoFramePages chrome: `n / N`.
    expect(find.text('2 / 2'), findsOneWidget);
  });
}
