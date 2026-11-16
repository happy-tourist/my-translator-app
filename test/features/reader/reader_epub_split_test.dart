import 'dart:typed_data';

import 'package:flutter/gestures.dart';
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
  ReadingAnchor? pumpInitialTranslationReadingAnchor;
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
    pumpInitialTranslationReadingAnchor = null;
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
          initialTranslationReadingAnchor: pumpInitialTranslationReadingAnchor,
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
    // D12 / RC-11: translation pane is text-only — no chapter title chrome.
    expect(find.text('TrChapter 1'), findsNothing);
    expect(find.text('TrPara 1 body'), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationEmpty')), findsNothing);
    expect(find.byKey(const Key('readerBookPane')), findsOneWidget);
    // D15 / RC-13: original also has no fixed title chrome; pager remains.
    expect(find.text('Chapter 1'), findsNothing);
    expect(find.byKey(const Key('readerBookChapterPager')), findsOneWidget);

    final reloaded = await documents.getById(original.id);
    expect(reloaded!.translationDocumentId, isNotNull);
    final linked = await documents.getById(reloaded.translationDocumentId!);
    expect(linked!.format, documentFormatEpub);
  });

  testWidgets('RS-23 epub: Bottom pane text-only under divider', (
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
    await tester.tap(find.byKey(const Key('readerTranslationLoad')));
    await tester.pumpAndSettle();

    // D12 / RC-11: no title/pager chrome inside the bottom pane.
    expect(find.text('TrChapter 1'), findsNothing);
    expect(find.byKey(const Key('readerTranslationBookChapterPager')),
        findsNothing);
    // D12 / RS-07: no delete chrome inside the bottom pane either.
    expect(
      find.descendant(
        of: find.byKey(const Key('readerTranslationBookPane')),
        matching: find.byKey(const Key('readerTranslationDelete')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const Key('readerTranslationDelete')),
      ),
      findsOneWidget,
    );

    // D12 / RS-23: first translation paragraph sits flush under the
    // divider — no extra title/pager/delete-bar chrome pushing it down.
    final dividerBottom =
        tester.getRect(find.byKey(const Key('readerSplitDivider'))).bottom;
    final firstRowTop = tester.getTopLeft(find.text('TrPara 1 body')).dy;
    // No delete bar (48dp) / title / pager pushing the row down — only the
    // row's own built-in padding remains.
    expect(firstRowTop - dividerBottom, lessThan(40));
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
    'RC-10 / RC-11 / RC-12: Top pager links bottom chapter and rewinds both',
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

      // RC-11 / RC-13: pager lives only on the top pane; no title chrome.
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('Chapter 1'), findsNothing);
      expect(find.byKey(const Key('readerBookChapterPager')), findsOneWidget);
      expect(find.byKey(const Key('readerTranslationBookChapterPager')),
          findsNothing);
      expect(find.byKey(const Key('readerTranslationBookChapterNext')),
          findsNothing);
      expect(find.text('TrChapter 1'), findsNothing);
      expect(find.text('TrPara 1 body'), findsOneWidget);
      expect(
        find.byKey(const Key('readerTranslationBookParagraphList_0')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('readerBookChapterNext')));
      await tester.pumpAndSettle();

      // RC-10: top next also moves the bottom (clamp to original); RC-12:
      // both paragraph lists rewind to the start of the new chapter.
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('Chapter 2'), findsNothing);
      expect(find.text('TrPara 2 body'), findsOneWidget);
      expect(
        find.byKey(const Key('readerOriginalBookParagraphList_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('readerTranslationBookParagraphList_1')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('readerBookChapterNext')));
      await tester.pumpAndSettle();

      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('Chapter 3'), findsNothing);
      expect(find.text('TrPara 3 body'), findsOneWidget);
      expect(
        find.byKey(const Key('readerOriginalBookParagraphList_2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('readerTranslationBookParagraphList_2')),
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
    await _pumpFrames(tester, frames: 12);

    final anchorIndex = _topParaIndex(
      tester,
      listKey: singleList,
      keyPrefix: 'readerCue',
      paragraphCount: 40,
    );
    expect(anchorIndex, greaterThan(0));

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    // D17: extra pumps for slow attach/layout (avoid pumpAndSettle + SPL).
    await _pumpFrames(tester, frames: 24);

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
    'RS-25: EPUB Show remount keeps mid-chapter (Hide→Show, not chapter start)',
    (tester) async {
      // D16 A / RS-25: mid → Hide → Show must not rewind to paragraph 0.
      // Prefer drag (not tall initialScrollIndex seed) to avoid SPL jump hangs.
      const paraCount = 40;
      pumpOriginalChapters = _multiParaChapters(
        chapterCount: 1,
        paragraphCount: paraCount,
        paraPrefix: 'Orig',
      );
      pumpTokenize = _emptyTokenize;

      await pumpBookReader(tester);
      const singleList = Key('readerBookParagraphList');
      const splitList = Key('readerOriginalBookParagraphList');

      await tester.drag(find.byKey(singleList), const Offset(0, -2500));
      await _pumpFrames(tester, frames: 12);
      final mid = _topParaIndex(
        tester,
        listKey: singleList,
        keyPrefix: 'readerCue',
        paragraphCount: paraCount,
      );
      expect(mid, greaterThan(0));

      // Show → Hide → Show remounts single↔split keys twice (D16 A / D17).
      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester, frames: 24);
      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester, frames: 24);
      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester, frames: 24);

      expect(find.byKey(splitList), findsOneWidget);
      final after = _topParaIndex(
        tester,
        listKey: splitList,
        keyPrefix: 'readerCue',
        paragraphCount: paraCount,
      );
      expect(after, greaterThan(0));
      expect((after - mid).abs(), lessThanOrEqualTo(15));
    },
  );

  testWidgets(
    'RS-26: Hide→Show keeps both EPUB panes mid-chapter',
    (tester) async {
      // D17 / RS-26: both mid → Hide → Show → both still mid (own seeds).
      const paraCount = 40;
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
      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester, frames: 24);

      const origList = Key('readerOriginalBookParagraphList');
      const trList = Key('readerTranslationBookParagraphList');
      expect(find.byKey(origList), findsOneWidget);
      expect(find.byKey(trList), findsOneWidget);

      await tester.drag(find.byKey(origList), const Offset(0, -2500));
      await _pumpFrames(tester, frames: 12);
      await tester.drag(find.byKey(trList), const Offset(0, -1800));
      await _pumpFrames(tester, frames: 12);

      final origMid = _topParaIndex(
        tester,
        listKey: origList,
        keyPrefix: 'readerCue',
        paragraphCount: paraCount,
      );
      final trMid = _topParaIndex(
        tester,
        listKey: trList,
        keyPrefix: 'readerTranslationCue',
        paragraphCount: paraCount,
      );
      expect(origMid, greaterThan(0));
      expect(trMid, greaterThan(0));

      // Hide → Show remounts both panes (D17).
      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester, frames: 24);
      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester, frames: 24);

      expect(find.byKey(origList), findsOneWidget);
      expect(find.byKey(trList), findsOneWidget);

      final origAfter = _topParaIndex(
        tester,
        listKey: origList,
        keyPrefix: 'readerCue',
        paragraphCount: paraCount,
      );
      final trAfter = _topParaIndex(
        tester,
        listKey: trList,
        keyPrefix: 'readerTranslationCue',
        paragraphCount: paraCount,
      );
      expect(origAfter, greaterThan(0));
      expect(trAfter, greaterThan(0));
      expect((origAfter - origMid).abs(), lessThanOrEqualTo(15));
      expect((trAfter - trMid).abs(), lessThanOrEqualTo(15));
      // Bottom keeps its own mid — not synced to top.
      expect(trAfter, isNot(equals(0)));
    },
  );

  testWidgets(
    'RC-14: Revisit chapter still starts at paragraph 0 (not PageStorage mid)',
    (tester) async {
      // D16 B / RC-14: mid on chapter 0 → next → back → para 0 (generation
      // key defeats PageStorage). Chapter 0 tall (scroll mid like RS-10);
      // chapter 1 tiny — avoids the 2×N tall remount hang.
      const paraCount = 40;
      List<EpubChapterDto> tallThenTiny({required String paraPrefix}) => [
            EpubChapterDto(
              index: 0,
              title: 'Chapter 1',
              paragraphs: [
                for (var p = 0; p < paraCount; p++) '$paraPrefix $p',
              ],
            ),
            EpubChapterDto(
              index: 1,
              title: 'Chapter 2',
              paragraphs: const ['Only one'],
            ),
          ];
      pumpOriginalChapters = tallThenTiny(paraPrefix: 'Orig');
      pumpTranslationChapters = tallThenTiny(paraPrefix: 'Tr');
      pumpTranslationDocumentId = 99;
      pumpTokenize = _emptyTokenize;

      await pumpBookReader(tester);
      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester);

      const origList = Key('readerOriginalBookParagraphList');
      await tester.drag(find.byKey(origList), const Offset(0, -2500));
      await _pumpFrames(tester);
      final mid = _topParaIndex(
        tester,
        listKey: origList,
        keyPrefix: 'readerCue',
        paragraphCount: paraCount,
      );
      expect(mid, greaterThan(0));

      await tester.tap(find.byKey(const Key('readerBookChapterNext')));
      await _pumpFrames(tester);
      expect(find.text('2 / 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('readerBookChapterPrev')));
      await _pumpFrames(tester);
      expect(find.text('1 / 2'), findsOneWidget);

      final origAfter = _topParaIndex(
        tester,
        listKey: origList,
        keyPrefix: 'readerCue',
        paragraphCount: paraCount,
      );
      final trAfter = _topParaIndex(
        tester,
        listKey: const Key('readerTranslationBookParagraphList'),
        keyPrefix: 'readerTranslationCue',
        paragraphCount: paraCount,
      );
      expect(origAfter, 0);
      expect(trAfter, 0);
      expect(find.byKey(const Key('readerCue_0')), findsOneWidget);
      expect(find.byKey(const Key('readerTranslationCue_0')), findsOneWidget);
    },
  );

  testWidgets(
    'D16 C / RS-12: Wheel scroll updates original seed for reopen',
    (tester) async {
      const paraCount = 40;
      final doc = await seedEpubDoc();
      pumpOriginalDocumentId = doc.id;
      pumpOriginalChapters = _multiParaChapters(
        chapterCount: 1,
        paragraphCount: paraCount,
        paraPrefix: 'Orig',
      );
      pumpTokenize = _emptyTokenize;

      await pumpBookReader(tester);
      const singleList = Key('readerBookParagraphList');

      // Wheel/trackpad: PointerScrollEvent (no dragDetails) — D16 C must
      // still update session seed + persist on scroll-end.
      final center = tester.getCenter(find.byKey(singleList));
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, 2400)),
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, 2400)),
      );
      await _pumpFrames(tester, frames: 12);

      final mid = _topParaIndex(
        tester,
        listKey: singleList,
        keyPrefix: 'readerCue',
        paragraphCount: paraCount,
      );
      expect(mid, greaterThan(0));

      // Allow async saveReadingAnchor from scroll-end persist.
      await tester.pump(const Duration(milliseconds: 100));

      final anchor = await documents.loadReadingAnchor(doc.id);
      expect(anchor, isNotNull);
      expect(anchor!.paragraphIndex, isNotNull);
      expect(anchor.paragraphIndex!, greaterThan(0));
    },
  );

  testWidgets(
    'RS-19: Show split does not align EPUB paragraph to original anchor',
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

      // D9: bottom shows its own default (first) paragraph — no align to
      // the original's (scrolled-far) anchor. (No title chrome — RC-11.)
      expect(
        find.byKey(const Key('readerTranslationCue_0')),
        findsOneWidget,
      );
      final trIndex = _topParaIndex(
        tester,
        listKey: trList,
        keyPrefix: 'readerTranslationCue',
        paragraphCount: paraCount,
      );
      expect(trIndex, 0);
    },
  );

  testWidgets(
    'RS-19 chapter: Show split itself does not align; top pager does (D10)',
    (tester) async {
      pumpOriginalChapters = _chapters(count: 3, paraPrefix: 'Orig');
      pumpTranslationChapters = _chapters(
        count: 3,
        titlePrefix: 'TrChapter',
        paraPrefix: 'TrPara',
      );
      pumpTranslationDocumentId = 99;

      await pumpBookReader(tester);
      // Translation chapters already present in-session (no explicit Load);
      // Show split itself (D9) must not align the bottom to the original.
      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester);

      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('Chapter 1'), findsNothing);
      expect(find.text('TrPara 1 body'), findsOneWidget);

      // D10 / RC-10: only the top pager links the bottom chapter.
      await tester.tap(find.byKey(const Key('readerBookChapterNext')));
      await _pumpFrames(tester);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('Chapter 2'), findsNothing);
      expect(find.text('TrPara 2 body'), findsOneWidget);
    },
  );

  testWidgets(
    'RS-20: Load EPUB translation does not align paragraph to original',
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

      // D9: freshly loaded translation starts at its own default (first)
      // paragraph — no align to the original's anchor. (No title chrome —
      // RC-11.)
      expect(
        find.byKey(const Key('readerTranslationCue_0')),
        findsOneWidget,
      );
      final trIndex = _topParaIndex(
        tester,
        listKey: trList,
        keyPrefix: 'readerTranslationCue',
        paragraphCount: paraCount,
      );
      expect(trIndex, 0);
    },
  );

  testWidgets(
    'RS-20 chapter: Load does not align; top pager links once loaded (D9/D10)',
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
      // Before any translation is loaded, the top pager only moves the
      // original — nothing to link yet.
      await tester.tap(find.byKey(const Key('readerBookChapterNext')));
      await _pumpFrames(tester);
      expect(find.text('2 / 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('readerTranslationLoad')));
      await _pumpFrames(tester);

      // D9: freshly loaded translation starts at chapter 1 (its own
      // default) — no align to the original's current chapter (2).
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('Chapter 2'), findsNothing);
      expect(find.text('TrPara 1 body'), findsOneWidget);
      expect(
        find.byKey(const Key('readerTranslationBookParagraphList_0')),
        findsOneWidget,
      );

      // D10 / RC-10: now that a translation is loaded, the top pager links
      // the bottom chapter too (clamp to original).
      await tester.tap(find.byKey(const Key('readerBookChapterNext')));
      await _pumpFrames(tester);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('Chapter 3'), findsNothing);
      expect(find.text('TrPara 3 body'), findsOneWidget);
      expect(
        find.byKey(const Key('readerTranslationBookParagraphList_2')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'RS-21: After EPUB Show, further original scroll does not move translation',
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

      const splitList = Key('readerOriginalBookParagraphList');
      const trList = Key('readerTranslationBookParagraphList');

      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester, frames: 16);

      final trIndex = _topParaIndex(
        tester,
        listKey: trList,
        keyPrefix: 'readerTranslationCue',
        paragraphCount: paraCount,
      );
      expect(trIndex, 0);

      // Scroll original — translation must not follow (no settle-sync).
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

  testWidgets(
    'RS-22 / LD-32: Restore clamps bottom paragraph to shorter translation chapter',
    (tester) async {
      // Translation chapter has few paragraphs; saved anchor from a prior
      // (longer) session points past the end — restore must clamp, not crash.
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
      pumpInitialTranslationReadingAnchor = const ReadingAnchor(startMs: 20);
      pumpTokenize = _emptyTokenize;

      await pumpBookReader(tester);
      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester);

      expect(find.byKey(const Key('readerTranslationBookPane')), findsOneWidget);
      // Clamped to last available translation paragraph (index 2).
      expect(find.byKey(const Key('readerTranslationCue_2')), findsOneWidget);
      expect(find.text('Tr 2'), findsOneWidget);
      expect(find.byKey(const Key('readerTranslationErrorSnack')), findsNothing);
    },
  );

  testWidgets('RS-16: Mismatched chapter counts show error, own chapter', (
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
    // Advance original to chapter 3 before load — must not pull translation.
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
    // D9: still a noticeable mismatch error, and Load itself starts the
    // translation at its own default chapter (1) — no align to the
    // original's current chapter (3) on load.
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('Chapter 3'), findsNothing);
    expect(find.text('TrPara 1 body'), findsOneWidget);
    expect(
      find.byKey(const Key('readerTranslationBookParagraphList_0')),
      findsOneWidget,
    );

    // D10 / RC-10: once loaded, top pager links bottom with clamp (M=2 < N=3).
    await tester.tap(find.byKey(const Key('readerBookChapterPrev')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('TrPara 2 body'), findsOneWidget);
    expect(
      find.byKey(const Key('readerTranslationBookParagraphList_1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('readerBookChapterPrev')));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    // Clamp: original index 0 ≤ maxTrans (1) — translation also at chapter 1.
    expect(find.text('TrPara 1 body'), findsOneWidget);
    expect(
      find.byKey(const Key('readerTranslationBookParagraphList_0')),
      findsOneWidget,
    );
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
    // D12 / RC-11: no title chrome on the translation pane.
    expect(find.text('TrChapter 1'), findsNothing);
    expect(find.text('TrPara 1 body'), findsOneWidget);

    // D12 / RS-07: Delete lives in the AppBar next to split, not the bottom.
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const Key('readerTranslationDelete')),
      ),
      findsOneWidget,
    );

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
    // D12 / RC-11: no title chrome on the translation pane.
    expect(find.text('SavedTr 1'), findsNothing);
    expect(find.text('SavedPara 1 body'), findsOneWidget);
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
    expect(find.text('Chapter 3'), findsNothing);
    expect(find.byKey(const Key('readerBookParagraphList_2')), findsOneWidget);
    expect(find.textContaining('Orig'), findsWidgets);
    expect(find.text('Chapter 1'), findsNothing);
  });

  testWidgets(
    'LD-32 / D10: Reopen at a mid-book chapter links the bottom pane to it',
    (tester) async {
      // Original resumes at chapter index 2 (0-based) via saved anchor,
      // while a translation is already linked from Library open — the
      // bottom pane has no pager of its own, so its chapter must follow
      // the restored original chapter, not default to chapter 0.
      pumpInitialReadingAnchor = const ReadingAnchor(startMs: 2);
      pumpOriginalChapters = _chapters(count: 3, paraPrefix: 'Orig');
      pumpTranslationChapters = _chapters(
        count: 3,
        titlePrefix: 'TrChapter',
        paraPrefix: 'TrPara',
      );
      pumpTranslationDocumentId = 99;

      await pumpBookReader(tester);

      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('Chapter 3'), findsNothing);

      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await tester.pumpAndSettle();

      // Bottom pane must show chapter 3's paragraphs (clamp(original)),
      // not chapter 1 — confirming the translation chapter index followed
      // the restored original chapter on reopen (LD-32), independent of
      // the bottom's own (unset) paragraph-scroll anchor.
      expect(find.text('TrPara 3 body'), findsOneWidget);
      expect(find.text('TrPara 1 body'), findsNothing);
      expect(
        find.byKey(const Key('readerTranslationBookParagraphList_2')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'LD-33 / RS-12: Original paragraph seed + bottom own restore (no sync)',
    (tester) async {
      // Two-paragraph chapters: both rows fit the viewport (no SPL jump hang),
      // still proves paragraphIndex seed on original + independent bottom seed.
      pumpOriginalChapters = _multiParaChapters(
        chapterCount: 1,
        paragraphCount: 2,
        paraPrefix: 'Orig',
      );
      pumpTranslationChapters = _multiParaChapters(
        chapterCount: 1,
        paragraphCount: 3,
        titlePrefix: 'TrChapter',
        paraPrefix: 'Tr',
      );
      pumpTranslationDocumentId = 99;
      pumpInitialReadingAnchor = const ReadingAnchor(
        startMs: 0,
        paragraphIndex: 1,
        alignment: 0.0,
      );
      // Bottom own mid-chapter (LD-32) — distinct from original's paragraph 1.
      pumpInitialTranslationReadingAnchor = const ReadingAnchor(
        startMs: 2,
        alignment: 0.0,
      );
      pumpTokenize = _emptyTokenize;

      await pumpBookReader(tester);

      expect(find.byKey(const Key('readerCue_1')), findsOneWidget);
      expect(find.textContaining('Orig 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await _pumpFrames(tester);

      expect(
        find.byKey(const Key('readerTranslationCue_2')),
        findsOneWidget,
      );
      expect(find.textContaining('Tr 2'), findsOneWidget);
      // Not synced to original paragraph 1.
      expect(find.byKey(const Key('readerTranslationCue_1')), findsOneWidget);
    },
  );

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
