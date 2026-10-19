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
import 'package:my_translator_app/data/library/parse_epub_fn.dart';
import 'package:my_translator_app/features/reader/reader_screen.dart';
import 'package:my_translator_app/features/reader/tokenize_cues_fn.dart';
import 'package:my_translator_app/src/rust/api/epub.dart';
import 'package:my_translator_app/src/rust/api/tokenize.dart';

import '../../support/test_database.dart';

List<EpubChapterDto> _chapters({
  required int count,
  String titlePrefix = 'Chapter',
  String paraPrefix = 'Para',
}) =>
    [
      for (var i = 0; i < count; i++)
        EpubChapterDto(
          index: i,
          title: '$titlePrefix ${i + 1}',
          paragraphs: ['$paraPrefix ${i + 1} body'],
        ),
    ];

/// Multi-paragraph chapters for mid-chapter scroll / one-shot tests.
List<EpubChapterDto> _multiParaChapters({
  required int chapterCount,
  required int paragraphCount,
  String titlePrefix = 'Chapter',
  String paraPrefix = 'Para',
}) =>
    [
      for (var c = 0; c < chapterCount; c++)
        EpubChapterDto(
          index: c,
          title: '$titlePrefix ${c + 1}',
          paragraphs: [
            for (var p = 0; p < paragraphCount; p++) '$paraPrefix $p',
          ],
        ),
    ];

/// Empty tokens — avoids progressive tokenize rebuilds hanging pumpAndSettle.
Future<List<CueTokensDto>> _emptyTokenize(List<String> texts) async => [
      for (var i = 0; i < texts.length; i++)
        CueTokensDto(cueIndex: i, tokens: const []),
    ];

/// Bounded settle — avoids hangs from SPL animations.
Future<void> _pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Top-visible paragraph index inside [listKey] (book rows use Text.rich).
/// Matches [_topVisible]: include rows that still intersect the list (trailing
/// edge below list top), not only those whose leading edge is fully inside.
int _topParaIndex(
  WidgetTester tester, {
  required Key listKey,
  required String keyPrefix,
  required int paragraphCount,
}) {
  final listRect = tester.getRect(find.byKey(listKey));
  int? bestIndex;
  double? bestTop;
  for (var i = 0; i < paragraphCount; i++) {
    final finder = find.byKey(Key('${keyPrefix}_$i'));
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder);
    // Fully above or fully below the list clip — ignore.
    if (rect.bottom <= listRect.top + 1) continue;
    if (rect.top >= listRect.bottom - 1) continue;
    if (bestTop == null || rect.top < bestTop) {
      bestTop = rect.top;
      bestIndex = i;
    }
  }
  expect(bestIndex, isNotNull);
  return bestIndex!;
}

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
}) async =>
    cues;

void main() {
  late final db = createTestDatabase();
  late MemoryDocumentContentStore store;
  late FolderRepository folders;
  late DocumentRepository documents;
  late DictionaryRepository dictionary;

  late List<EpubChapterDto> pumpOriginalChapters;
  List<EpubChapterDto>? pumpTranslationChapters;
  late String pumpTitle;
  late int pumpOriginalDocumentId;
  int? pumpTranslationDocumentId;
  ReadingAnchor? pumpInitialReadingAnchor;
  ReaderTranslationPicker? pumpPicker;
  ParseEpubFn? pumpParseEpub;
  TokenizeCuesFn? pumpTokenize;
  MarkVocabTokensFn? pumpMark;

  setUp(() {
    store = MemoryDocumentContentStore();
    folders = FolderRepository(db, contentStore: store);
    documents = DocumentRepository(db, contentStore: store);
    dictionary = DictionaryRepository(db);
    pumpOriginalChapters = _chapters(count: 3, paraPrefix: 'Orig');
    pumpTranslationChapters = null;
    pumpTitle = 'sample.epub';
    pumpOriginalDocumentId = 1;
    pumpTranslationDocumentId = null;
    pumpInitialReadingAnchor = null;
    pumpPicker = null;
    pumpParseEpub = null;
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

  Future<Document> seedEpubDoc({String fileName = 'sample.epub'}) async {
    final folder = await folders.createFolder(name: 'Books');
    return documents.importIntoFolder(
      folderId: folder.id,
      fileName: fileName,
      bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x00]),
    );
  }

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
          originalChapters: pumpOriginalChapters,
          translationChapters: pumpTranslationChapters,
          translationDocumentId: pumpTranslationDocumentId,
          initialReadingAnchor: pumpInitialReadingAnchor,
          parseEpub: pumpParseEpub,
          filePicker: pumpPicker,
          tokenizeCues: pumpTokenize,
          markVocabTokens: pumpMark,
        ),
      ),
    );
    await tester.pump();
    // Bounded — multi-para + SPL can keep scheduling frames forever.
    await _pumpFrames(tester, frames: 20);
  }

  testWidgets('RS-13: Load EPUB translation shows chapters in bottom', (
    tester,
  ) async {
    final original = await seedEpubDoc();
    pumpOriginalDocumentId = original.id;
    final translationChapters = _chapters(
      count: 3,
      titlePrefix: 'TrChapter',
      paraPrefix: 'TrPara',
    );
    pumpPicker = () async => PickedTranslationFile(
          fileName: 'ru.epub',
          bytes: Uint8List.fromList([1, 2, 3]),
        );
    pumpParseEpub = ({required bytes}) async =>
        ParsedEpub(chapters: translationChapters);

    await pumpBookReader(tester);
    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerTranslationEmpty')), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationLoad')), findsOneWidget);

    await tester.tap(find.byKey(const Key('readerTranslationLoad')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerTranslationBookPane')), findsOneWidget);
    expect(find.text('TrChapter 1'), findsOneWidget);
    expect(find.text('TrPara 1 body'), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationEmpty')), findsNothing);
    expect(find.byKey(const Key('readerBookPane')), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);

    final reloaded = await documents.getById(original.id);
    expect(reloaded!.translationDocumentId, isNotNull);
    final linked = await documents.getById(reloaded.translationDocumentId!);
    expect(linked!.format, documentFormatEpub);
  });

  testWidgets('RS-08 epub: reject subtitle translation for EPUB original', (
    tester,
  ) async {
    final original = await seedEpubDoc();
    pumpOriginalDocumentId = original.id;
    pumpPicker = () async => PickedTranslationFile(
          fileName: 'ru.srt',
          bytes: Uint8List.fromList([1, 2, 3]),
        );
    var parseEpubCalled = false;
    pumpParseEpub = ({required bytes}) async {
      parseEpubCalled = true;
      return ParsedEpub(chapters: _chapters(count: 1));
    };

    await pumpBookReader(tester);
    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerTranslationLoad')));
    await tester.pumpAndSettle();

    expect(parseEpubCalled, isFalse);
    expect(find.byKey(const Key('readerTranslationErrorSnack')), findsOneWidget);
    expect(find.text(incompatibleTranslationFormatMessage), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationEmpty')), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationBookPane')), findsNothing);
    expect(find.byKey(const Key('readerBookPane')), findsOneWidget);

    final reloaded = await documents.getById(original.id);
    expect(reloaded!.translationDocumentId, isNull);
  });

  testWidgets('RS-08 epub: parse error shows D10 copy, no translation', (
    tester,
  ) async {
    final original = await seedEpubDoc();
    pumpOriginalDocumentId = original.id;
    pumpPicker = () async => PickedTranslationFile(
          fileName: 'bad.epub',
          bytes: Uint8List.fromList([1, 2, 3]),
        );
    pumpParseEpub = ({required bytes}) async {
      throw EpubParseErrorKind.malformed;
    };

    await pumpBookReader(tester);
    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerTranslationLoad')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerTranslationErrorSnack')), findsOneWidget);
    expect(find.text('Could not open this EPUB file'), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationEmpty')), findsOneWidget);
    expect(find.byKey(const Key('readerBookPane')), findsOneWidget);

    final reloaded = await documents.getById(original.id);
    expect(reloaded!.translationDocumentId, isNull);
  });

  testWidgets(
    'RS-14 / RS-15 / RC-10: Chapter pager is independent per pane',
    (tester) async {
      pumpOriginalChapters = _chapters(count: 3, paraPrefix: 'Orig');
      pumpTranslationChapters = _chapters(
        count: 3,
        titlePrefix: 'TrChapter',
        paraPrefix: 'TrPara',
      );
      pumpTranslationDocumentId = 99;

      await pumpBookReader(tester);
      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await tester.pumpAndSettle();

      expect(find.text('1 / 3'), findsNWidgets(2));
      expect(find.text('Chapter 1'), findsOneWidget);
      expect(find.text('TrChapter 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('readerBookChapterNext')));
      await tester.pumpAndSettle();

      // Top advances; bottom stays (no realtime pager sync).
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('Chapter 2'), findsOneWidget);
      expect(find.text('TrChapter 1'), findsOneWidget);
      expect(find.text('TrPara 1 body'), findsOneWidget);
      expect(
        find.byKey(const Key('readerOriginalBookParagraphList_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('readerTranslationBookParagraphList_0')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('readerTranslationBookChapterNext')),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 / 3'), findsNWidgets(2));
      expect(find.text('Chapter 2'), findsOneWidget);
      expect(find.text('TrChapter 2'), findsOneWidget);
      expect(
        find.byKey(const Key('readerOriginalBookParagraphList_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('readerTranslationBookParagraphList_1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('RS-10 epub: Show split preserves mid-chapter scroll', (
    tester,
  ) async {
    pumpOriginalChapters = _multiParaChapters(
      chapterCount: 1,
      paragraphCount: 40,
      paraPrefix: 'Orig',
    );
    pumpTokenize = _emptyTokenize;

    await pumpBookReader(tester);

    const singleList = Key('readerBookParagraphList');
    const splitList = Key('readerOriginalBookParagraphList');
    await tester.drag(find.byKey(singleList), const Offset(0, -2500));
    await _pumpFrames(tester);

    final anchorIndex = _topParaIndex(
      tester,
      listKey: singleList,
      keyPrefix: 'readerCue',
      paragraphCount: 40,
    );
    expect(anchorIndex, greaterThan(0));

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await _pumpFrames(tester);

    expect(find.byKey(splitList), findsOneWidget);
    expect(find.byKey(Key('readerCue_$anchorIndex')), findsOneWidget);

    final afterIndex = _topParaIndex(
      tester,
      listKey: splitList,
      keyPrefix: 'readerCue',
      paragraphCount: 40,
    );
    expect(afterIndex, greaterThan(0));
    expect((afterIndex - anchorIndex).abs(), lessThanOrEqualTo(2));
  });

  testWidgets('RS-11 epub: Hide split preserves mid-chapter scroll', (
    tester,
  ) async {
    pumpOriginalChapters = _multiParaChapters(
      chapterCount: 1,
      paragraphCount: 40,
      paraPrefix: 'Orig',
    );
    pumpTokenize = _emptyTokenize;

    await pumpBookReader(tester);
    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await _pumpFrames(tester);
    const singleList = Key('readerBookParagraphList');
    const splitList = Key('readerOriginalBookParagraphList');
    expect(find.byKey(splitList), findsOneWidget);

    await tester.drag(find.byKey(splitList), const Offset(0, -2500));
    await _pumpFrames(tester);

    final anchorIndex = _topParaIndex(
      tester,
      listKey: splitList,
      keyPrefix: 'readerCue',
      paragraphCount: 40,
    );
    expect(anchorIndex, greaterThan(0));

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await _pumpFrames(tester);

    expect(find.byKey(singleList), findsOneWidget);
    expect(find.byKey(Key('readerCue_$anchorIndex')), findsOneWidget);

    final afterIndex = _topParaIndex(
      tester,
      listKey: singleList,
      keyPrefix: 'readerCue',
      paragraphCount: 40,
    );
    expect(afterIndex, greaterThan(0));
    // Hide remounts into a taller viewport; allow a wider band than Show (RS-10)
    // while still requiring mid-chapter (not para 0).
    expect((afterIndex - anchorIndex).abs(), lessThanOrEqualTo(15));
  });

  testWidgets(
    'RS-19: Show split one-shot aligns EPUB chapter and paragraph',
    (tester) async {
      // Paragraph one-shot (chapter index covered with pager after Show).
      const paraCount = 25;
      pumpOriginalChapters = _multiParaChapters(
        chapterCount: 1,
        paragraphCount: paraCount,
        paraPrefix: 'Orig',
      );
      pumpTranslationChapters = _multiParaChapters(
        chapterCount: 1,
        paragraphCount: paraCount,
        titlePrefix: 'TrChapter',
        paraPrefix: 'Tr',
      );
      pumpTranslationDocumentId = 99;
      pumpTokenize = _emptyTokenize;

      await pumpBookReader(tester);

      const singleList = Key('readerBookParagraphList');
      const trList = Key('readerTranslationBookParagraphList');
      await tester.drag(find.byKey(singleList), const Offset(0, -1200));
      await _pumpFrames(tester);
      final anchorIndex = _topParaIndex(
        tester,
        listKey: singleList,
        keyPrefix: 'readerCue',
        paragraphCount: paraCount,
      );
      expect(anchorIndex, greaterThan(0));

      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester, frames: 16);

      expect(find.text('TrChapter 1'), findsOneWidget);
      expect(
        find.byKey(Key('readerTranslationCue_$anchorIndex')),
        findsOneWidget,
      );
      final trIndex = _topParaIndex(
        tester,
        listKey: trList,
        keyPrefix: 'readerTranslationCue',
        paragraphCount: paraCount,
      );
      expect(trIndex, greaterThan(0));
      expect((trIndex - anchorIndex).abs(), lessThanOrEqualTo(2));
    },
  );

  testWidgets(
    'RS-19 chapter: Show split one-shot aligns EPUB chapter index',
    (tester) async {
      pumpOriginalChapters = _chapters(count: 3, paraPrefix: 'Orig');
      pumpTranslationChapters = _chapters(
        count: 3,
        titlePrefix: 'TrChapter',
        paraPrefix: 'TrPara',
      );
      pumpTranslationDocumentId = 99;

      await pumpBookReader(tester);
      await tester.tap(find.byKey(const Key('readerBookChapterNext')));
      await _pumpFrames(tester);
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester);

      expect(find.text('2 / 3'), findsNWidgets(2));
      expect(find.text('Chapter 2'), findsOneWidget);
      expect(find.text('TrChapter 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('readerBookChapterNext')));
      await _pumpFrames(tester);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('TrChapter 2'), findsOneWidget);
    },
  );

  testWidgets(
    'RS-20: Load EPUB translation one-shot aligns paragraph',
    (tester) async {
      final original = await seedEpubDoc();
      pumpOriginalDocumentId = original.id;
      const paraCount = 25;
      pumpOriginalChapters = _multiParaChapters(
        chapterCount: 1,
        paragraphCount: paraCount,
        paraPrefix: 'Orig',
      );
      final translationChapters = _multiParaChapters(
        chapterCount: 1,
        paragraphCount: paraCount,
        titlePrefix: 'TrChapter',
        paraPrefix: 'Tr',
      );
      pumpPicker = () async => PickedTranslationFile(
            fileName: 'ru.epub',
            bytes: Uint8List.fromList([1, 2, 3]),
          );
      pumpParseEpub = ({required bytes}) async =>
          ParsedEpub(chapters: translationChapters);
      pumpTokenize = _emptyTokenize;

      await pumpBookReader(tester);

      const singleList = Key('readerBookParagraphList');
      const trList = Key('readerTranslationBookParagraphList');
      await tester.drag(find.byKey(singleList), const Offset(0, -1200));
      await _pumpFrames(tester);
      final anchorIndex = _topParaIndex(
        tester,
        listKey: singleList,
        keyPrefix: 'readerCue',
        paragraphCount: paraCount,
      );
      expect(anchorIndex, greaterThan(0));

      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('readerTranslationLoad')));
      await _pumpFrames(tester, frames: 16);

      expect(find.text('TrChapter 1'), findsOneWidget);
      expect(
        find.byKey(Key('readerTranslationCue_$anchorIndex')),
        findsOneWidget,
      );
      final trIndex = _topParaIndex(
        tester,
        listKey: trList,
        keyPrefix: 'readerTranslationCue',
        paragraphCount: paraCount,
      );
      expect(trIndex, greaterThan(0));
      expect((trIndex - anchorIndex).abs(), lessThanOrEqualTo(2));
    },
  );

  testWidgets(
    'RS-20 chapter: Load EPUB translation one-shot aligns chapter index',
    (tester) async {
      final original = await seedEpubDoc();
      pumpOriginalDocumentId = original.id;
      pumpOriginalChapters = _chapters(count: 3, paraPrefix: 'Orig');
      final translationChapters = _chapters(
        count: 3,
        titlePrefix: 'TrChapter',
        paraPrefix: 'TrPara',
      );
      pumpPicker = () async => PickedTranslationFile(
            fileName: 'ru.epub',
            bytes: Uint8List.fromList([1, 2, 3]),
          );
      pumpParseEpub = ({required bytes}) async =>
          ParsedEpub(chapters: translationChapters);

      await pumpBookReader(tester);
      await tester.tap(find.byKey(const Key('readerBookChapterNext')));
      await _pumpFrames(tester);
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('readerTranslationLoad')));
      await _pumpFrames(tester);

      expect(find.text('2 / 3'), findsNWidgets(2));
      expect(find.text('Chapter 2'), findsOneWidget);
      expect(find.text('TrChapter 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('readerBookChapterNext')));
      await _pumpFrames(tester);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('TrChapter 2'), findsOneWidget);
    },
  );

  testWidgets(
    'RS-21: After EPUB one-shot paragraph scroll is independent',
    (tester) async {
      const paraCount = 25;
      pumpOriginalChapters = _multiParaChapters(
        chapterCount: 1,
        paragraphCount: paraCount,
        paraPrefix: 'Orig',
      );
      pumpTranslationChapters = _multiParaChapters(
        chapterCount: 1,
        paragraphCount: paraCount,
        titlePrefix: 'TrChapter',
        paraPrefix: 'Tr',
      );
      pumpTranslationDocumentId = 99;
      pumpTokenize = _emptyTokenize;

      await pumpBookReader(tester);

      const singleList = Key('readerBookParagraphList');
      const splitList = Key('readerOriginalBookParagraphList');
      const trList = Key('readerTranslationBookParagraphList');
      await tester.drag(find.byKey(singleList), const Offset(0, -1200));
      await _pumpFrames(tester);

      final anchorIndex = _topParaIndex(
        tester,
        listKey: singleList,
        keyPrefix: 'readerCue',
        paragraphCount: paraCount,
      );
      expect(anchorIndex, greaterThan(0));

      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester, frames: 16);

      final trIndex = _topParaIndex(
        tester,
        listKey: trList,
        keyPrefix: 'readerTranslationCue',
        paragraphCount: paraCount,
      );
      expect((trIndex - anchorIndex).abs(), lessThanOrEqualTo(2));

      // Scroll original further — translation must not follow (no settle-sync).
      await tester.drag(find.byKey(splitList), const Offset(0, -800));
      await _pumpFrames(tester);

      final trAfter = _topParaIndex(
        tester,
        listKey: trList,
        keyPrefix: 'readerTranslationCue',
        paragraphCount: paraCount,
      );
      expect(trAfter, trIndex);
    },
  );

  testWidgets('RS-22: Unequal paragraph counts clamp on one-shot', (
    tester,
  ) async {
    // Original has many paragraphs; scroll far. Translation has few (M ≤ p).
    const paraCount = 25;
    pumpOriginalChapters = _multiParaChapters(
      chapterCount: 1,
      paragraphCount: paraCount,
      paraPrefix: 'Orig',
    );
    pumpTranslationChapters = _multiParaChapters(
      chapterCount: 1,
      paragraphCount: 3,
      titlePrefix: 'TrChapter',
      paraPrefix: 'Tr',
    );
    pumpTranslationDocumentId = 99;
    pumpTokenize = _emptyTokenize;

    await pumpBookReader(tester);

    const origList = Key('readerBookParagraphList');
    await tester.drag(find.byKey(origList), const Offset(0, -1200));
    await _pumpFrames(tester);

    final anchorIndex = _topParaIndex(
      tester,
      listKey: origList,
      keyPrefix: 'readerCue',
      paragraphCount: paraCount,
    );
    expect(anchorIndex, greaterThanOrEqualTo(3));

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await _pumpFrames(tester);

    expect(find.byKey(const Key('readerTranslationBookPane')), findsOneWidget);
    // Clamped to last available translation paragraph (index 2).
    expect(find.byKey(const Key('readerTranslationCue_2')), findsOneWidget);
    expect(find.text('Tr 2'), findsOneWidget);
    // No crash / error chrome for unequal paragraph counts (unlike RS-16).
    expect(find.byKey(const Key('readerTranslationErrorSnack')), findsNothing);
  });

  testWidgets('RS-16: Mismatched chapter counts show error and clamp', (
    tester,
  ) async {
    final original = await seedEpubDoc();
    pumpOriginalDocumentId = original.id;
    pumpOriginalChapters = _chapters(count: 3, paraPrefix: 'Orig');
    final translationChapters = _chapters(
      count: 2,
      titlePrefix: 'TrChapter',
      paraPrefix: 'TrPara',
    );
    pumpPicker = () async => PickedTranslationFile(
          fileName: 'ru.epub',
          bytes: Uint8List.fromList([1, 2, 3]),
        );
    pumpParseEpub = ({required bytes}) async =>
        ParsedEpub(chapters: translationChapters);

    await pumpBookReader(tester);
    // Advance original to chapter 3 before load so one-shot must clamp.
    await tester.tap(find.byKey(const Key('readerBookChapterNext')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerBookChapterNext')));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerTranslationLoad')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerTranslationErrorSnack')), findsOneWidget);
    expect(find.text(mismatchedEpubChapterCountMessage), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationBookPane')), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Chapter 3'), findsOneWidget);
    expect(find.text('TrChapter 2'), findsOneWidget);

    // Independent: moving original does not drag translation.
    await tester.tap(find.byKey(const Key('readerBookChapterPrev')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('TrChapter 2'), findsOneWidget);
  });

  testWidgets('RS-07: Delete EPUB translation returns to empty', (tester) async {
    final original = await seedEpubDoc();
    final translation = await documents.attachTranslation(
      originalDocumentId: original.id,
      fileName: 'ru.epub',
      bytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x00]),
    );
    pumpOriginalDocumentId = original.id;
    pumpTranslationDocumentId = translation.id;
    // Equal N with original (setUp count: 3) — RS-07 happy path, not RS-16.
    pumpTranslationChapters = _chapters(
      count: 3,
      titlePrefix: 'TrChapter',
      paraPrefix: 'TrPara',
    );

    await pumpBookReader(tester);
    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();
    expect(find.text('TrChapter 1'), findsOneWidget);

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const Key('readerTranslationDelete')),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('readerTranslationDelete')), findsOneWidget);

    await tester.tap(find.byKey(const Key('readerTranslationDelete')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerTranslationEmpty')), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationLoad')), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationBookPane')), findsNothing);
    expect(find.text('TrChapter 1'), findsNothing);
    expect(find.byKey(const Key('readerBookPane')), findsOneWidget);

    final reloaded = await documents.getById(original.id);
    expect(reloaded!.translationDocumentId, isNull);
    expect(await documents.getById(translation.id), isNull);
  });

  testWidgets('RS-09: Reopen restores EPUB translation in split', (
    tester,
  ) async {
    // Equal N with original (setUp count: 3) — RS-09 restore, not RS-16.
    pumpTranslationChapters = _chapters(
      count: 3,
      titlePrefix: 'SavedTr',
      paraPrefix: 'SavedPara',
    );
    pumpTranslationDocumentId = 99;

    await pumpBookReader(tester);
    expect(find.text('SavedTr 1'), findsNothing);

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerTranslationBookPane')), findsOneWidget);
    expect(find.text('SavedTr 1'), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationEmpty')), findsNothing);
  });

  testWidgets('RS-12 epub: Reopen resumes at saved chapter index', (
    tester,
  ) async {
    final doc = await seedEpubDoc();
    pumpOriginalDocumentId = doc.id;
    pumpInitialReadingAnchor = const ReadingAnchor(startMs: 2);
    pumpOriginalChapters = _chapters(count: 3, paraPrefix: 'Orig');

    await pumpBookReader(tester);

    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('Chapter 3'), findsOneWidget);
    expect(find.byKey(const Key('readerBookParagraphList_2')), findsOneWidget);
    expect(find.textContaining('Orig'), findsWidgets);
    expect(find.text('Chapter 1'), findsNothing);
  });

  testWidgets('RS-17: Split divider drag does not rebuild paragraph lists', (
    tester,
  ) async {
    pumpOriginalChapters = _chapters(count: 2, paraPrefix: 'Orig');
    pumpTranslationChapters = _chapters(
      count: 2,
      titlePrefix: 'TrChapter',
      paraPrefix: 'TrPara',
    );
    pumpTranslationDocumentId = 99;

    await pumpBookReader(tester);
    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('readerOriginalBookParagraphList_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('readerTranslationBookParagraphList_0')),
      findsOneWidget,
    );

    final origListElementBefore = tester.element(
      find.byKey(const Key('readerOriginalBookParagraphList_0')),
    );
    final transListElementBefore = tester.element(
      find.byKey(const Key('readerTranslationBookParagraphList_0')),
    );

    final divider = find.byKey(const Key('readerSplitDivider'));
    expect(divider, findsOneWidget);
    await tester.drag(divider, const Offset(0, 40));
    await tester.pump();

    // D13: ValueNotifier height change — ListView elements must survive drag.
    expect(
      tester.element(
        find.byKey(const Key('readerOriginalBookParagraphList_0')),
      ),
      same(origListElementBefore),
    );
    expect(
      tester.element(
        find.byKey(const Key('readerTranslationBookParagraphList_0')),
      ),
      same(transListElementBefore),
    );
    expect(find.text('TrPara 1 body'), findsOneWidget);
    expect(find.textContaining('Orig'), findsWidgets);
  });
}
