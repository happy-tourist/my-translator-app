import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/app/theme.dart';
import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_format.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/features/reader/reader_screen.dart';
import 'package:my_translator_app/features/reader/tokenize_cues_fn.dart';
import 'package:my_translator_app/src/rust/api/epub.dart';
import 'package:my_translator_app/src/rust/api/tokenize.dart';

import '../../support/test_database.dart';

List<EpubChapterDto> _sampleChapters() => [
      const EpubChapterDto(
        index: 0,
        title: 'Chapter One',
        paragraphs: [
          'Once upon a time there was a fox.',
          'The fox lived in the woods.',
        ],
      ),
      const EpubChapterDto(
        index: 1,
        title: 'Chapter Two',
        paragraphs: [
          'Later the fox met a rabbit.',
        ],
      ),
      const EpubChapterDto(
        index: 2,
        title: 'Chapter Three',
        paragraphs: [
          'Finally they became friends.',
        ],
      ),
    ];

/// Word-like tokens with char spans matching [text] (for fake TokenizeCuesFn).
List<TokenDto> _tokensFor(String text) {
  final tokens = <TokenDto>[];
  var index = 0;
  for (final match in RegExp(r"[\w']+", unicode: true).allMatches(text)) {
    final surface = match.group(0)!;
    tokens.add(
      TokenDto(
        surface: surface,
        charStart: match.start,
        charEnd: match.end,
        tokenIndex: index++,
        lemmaKey: surface.toLowerCase(),
        isInVocab: false,
      ),
    );
  }
  return tokens;
}

Future<List<CueTokensDto>> _tokenizeFromTexts(List<String> texts) async => [
      for (var i = 0; i < texts.length; i++)
        CueTokensDto(cueIndex: i, tokens: _tokensFor(texts[i])),
    ];

Future<List<CueTokensDto>> _fakeMarkVocabTokens({
  required List<CueTokensDto> cues,
  required List<String> vocabLemmas,
}) async {
  final singles = vocabLemmas
      .map(DictionaryRepository.normalizeSurface)
      .where((k) => k.isNotEmpty && !k.contains(RegExp(r'\s')))
      .toSet();
  return [
    for (final cue in cues)
      CueTokensDto(
        cueIndex: cue.cueIndex,
        tokens: [
          for (final t in cue.tokens)
            TokenDto(
              surface: t.surface,
              charStart: t.charStart,
              charEnd: t.charEnd,
              tokenIndex: t.tokenIndex,
              lemmaKey: t.lemmaKey,
              isInVocab: singles.contains(t.lemmaKey.toLowerCase()),
            ),
        ],
      ),
  ];
}

void main() {
  late final db = createTestDatabase();
  late MemoryDocumentContentStore store;
  late FolderRepository folders;
  late DocumentRepository documents;
  late DictionaryRepository dictionary;

  late List<EpubChapterDto> pumpChapters;
  late String pumpTitle;
  late int pumpOriginalDocumentId;
  ReadingAnchor? pumpInitialReadingAnchor;
  TokenizeCuesFn? pumpTokenize;
  MarkVocabTokensFn? pumpMark;

  setUp(() {
    store = MemoryDocumentContentStore();
    folders = FolderRepository(db, contentStore: store);
    documents = DocumentRepository(db, contentStore: store);
    dictionary = DictionaryRepository(db);
    pumpChapters = _sampleChapters();
    pumpTitle = 'sample.epub';
    pumpOriginalDocumentId = 1;
    pumpInitialReadingAnchor = null;
    pumpTokenize = _tokenizeFromTexts;
    pumpMark = _fakeMarkVocabTokens;
  });

  tearDown(() async {
    await db.delete(db.dictionaryEntries).go();
    await db.delete(db.documents).go();
    await db.delete(db.folders).go();
  });

  tearDownAll(() async {
    await db.close();
  });

  Future<void> pumpBookReader(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: ReaderScreen(
          title: pumpTitle,
          originalCues: const [],
          originalDocumentId: pumpOriginalDocumentId,
          documentRepository: documents,
          dictionaryRepository: dictionary,
          documentFormat: documentFormatEpub,
          originalChapters: pumpChapters,
          initialReadingAnchor: pumpInitialReadingAnchor,
          tokenizeCues: pumpTokenize,
          markVocabTokens: pumpMark,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Future<Document> seedEpubDoc() async {
    final folder = await folders.createFolder(name: 'Books');
    return documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'sample.epub',
      // Minimal zip-like bytes; content store does not parse EPUB.
      bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x00]),
    );
  }

  testWidgets('RC-01: Show paragraphs of current chapter', (tester) async {
    await pumpBookReader(tester);

    expect(find.byKey(const Key('readerScreen')), findsOneWidget);
    expect(find.byKey(const Key('readerBookPane')), findsOneWidget);
    expect(find.byKey(const Key('readerBookParagraphList')), findsOneWidget);
    expect(find.byKey(const Key('readerBookChapterTitle_0')), findsOneWidget);
    expect(find.text('Chapter One'), findsOneWidget);
    // Paragraphs rendered via CueRow (± tokens) — find by cue keys / words.
    expect(find.byKey(const Key('readerCue_0')), findsOneWidget);
    expect(find.byKey(const Key('readerCue_1')), findsOneWidget);
    expect(find.text('fox'), findsWidgets);
    expect(find.text('woods'), findsOneWidget);
    // Not a timed subtitle cue list.
    expect(find.byKey(const Key('readerCueList')), findsNothing);
    expect(find.byKey(const Key('readerCueTime_0')), findsNothing);
  });

  testWidgets('RC-02: Bottom chapter pager advances', (tester) async {
    await pumpBookReader(tester);

    expect(find.byKey(const Key('readerBookChapterPager')), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('Chapter One'), findsOneWidget);
    expect(find.byKey(const Key('readerBookParagraphList_0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('readerBookChapterNext')));
    await tester.pumpAndSettle();

    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('Chapter Two'), findsOneWidget);
    expect(find.byKey(const Key('readerBookParagraphList_1')), findsOneWidget);
    expect(find.text('rabbit'), findsOneWidget);
    expect(find.text('woods'), findsNothing);

    await tester.tap(find.byKey(const Key('readerBookChapterPrev')));
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('Chapter One'), findsOneWidget);
    expect(find.byKey(const Key('readerBookParagraphList_0')), findsOneWidget);
  });

  testWidgets('RC-03: Pager page count equals chapter count', (tester) async {
    pumpChapters = [
      const EpubChapterDto(
        index: 0,
        title: 'A',
        paragraphs: ['alpha'],
      ),
      const EpubChapterDto(
        index: 1,
        title: 'B',
        paragraphs: ['beta'],
      ),
      const EpubChapterDto(
        index: 2,
        title: 'C',
        paragraphs: ['gamma'],
      ),
      const EpubChapterDto(
        index: 3,
        title: 'D',
        paragraphs: ['delta'],
      ),
    ];
    await pumpBookReader(tester);

    expect(find.text('1 / 4'), findsOneWidget);
    // Walk to last chapter — N stays 4.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('readerBookChapterNext')));
      await tester.pumpAndSettle();
    }
    expect(find.text('4 / 4'), findsOneWidget);
    expect(find.text('D'), findsOneWidget);
    expect(
      tester.widget<IconButton>(
        find.byKey(const Key('readerBookChapterNext')),
      ).onPressed,
      isNull,
    );
  });

  testWidgets('RC-04: Tap/highlight on paragraph like cues', (tester) async {
    await pumpBookReader(tester);

    expect(find.byKey(const Key('readerCueTime_0')), findsNothing);
    expect(find.byKey(const Key('readerCueToken_0_0')), findsOneWidget);
    expect(find.byKey(const Key('readerAddVocabCta')), findsNothing);

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerAddVocabCta')), findsOneWidget);
    expect(find.text('Add to vocabulary'), findsOneWidget);
  });

  testWidgets('RC-05: No video chrome for EPUB document', (tester) async {
    await pumpBookReader(tester);

    expect(find.byKey(const Key('readerLoadVideo')), findsNothing);
    expect(find.byKey(const Key('readerRemoveVideo')), findsNothing);
    expect(find.byKey(const Key('readerSplitToggle')), findsOneWidget);
  });

  testWidgets('RC-06: Restore chapter from reading anchor', (tester) async {
    final doc = await seedEpubDoc();
    pumpOriginalDocumentId = doc.id;
    pumpInitialReadingAnchor = const ReadingAnchor(startMs: 2);

    await pumpBookReader(tester);

    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('Chapter Three'), findsOneWidget);
    expect(find.byKey(const Key('readerBookParagraphList_2')), findsOneWidget);
    expect(find.text('friends'), findsOneWidget);
    expect(find.text('Chapter One'), findsNothing);
  });

  testWidgets('RC-06 persist: chapter index saved on pager settle', (
    tester,
  ) async {
    final doc = await seedEpubDoc();
    pumpOriginalDocumentId = doc.id;
    await pumpBookReader(tester);

    await tester.tap(find.byKey(const Key('readerBookChapterNext')));
    await tester.pumpAndSettle();
    // Allow async saveReadingAnchor.
    await tester.pump(const Duration(milliseconds: 50));

    final anchor = await documents.loadReadingAnchor(doc.id);
    expect(anchor, isNotNull);
    expect(anchor!.startMs, 1);
  });
}
