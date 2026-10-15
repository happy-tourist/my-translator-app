import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// UTF-16 offset for a Unicode scalar index (matches TextPainter / RenderParagraph).
int _charIndexToUtf16(String text, int charIndex) {
  if (charIndex <= 0) return 0;
  final runes = text.runes.toList();
  if (charIndex >= runes.length) return text.length;
  return String.fromCharCodes(runes.take(charIndex)).length;
}

/// Tap a book-mode token without requiring `readerCueToken_*` Widget Keys (D11).
Future<void> _tapBookToken(
  WidgetTester tester, {
  required int cueIndex,
  required int tokenIndex,
  required String paragraph,
}) async {
  final tokens = _tokensFor(paragraph);
  final token = tokens.firstWhere((t) => t.tokenIndex == tokenIndex);
  final finder = find.byKey(Key('readerCueText_$cueIndex'));
  expect(finder, findsOneWidget);
  final box = tester.renderObject(finder) as RenderParagraph;
  final utf16Start = _charIndexToUtf16(paragraph, token.charStart);
  final utf16End = _charIndexToUtf16(paragraph, token.charEnd);
  final List<TextBox> boxes = box.getBoxesForSelection(
    TextSelection(baseOffset: utf16Start, extentOffset: utf16End),
  );
  expect(boxes, isNotEmpty);
  final center = boxes.first.toRect().center;
  await tester.tapAt(box.localToGlobal(center));
  await tester.pumpAndSettle();
}

bool _paragraphTextHasWidgetSpan(InlineSpan span) {
  if (span is WidgetSpan) return true;
  if (span is TextSpan && span.children != null) {
    for (final child in span.children!) {
      if (_paragraphTextHasWidgetSpan(child)) return true;
    }
  }
  return false;
}

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
    // Book Text.rich: word surfaces are TextSpans, not separate Text widgets.
    expect(find.textContaining('fox'), findsWidgets);
    expect(find.textContaining('woods'), findsOneWidget);
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
    expect(find.textContaining('rabbit'), findsOneWidget);
    expect(find.textContaining('woods'), findsNothing);

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
    // Book mode: no per-token Widget Keys (D11); tap via char→token hit-test.
    expect(find.byKey(const Key('readerCueToken_0_0')), findsNothing);
    expect(find.byKey(const Key('readerAddVocabCta')), findsNothing);

    await _tapBookToken(
      tester,
      cueIndex: 0,
      tokenIndex: 0,
      paragraph: 'Once upon a time there was a fox.',
    );

    expect(find.byKey(const Key('readerAddVocabCta')), findsOneWidget);
    expect(find.text('Add to vocabulary'), findsOneWidget);
  });

  testWidgets('RC-07: Book hit-test without per-word WidgetSpan', (tester) async {
    await pumpBookReader(tester);

    expect(find.byKey(const Key('readerCueToken_0_0')), findsNothing);
    final textWidget = tester.widget<Text>(
      find.byKey(const Key('readerCueText_0')),
    );
    expect(textWidget.textSpan, isNotNull);
    expect(_paragraphTextHasWidgetSpan(textWidget.textSpan!), isFalse);

    await _tapBookToken(
      tester,
      cueIndex: 0,
      tokenIndex: 0,
      paragraph: 'Once upon a time there was a fox.',
    );
    expect(find.byKey(const Key('readerAddVocabCta')), findsOneWidget);
  });

  testWidgets('RC-08: Progressive tokenize keeps early tap', (tester) async {
    final restGate = Completer<void>();
    var tokenizeCalls = 0;
    final manyParas = [
      for (var i = 0; i < 8; i++) 'Word$i alpha beta gamma.',
    ];
    pumpChapters = [
      EpubChapterDto(index: 0, title: 'Long', paragraphs: manyParas),
    ];
    pumpTokenize = (texts) async {
      tokenizeCalls++;
      if (tokenizeCalls == 1) {
        // Prefix batch (≤4) returns immediately.
        expect(texts.length, lessThanOrEqualTo(4));
        return _tokenizeFromTexts(texts);
      }
      // Remainder waits until test releases the gate.
      await restGate.future;
      return _tokenizeFromTexts(texts);
    };

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
          tokenizeCues: pumpTokenize,
          markVocabTokens: pumpMark,
        ),
      ),
    );
    // Allow prefix tokenize + idle schedule to request rest (still gated).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(tokenizeCalls, greaterThanOrEqualTo(1));
    expect(find.byKey(const Key('readerAddVocabCta')), findsNothing);

    // Early paragraph is tap-ready before full-chapter tokenize completes.
    await _tapBookToken(
      tester,
      cueIndex: 0,
      tokenIndex: 0,
      paragraph: manyParas[0],
    );
    expect(find.byKey(const Key('readerAddVocabCta')), findsOneWidget);

    restGate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('RC-09: Chapter token cache on pager return', (tester) async {
    final tokenizeBatches = <List<String>>[];
    pumpTokenize = (texts) async {
      tokenizeBatches.add(List<String>.from(texts));
      return _tokenizeFromTexts(texts);
    };
    await pumpBookReader(tester);

    final batchesAfterOpen = tokenizeBatches.length;
    expect(batchesAfterOpen, greaterThanOrEqualTo(1));

    await tester.tap(find.byKey(const Key('readerBookChapterNext')));
    await tester.pumpAndSettle();
    final batchesAfterNext = tokenizeBatches.length;
    expect(batchesAfterNext, greaterThan(batchesAfterOpen));

    await tester.tap(find.byKey(const Key('readerBookChapterPrev')));
    await tester.pumpAndSettle();

    // Return to chapter 0: cache hit — no additional tokenize batches (RC-09).
    expect(tokenizeBatches.length, batchesAfterNext);

    await _tapBookToken(
      tester,
      cueIndex: 0,
      tokenIndex: 0,
      paragraph: 'Once upon a time there was a fox.',
    );
    expect(find.byKey(const Key('readerAddVocabCta')), findsOneWidget);
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
    expect(find.textContaining('friends'), findsOneWidget);
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
