import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/app/theme.dart';
import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/data/library/parse_subtitles_fn.dart';
import 'package:my_translator_app/features/reader/cue_time_format.dart';
import 'package:my_translator_app/features/reader/nearest_cue_index.dart';
import 'package:my_translator_app/features/reader/reader_screen.dart';
import 'package:my_translator_app/features/reader/tokenize_cues_fn.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';
import 'package:my_translator_app/src/rust/api/tokenize.dart';

import '../../support/test_database.dart';

Uint8List _srtBytes([String text = 'Hi']) =>
    Uint8List.fromList(utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n$text\n'));

List<CueDto> _sampleCues({
  int count = 3,
  String prefix = 'Cue line',
  int startStepMs = 1500,
}) {
  return List.generate(count, (i) {
    final start = BigInt.from(i * startStepMs);
    final end = start + BigInt.from(1000);
    return CueDto(
      index: i,
      startMs: start,
      endMs: end,
      textLines: ['$prefix $i'],
    );
  });
}

ParsedSubtitles _parsedFromCues(List<CueDto> cues) =>
    ParsedSubtitles(format: 'srt', cues: cues);

Future<List<CueTokensDto>> _emptyTokenize(List<String> texts) async => [
      for (var i = 0; i < texts.length; i++)
        CueTokensDto(cueIndex: i, tokens: const []),
    ];

/// Word-like tokens with char spans matching [text] (for fake TokenizeCuesFn).
/// Mimics panko: letter/digit/apostrophe runs (punct stays interstitial).
/// Optional [lemmaKeys] overrides morph keys by surface (casefold lookup).
List<TokenDto> _tokensFor(
  String text, {
  Map<String, String>? lemmaKeys,
}) {
  final tokens = <TokenDto>[];
  var index = 0;
  for (final match in RegExp(r"[\w']+", unicode: true).allMatches(text)) {
    final surface = match.group(0)!;
    final lower = surface.toLowerCase();
    tokens.add(
      TokenDto(
        surface: surface,
        charStart: match.start,
        charEnd: match.end,
        tokenIndex: index++,
        lemmaKey: lemmaKeys?[lower] ?? lower,
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

/// Fake morph: running/ran → run (RH-01 wordforms).
Future<List<CueTokensDto>> _tokenizeWithMorphLemmas(List<String> texts) async {
  const morph = {
    'running': 'run',
    'ran': 'run',
    'dogs': 'dog',
  };
  return [
    for (var i = 0; i < texts.length; i++)
      CueTokensDto(
        cueIndex: i,
        tokens: _tokensFor(texts[i], lemmaKeys: morph),
      ),
  ];
}

/// Fake mark seam: morph singles + phrase windows (RH-09 / D2 compute path).
Future<List<CueTokensDto>> _fakeMarkVocabTokens({
  required List<CueTokensDto> cues,
  required List<String> vocabLemmas,
}) async {
  final singles = <String>{};
  final phrases = <({String key, int wordCount})>[];
  for (final raw in vocabLemmas) {
    final key = DictionaryRepository.normalizeSurface(raw);
    if (key.isEmpty) continue;
    if (key.contains(RegExp(r'\s'))) {
      final wordCount = key.split(RegExp(r'\s+')).length;
      if (wordCount >= 2) phrases.add((key: key, wordCount: wordCount));
    } else {
      singles.add(key);
    }
  }
  return [
    for (final cue in cues)
      CueTokensDto(
        cueIndex: cue.cueIndex,
        tokens: () {
          final marked = [
            for (final t in cue.tokens)
              TokenDto(
                surface: t.surface,
                charStart: t.charStart,
                charEnd: t.charEnd,
                tokenIndex: t.tokenIndex,
                lemmaKey: t.lemmaKey,
                isInVocab: singles.contains(t.lemmaKey.toLowerCase()),
              ),
          ];
          final n = marked.length;
          for (final phrase in phrases) {
            final w = phrase.wordCount;
            if (w > n) continue;
            for (var start = 0; start <= n - w; start++) {
              final joined = marked
                  .sublist(start, start + w)
                  .map((t) => t.surface.trim().toLowerCase())
                  .join(' ');
              if (joined == phrase.key) {
                for (var i = start; i < start + w; i++) {
                  final t = marked[i];
                  marked[i] = TokenDto(
                    surface: t.surface,
                    charStart: t.charStart,
                    charEnd: t.charEnd,
                    tokenIndex: t.tokenIndex,
                    lemmaKey: t.lemmaKey,
                    isInVocab: true,
                  );
                }
              }
            }
          }
          return marked;
        }(),
      ),
  ];
}

class _FakeTokenize {
  int callCount = 0;
  Object? throwError;
  Future<List<CueTokensDto>> Function(List<String>)? impl;

  Future<List<CueTokensDto>> call(List<String> texts) async {
    callCount++;
    if (throwError != null) throw throwError!;
    return (impl ?? _tokenizeFromTexts)(texts);
  }
}

class _FakeMark {
  int callCount = 0;
  List<String>? lastVocabLemmas;

  Future<List<CueTokensDto>> call({
    required List<CueTokensDto> cues,
    required List<String> vocabLemmas,
  }) async {
    callCount++;
    lastVocabLemmas = List<String>.from(vocabLemmas);
    return _fakeMarkVocabTokens(cues: cues, vocabLemmas: vocabLemmas);
  }
}

Color? _tokenBackground(WidgetTester tester, Key tokenKey) {
  final text = tester.widget<Text>(
    find.descendant(of: find.byKey(tokenKey), matching: find.byType(Text)),
  );
  return text.style?.backgroundColor;
}

void main() {
  late final db = createTestDatabase();
  late MemoryDocumentContentStore store;
  late FolderRepository folders;
  late DocumentRepository documents;
  late DictionaryRepository dictionary;

  // Pump-helper overrides (skill: scenario via mutable fields, not ad-hoc trees).
  late List<CueDto> pumpCues;
  late String pumpTitle;
  late int pumpOriginalDocumentId;
  List<CueDto>? pumpTranslationCues;
  int? pumpTranslationDocumentId;
  ReadingAnchor? pumpInitialReadingAnchor;
  ParseSubtitlesFn? pumpParse;
  TokenizeCuesFn? pumpTokenize;
  MarkVocabTokensFn? pumpMark;
  ReaderTranslationPicker? pumpPicker;

  setUp(() {
    store = MemoryDocumentContentStore();
    folders = FolderRepository(db, contentStore: store);
    documents = DocumentRepository(db, contentStore: store);
    dictionary = DictionaryRepository(db);
    pumpCues = _sampleCues();
    pumpTitle = 'doc';
    pumpOriginalDocumentId = 1;
    pumpTranslationCues = null;
    pumpTranslationDocumentId = null;
    pumpInitialReadingAnchor = null;
    pumpParse = null;
    pumpTokenize = _emptyTokenize;
    pumpMark = _fakeMarkVocabTokens;
    pumpPicker = null;
  });

  tearDown(() async {
    await db.delete(db.dictionaryEntries).go();
    await db.delete(db.documents).go();
    await db.delete(db.folders).go();
  });

  tearDownAll(() async {
    await db.close();
  });

  Future<void> pumpReader(WidgetTester tester) async {
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
          originalCues: pumpCues,
          originalDocumentId: pumpOriginalDocumentId,
          documentRepository: documents,
          dictionaryRepository: dictionary,
          translationCues: pumpTranslationCues,
          translationDocumentId: pumpTranslationDocumentId,
          initialReadingAnchor: pumpInitialReadingAnchor,
          parseSubtitles: pumpParse,
          tokenizeCues: pumpTokenize,
          markVocabTokens: pumpMark,
          filePicker: pumpPicker,
        ),
      ),
    );
    // Allow batch tokenize+mark (injectable) to settle without FRB.
    await tester.pump();
  }

  Future<Document> seedOriginal() async {
    final folder = await folders.createFolder(name: 'S01');
    return documents.importIntoFolder(
      folderId: folder.id,
      fileName: 'original.srt',
      bytes: _srtBytes('original'),
    );
  }

  test('formatCueTimestamp zero-pads HH:MM:SS,mmm', () {
    expect(formatCueTimestamp(BigInt.from(0)), '00:00:00,000');
    expect(formatCueTimestamp(BigInt.from(3661001)), '01:01:01,001');
    expect(formatCueTimestamp(BigInt.from(61)), '00:00:00,061');
  });

  testWidgets('RC-01: Open Reader with cue list', (tester) async {
    pumpCues = _sampleCues();
    pumpTitle = 'episode1';
    await pumpReader(tester);
    expect(find.byKey(const Key('readerScreen')), findsOneWidget);
    expect(find.byKey(const Key('readerCueList')), findsOneWidget);
    expect(find.byKey(const Key('readerCue_0')), findsOneWidget);
    expect(find.byKey(const Key('readerCue_1')), findsOneWidget);
    expect(find.byKey(const Key('readerCue_2')), findsOneWidget);
    expect(find.text('Cue line 0'), findsOneWidget);
    expect(find.text('episode1'), findsOneWidget);
  });

  testWidgets('RC-02: Show start and end times per cue', (tester) async {
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(1000),
        endMs: BigInt.from(2500),
        textLines: ['Hello'],
      ),
      CueDto(
        index: 1,
        startMs: BigInt.from(3661001),
        endMs: BigInt.from(3662002),
        textLines: ['World'],
      ),
    ];
    await pumpReader(tester);
    expect(find.text('00:00:01,000 → 00:00:02,500'), findsOneWidget);
    expect(find.text('01:01:01,001 → 01:01:02,002'), findsOneWidget);
  });

  testWidgets('RC-01: Multi-line cue text shows all text_lines', (tester) async {
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(1000),
        endMs: BigInt.from(2000),
        textLines: ['Line one', 'Line two', 'Line three'],
      ),
    ];
    await pumpReader(tester);
    expect(find.text('Line one\nLine two\nLine three'), findsOneWidget);
  });

  testWidgets('RC-03: Scroll through all cues', (tester) async {
    pumpCues = _sampleCues(count: 40);
    pumpTitle = 'long';
    await pumpReader(tester);
    expect(find.text('Cue line 0'), findsOneWidget);
    expect(find.text('Cue line 39'), findsNothing);

    await tester.drag(
      find.byKey(const Key('readerCueList')),
      const Offset(0, -4000),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cue line 39'), findsOneWidget);
  });

  testWidgets('RC-04: Navigate back to Library', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('openReader'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReaderScreen(
                          title: 'ep',
                          originalCues: _sampleCues(count: 1),
                          originalDocumentId: 1,
                          documentRepository: documents,
                          dictionaryRepository: dictionary,
                          tokenizeCues: _emptyTokenize,
                          markVocabTokens: _fakeMarkVocabTokens,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('openReader')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('readerScreen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('readerBack')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('readerScreen')), findsNothing);
    expect(find.byKey(const Key('openReader')), findsOneWidget);
  });

  testWidgets('RS-01: Toggle split shows empty bottom pane', (tester) async {
    await pumpReader(tester);
    expect(find.byKey(const Key('readerCueList')), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationEmpty')), findsNothing);

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerOriginalCueList')), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationEmpty')), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationLoad')), findsOneWidget);
    expect(find.text('No translation loaded'), findsOneWidget);
    expect(find.byKey(const Key('readerCueList')), findsNothing);
  });

  testWidgets('RS-02: Hide split keeps translation in session', (tester) async {
    pumpTranslationCues = _sampleCues(prefix: 'Tr', count: 2);
    await pumpReader(tester);

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();
    expect(find.text('Tr 0'), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationCueList')), findsOneWidget);

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('readerCueList')), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationCueList')), findsNothing);
    expect(find.byKey(const Key('readerTranslationEmpty')), findsNothing);

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();
    expect(find.text('Tr 0'), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationLoad')), findsNothing);
  });

  testWidgets('RS-03: Resize divider changes pane ratio', (tester) async {
    await pumpReader(tester);
    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();

    final topBefore =
        tester.getSize(find.byKey(const Key('readerOriginalCueList'))).height;
    final bottomBefore =
        tester.getSize(find.byKey(const Key('readerTranslationEmpty'))).height;

    await tester.drag(
      find.byKey(const Key('readerSplitDivider')),
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();

    final topAfter =
        tester.getSize(find.byKey(const Key('readerOriginalCueList'))).height;
    final bottomAfter =
        tester.getSize(find.byKey(const Key('readerTranslationEmpty'))).height;

    expect(topAfter, greaterThan(topBefore));
    expect(bottomAfter, lessThan(bottomBefore));
  });

  testWidgets('RS-04: Load translation shows cues in bottom', (tester) async {
    final original = await seedOriginal();
    pumpOriginalDocumentId = original.id;
    final translationCues = _sampleCues(prefix: 'Tr', count: 2);
    pumpPicker = () async => PickedTranslationFile(
      fileName: 'ru.srt',
      bytes: _srtBytes('перевод'),
    );
    pumpParse = ({required bytes, formatHint}) async =>
        _parsedFromCues(translationCues);

    await pumpReader(tester);
    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerTranslationLoad')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerTranslationCueList')), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationCue_0')), findsOneWidget);
    expect(find.text('Tr 0'), findsOneWidget);
    expect(find.text('Tr 1'), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationEmpty')), findsNothing);

    final reloaded = await documents.getById(original.id);
    expect(reloaded!.translationDocumentId, isNotNull);
  });

  testWidgets('RS-05: Sync after load by nearest start time', (tester) async {
    final original = await seedOriginal();
    pumpOriginalDocumentId = original.id;
    // Top stays on cue 0 (start 0). Translation nearest to 0 is index 0
    // (start 100), not the later cues — verify that cue text appears after load.
    final translationCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(100),
        endMs: BigInt.from(1100),
        textLines: ['Near anchor'],
      ),
      CueDto(
        index: 1,
        startMs: BigInt.from(8000),
        endMs: BigInt.from(9000),
        textLines: ['Far cue'],
      ),
      CueDto(
        index: 2,
        startMs: BigInt.from(16000),
        endMs: BigInt.from(17000),
        textLines: ['Farther cue'],
      ),
    ];
    pumpCues = _sampleCues(count: 20);
    pumpPicker = () async => PickedTranslationFile(
      fileName: 'ru.srt',
      bytes: _srtBytes('перевод'),
    );
    pumpParse = ({required bytes, formatHint}) async =>
        _parsedFromCues(translationCues);

    await pumpReader(tester);
    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();

    // Scroll original so cue 10 (start 15000) is the anchor, then load.
    await tester.drag(
      find.byKey(const Key('readerOriginalCueList')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();

    final topVisible = tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(const Key('readerOriginalCueList')),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => s.startsWith('Cue line '))
        .toList();
    expect(topVisible, isNotEmpty);
    final anchorLine = topVisible.first;
    final anchorIndex = int.parse(anchorLine.replaceFirst('Cue line ', ''));
    final expected = nearestCueIndex(
      translationCues,
      pumpCues[anchorIndex].startMs,
    );

    await tester.tap(find.byKey(const Key('readerTranslationLoad')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('readerTranslationCue_$expected')),
      findsOneWidget,
    );
    expect(find.text(translationCues[expected].textLines.first), findsOneWidget);
  });

  testWidgets('RS-06: Scroll sync time then pixel on settle', (tester) async {
    final originalCues = _sampleCues(count: 40, prefix: 'Orig');
    final translationCues = _sampleCues(
      count: 40,
      prefix: 'Tr',
      startStepMs: 2000,
    );
    pumpCues = originalCues;
    pumpTranslationCues = translationCues;

    await pumpReader(tester);
    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();

    expect(find.text('Tr 0'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('readerOriginalCueList')),
      const Offset(0, -3500),
    );
    await tester.pumpAndSettle();

    final origVisible = tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(const Key('readerOriginalCueList')),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => s.startsWith('Orig '))
        .toList();
    expect(origVisible, isNotEmpty);
    final anchorIndex = int.parse(origVisible.first.replaceFirst('Orig ', ''));
    final expected = nearestCueIndex(
      translationCues,
      originalCues[anchorIndex].startMs,
    );

    expect(find.byKey(Key('readerTranslationCue_$expected')), findsOneWidget);
    expect(find.text('Tr $expected'), findsOneWidget);
  });

  testWidgets('RS-07 / LD-14: Delete translation returns to empty and unlinks', (
    tester,
  ) async {
    final original = await seedOriginal();
    final translation = await documents.attachTranslation(
      originalDocumentId: original.id,
      fileName: 'ru.srt',
      bytes: _srtBytes('перевод'),
    );
    pumpOriginalDocumentId = original.id;
    pumpTranslationDocumentId = translation.id;
    pumpTranslationCues = _sampleCues(prefix: 'Tr', count: 2);

    await pumpReader(tester);
    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();
    expect(find.text('Tr 0'), findsOneWidget);

    // Delete is in bottom-pane top chrome, not AppBar (RS-07 / D8).
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
    expect(find.byKey(const Key('readerTranslationCueList')), findsNothing);
    expect(find.byKey(const Key('readerTranslationDelete')), findsNothing);
    expect(find.text('Tr 0'), findsNothing);

    final reloaded = await documents.getById(original.id);
    expect(reloaded!.translationDocumentId, isNull);
    expect(await documents.getById(translation.id), isNull);
    final listed = await documents.listInFolder(original.folderId);
    expect(listed.map((d) => d.id), [original.id]);
  });

  testWidgets('RS-08: Failed load shows error, no cues', (tester) async {
    final original = await seedOriginal();
    pumpOriginalDocumentId = original.id;
    pumpPicker = () async => PickedTranslationFile(
      fileName: 'bad.srt',
      bytes: _srtBytes('bad'),
    );
    pumpParse = ({required bytes, formatHint}) async {
      throw ParseErrorKind.empty;
    };

    await pumpReader(tester);
    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerTranslationLoad')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerTranslationErrorSnack')), findsOneWidget);
    expect(find.text('No subtitle cues found in this file'), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationEmpty')), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationCueList')), findsNothing);
    expect(find.byKey(const Key('readerOriginalCueList')), findsOneWidget);
    expect(find.text('Cue line 0'), findsOneWidget);

    final reloaded = await documents.getById(original.id);
    expect(reloaded!.translationDocumentId, isNull);
  });

  testWidgets('RS-09: Reopen restores translation in split', (tester) async {
    pumpTranslationCues = _sampleCues(prefix: 'Saved Tr', count: 2);
    pumpTranslationDocumentId = 99;
    await pumpReader(tester);

    expect(find.byKey(const Key('readerCueList')), findsOneWidget);
    expect(find.text('Saved Tr 0'), findsNothing);

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerTranslationCueList')), findsOneWidget);
    expect(find.text('Saved Tr 0'), findsOneWidget);
    expect(find.byKey(const Key('readerTranslationEmpty')), findsNothing);
  });

  testWidgets('RS-10: Toggle split preserves original scroll', (tester) async {
    pumpCues = _sampleCues(count: 40);
    await pumpReader(tester);

    await tester.drag(
      find.byKey(const Key('readerCueList')),
      const Offset(0, -2500),
    );
    await tester.pumpAndSettle();

    final beforeVisible = tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(const Key('readerCueList')),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => s.startsWith('Cue line '))
        .toList();
    expect(beforeVisible, isNotEmpty);
    final anchorLine = beforeVisible.first;
    final anchorIndex = int.parse(anchorLine.replaceFirst('Cue line ', ''));
    expect(anchorIndex, greaterThan(0));

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerOriginalCueList')), findsOneWidget);
    expect(find.byKey(Key('readerCue_$anchorIndex')), findsOneWidget);
    expect(find.text(anchorLine), findsOneWidget);

    final afterVisible = tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(const Key('readerOriginalCueList')),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => s.startsWith('Cue line '))
        .toList();
    expect(afterVisible, isNotEmpty);
    // Top-visible cue stays at the same (or nearby) index — not reset to 0.
    final afterIndex =
        int.parse(afterVisible.first.replaceFirst('Cue line ', ''));
    expect(afterIndex, greaterThan(0));
    expect((afterIndex - anchorIndex).abs(), lessThanOrEqualTo(2));
  });

  testWidgets(
    'Show split syncs translation pane to original anchor',
    (tester) async {
      final originalCues = _sampleCues(count: 40, prefix: 'Orig');
      final translationCues = _sampleCues(
        count: 40,
        prefix: 'Tr',
        startStepMs: 1500,
      );
      pumpCues = originalCues;
      pumpTranslationCues = translationCues;

      await pumpReader(tester);

      await tester.drag(
        find.byKey(const Key('readerCueList')),
        const Offset(0, -2500),
      );
      await tester.pumpAndSettle();

      final beforeVisible = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(const Key('readerCueList')),
            matching: find.byType(Text),
          ))
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => s.startsWith('Orig '))
          .toList();
      expect(beforeVisible, isNotEmpty);
      final anchorIndex =
          int.parse(beforeVisible.first.replaceFirst('Orig ', ''));
      expect(anchorIndex, greaterThan(0));
      final expected = nearestCueIndex(
        translationCues,
        originalCues[anchorIndex].startMs,
      );
      expect(expected, greaterThan(0));

      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('readerTranslationCueList')), findsOneWidget);
      expect(
        find.byKey(Key('readerTranslationCue_$expected')),
        findsOneWidget,
      );

      final trVisible = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(const Key('readerTranslationCueList')),
            matching: find.byType(Text),
          ))
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => s.startsWith('Tr '))
          .toList();
      expect(trVisible, isNotEmpty);
      final trIndex = int.parse(trVisible.first.replaceFirst('Tr ', ''));
      // Must not stay at cue 0 when original was scrolled far.
      expect(trIndex, greaterThan(0));
      expect((trIndex - expected).abs(), lessThanOrEqualTo(2));
    },
  );

  testWidgets('RS-11: Hide split preserves original scroll', (tester) async {
    pumpCues = _sampleCues(count: 40);
    await pumpReader(tester);

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('readerOriginalCueList')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('readerOriginalCueList')),
      const Offset(0, -2500),
    );
    await tester.pumpAndSettle();

    final beforeVisible = tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(const Key('readerOriginalCueList')),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => s.startsWith('Cue line '))
        .toList();
    expect(beforeVisible, isNotEmpty);
    final anchorLine = beforeVisible.first;
    final anchorIndex = int.parse(anchorLine.replaceFirst('Cue line ', ''));
    expect(anchorIndex, greaterThan(0));

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerCueList')), findsOneWidget);
    expect(find.byKey(Key('readerCue_$anchorIndex')), findsOneWidget);

    final afterVisible = tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(const Key('readerCueList')),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => s.startsWith('Cue line '))
        .toList();
    expect(afterVisible, isNotEmpty);
    final afterIndex =
        int.parse(afterVisible.first.replaceFirst('Cue line ', ''));
    expect(afterIndex, greaterThan(0));
    expect((afterIndex - anchorIndex).abs(), lessThanOrEqualTo(2));
  });

  testWidgets('RS-12: Reopen resumes at saved original anchor', (tester) async {
    pumpCues = _sampleCues(count: 40, startStepMs: 1000);
    // Cue 12 starts at 12000 ms — not the beginning of the list.
    pumpInitialReadingAnchor = const ReadingAnchor(
      startMs: 12000,
      alignment: 0.0,
    );
    await pumpReader(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerCueList')), findsOneWidget);
    expect(find.byKey(const Key('readerCue_12')), findsOneWidget);
    expect(find.text('Cue line 12'), findsOneWidget);

    final visible = tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(const Key('readerCueList')),
          matching: find.byType(Text),
        ))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => s.startsWith('Cue line '))
        .toList();
    expect(visible, isNotEmpty);
    final topIndex = int.parse(visible.first.replaceFirst('Cue line ', ''));
    expect(topIndex, greaterThan(0));
    expect((topIndex - 12).abs(), lessThanOrEqualTo(2));
  });

  testWidgets(
    'Failed restore: stuck link shows delete, then load works',
    (tester) async {
      final original = await seedOriginal();
      final translation = await documents.attachTranslation(
        originalDocumentId: original.id,
        fileName: 'ru.srt',
        bytes: _srtBytes('перевод'),
      );
      final translationCues = _sampleCues(prefix: 'New Tr', count: 1);
      // Simulate Library open that kept the link but could not parse cues.
      pumpOriginalDocumentId = original.id;
      pumpTranslationDocumentId = translation.id;
      pumpTranslationCues = null;
      pumpPicker = () async => PickedTranslationFile(
        fileName: 'new_ru.srt',
        bytes: _srtBytes('новый'),
      );
      pumpParse = ({required bytes, formatHint}) async =>
          _parsedFromCues(translationCues);

      await pumpReader(tester);
      await tester.tap(find.byKey(const Key('readerSplitToggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('readerTranslationEmpty')), findsOneWidget);
      expect(find.text('Saved translation could not be shown'), findsOneWidget);
      expect(find.byKey(const Key('readerTranslationLoad')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byKey(const Key('readerTranslationDeleteEmpty')),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const Key('readerTranslationDeleteEmpty')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('readerTranslationDeleteEmpty')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('readerTranslationLoad')), findsOneWidget);
      expect(
        find.byKey(const Key('readerTranslationDeleteEmpty')),
        findsNothing,
      );
      expect(await documents.getById(translation.id), isNull);
      expect(
        (await documents.getById(original.id))!.translationDocumentId,
        isNull,
      );

      await tester.tap(find.byKey(const Key('readerTranslationLoad')));
      await tester.pumpAndSettle();

      expect(find.text('New Tr 0'), findsOneWidget);
      expect(
        (await documents.getById(original.id))!.translationDocumentId,
        isNotNull,
      );
    },
  );

  // --- reader/tap + dictionary/entries (RT-*, DE-12/13) ---

  testWidgets('RT-01: Batch tokens ready; no re-tokenize on rebuild', (
    tester,
  ) async {
    final fake = _FakeTokenize();
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['hello world'],
      ),
    ];
    pumpTokenize = fake.call;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    expect(fake.callCount, 1);
    expect(find.byKey(const Key('readerCueToken_0_0')), findsOneWidget);
    expect(find.byKey(const Key('readerCueToken_0_1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();
    expect(fake.callCount, 1);
    expect(find.byKey(const Key('readerCueToken_0_0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();
    expect(fake.callCount, 1);
  });

  testWidgets('RT-02: Single tap shows selection and CTA', (tester) async {
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['hello world'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerAddVocabCta')), findsNothing);

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerAddVocabCta')), findsOneWidget);
    expect(find.text('Add to vocabulary'), findsOneWidget);
  });

  testWidgets('RT-17: Retap sole selected token clears selection', (tester) async {
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['hello world'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('readerAddVocabCta')), findsOneWidget);

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('readerAddVocabCta')), findsNothing);
  });

  testWidgets('RT-03: Contiguous tap extends selection', (tester) async {
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['hello world'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerCueToken_0_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerAddVocabCta')), findsOneWidget);

    await tester.tap(find.byKey(const Key('readerAddVocabCta')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('readerAddVocabSurface')),
        matching: find.text('hello world'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('RT-04: Non-contiguous tap resets anchor + ~300ms feedback', (
    tester,
  ) async {
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['one two three four'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerCueToken_0_1')));
    await tester.pumpAndSettle();

    // Gap: skip token 2, tap token 3.
    await tester.tap(find.byKey(const Key('readerCueToken_0_3')));
    await tester.pump();

    final flashText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('readerCueToken_0_3')),
        matching: find.byType(Text),
      ),
    );
    expect(flashText.style?.fontWeight, FontWeight.w700);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerAddVocabCta')), findsOneWidget);
    await tester.tap(find.byKey(const Key('readerAddVocabCta')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('readerAddVocabSurface')),
        matching: find.text('four'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('RT-16: Shrink multi selection to single', (tester) async {
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['one two three'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerCueToken_0_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerCueToken_0_2')));
    await tester.pumpAndSettle();

    // Tap inside range → shrink to that token.
    await tester.tap(find.byKey(const Key('readerCueToken_0_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerAddVocabCta')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('readerAddVocabSurface')),
        matching: find.text('two'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('RT-05: CTA opens sheet with prefilled fields', (tester) async {
    const cueText = 'hello world';
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: [cueText],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerAddVocabCta')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerAddVocabSheet')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('readerAddVocabSurface')),
        matching: find.text('hello'),
      ),
      findsOneWidget,
    );
    final translation = tester.widget<TextField>(
      find.byKey(const Key('readerAddVocabTranslation')),
    );
    expect(translation.controller!.text, isEmpty);
    final contextField = tester.widget<TextField>(
      find.byKey(const Key('readerAddVocabContext')),
    );
    expect(contextField.controller!.text, cueText);
    expect(contextField.enabled, isTrue);
  });

  testWidgets('RT-06 / DE-12: Save from sheet adds dictionary entry', (
    tester,
  ) async {
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['Running world'],
      ),
    ];
    pumpTokenize = _tokenizeWithMorphLemmas;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerAddVocabCta')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('readerAddVocabTranslation')),
      'бежать',
    );
    await tester.tap(find.byKey(const Key('readerAddVocabSave')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerAddVocabSheet')), findsNothing);
    expect(find.byKey(const Key('readerAddVocabCta')), findsNothing);

    final entry = await dictionary.lookup('run');
    expect(entry, isNotNull);
    expect(entry!.lemma, 'run');
    expect(entry.surfaceKey, 'running');
    expect(entry.translation, 'бежать');
    expect(entry.context, 'Running world');
    expect(await dictionary.list(), hasLength(1));
  });

  testWidgets('RT-07: Reject empty translation from Reader sheet', (
    tester,
  ) async {
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['hello'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerAddVocabCta')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('readerAddVocabTranslation')),
      '   ',
    );
    await tester.tap(find.byKey(const Key('readerAddVocabSave')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerAddVocabSheet')), findsOneWidget);
    expect(
      find.byKey(const Key('readerAddVocabValidationError')),
      findsOneWidget,
    );
    expect(await dictionary.list(), isEmpty);
  });

  testWidgets('RT-08: Translation pane has no token selection', (tester) async {
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['hello world'],
      ),
    ];
    pumpTranslationCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['привет мир'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerTranslationCueList')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('readerTranslationCueList')),
        matching: find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('readerCueToken_'),
        ),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('readerTranslationCue_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('readerAddVocabCta')), findsNothing);
  });

  testWidgets('RT-09: Selection stays within one cue', (tester) async {
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['alpha beta'],
      ),
      CueDto(
        index: 1,
        startMs: BigInt.from(1000),
        endMs: BigInt.from(2000),
        textLines: ['gamma delta'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerCueToken_0_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerCueToken_1_0')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerAddVocabCta')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('readerAddVocabSurface')),
        matching: find.text('gamma'),
      ),
      findsOneWidget,
    );
    final contextField = tester.widget<TextField>(
      find.byKey(const Key('readerAddVocabContext')),
    );
    expect(contextField.controller!.text, 'gamma delta');
  });

  testWidgets('RT-10 / RT-14: Phrase surface is casefold token-join', (
    tester,
  ) async {
    // Punct between tokens must not appear in phrase key (join surfaces only).
    const cueText = 'hello, world';
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: [cueText],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerCueToken_0_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerAddVocabCta')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('readerAddVocabSurface')),
        matching: find.text('hello world'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('readerAddVocabSurface')),
        matching: find.text('hello, world'),
      ),
      findsNothing,
    );
  });

  testWidgets('RT-06 / DE-18: Phrase Add saves casefold(join) key', (
    tester,
  ) async {
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['Hello World'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerCueToken_0_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerAddVocabCta')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('readerAddVocabTranslation')),
      'привет мир',
    );
    await tester.tap(find.byKey(const Key('readerAddVocabSave')));
    await tester.pumpAndSettle();

    final entry = await dictionary.lookup('hello world');
    expect(entry, isNotNull);
    expect(entry!.lemma, 'hello world');
    expect(entry.surfaceKey, 'hello world');
    expect(entry.translation, 'привет мир');
  });

  testWidgets('RT-13: Tokenize failure → plain text + SnackBar', (
    tester,
  ) async {
    final fake = _FakeTokenize()..throwError = Exception('frb down');
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['hello world'],
      ),
    ];
    pumpTokenize = fake.call;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    expect(find.text('hello world'), findsOneWidget);
    expect(find.byKey(const Key('readerCueToken_0_0')), findsNothing);
    expect(find.byKey(const Key('readerAddVocabCta')), findsNothing);
    expect(find.byKey(const Key('readerTokenizeErrorSnack')), findsOneWidget);
    expect(find.text('Could not prepare word selection'), findsOneWidget);
  });

  testWidgets('DE-13 / RH-06: Upsert from edit sheet by morph lemma', (
    tester,
  ) async {
    await dictionary.add(
      lemma: 'hello',
      surfaceKey: 'hello',
      translation: 'old',
      context: 'old ctx',
    );

    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['Hello there'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    // in_vocab → edit sheet (no Add CTA).
    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('readerAddVocabCta')), findsNothing);
    expect(find.byKey(const Key('readerEditVocabSheet')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('readerEditVocabTranslation')),
      'new tr',
    );
    await tester.enterText(
      find.byKey(const Key('readerEditVocabContext')),
      'new ctx',
    );
    await tester.tap(find.byKey(const Key('readerEditVocabSave')));
    await tester.pumpAndSettle();

    final list = await dictionary.list();
    expect(list, hasLength(1));
    expect(list.single.lemma, 'hello');
    expect(list.single.translation, 'new tr');
    expect(list.single.context, 'new ctx');
  });

  // --- reader/highlight (RH-*) ---

  testWidgets('RH-01 / RH-02 / RH-09: Marked wordforms use lemmaHighlight', (
    tester,
  ) async {
    await dictionary.add(
      lemma: 'run',
      surfaceKey: 'run',
      translation: 'бежать',
    );
    final mark = _FakeMark();
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['running and other'],
      ),
    ];
    pumpTokenize = _tokenizeWithMorphLemmas;
    pumpMark = mark.call;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    expect(mark.callCount, greaterThanOrEqualTo(1));
    expect(mark.lastVocabLemmas, contains('run'));

    final highlight = ReaderColors.light.lemmaHighlight;
    expect(
      _tokenBackground(tester, const Key('readerCueToken_0_0')),
      highlight,
    );
    // "and" / "other" stay default (no highlight fill).
    expect(
      _tokenBackground(tester, const Key('readerCueToken_0_1')),
      isNot(highlight),
    );
    expect(
      _tokenBackground(tester, const Key('readerCueToken_0_2')),
      isNot(highlight),
    );
  });

  testWidgets('RH-08: Phrase entry highlights all span tokens', (tester) async {
    await dictionary.add(
      lemma: 'hello world',
      surfaceKey: 'hello world',
      translation: 'привет мир',
    );
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['hello world other'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    final highlight = ReaderColors.light.lemmaHighlight;
    expect(
      _tokenBackground(tester, const Key('readerCueToken_0_0')),
      highlight,
    );
    expect(
      _tokenBackground(tester, const Key('readerCueToken_0_1')),
      highlight,
    );
    expect(
      _tokenBackground(tester, const Key('readerCueToken_0_2')),
      isNot(highlight),
    );
  });

  testWidgets('RH-13: Overlapping phrases both paint', (tester) async {
    await dictionary.add(
      lemma: 'a b',
      surfaceKey: 'a b',
      translation: 'ab',
    );
    await dictionary.add(
      lemma: 'b c',
      surfaceKey: 'b c',
      translation: 'bc',
    );
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['a b c'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    final highlight = ReaderColors.light.lemmaHighlight;
    expect(
      _tokenBackground(tester, const Key('readerCueToken_0_0')),
      highlight,
    );
    expect(
      _tokenBackground(tester, const Key('readerCueToken_0_1')),
      highlight,
    );
    expect(
      _tokenBackground(tester, const Key('readerCueToken_0_2')),
      highlight,
    );
  });

  testWidgets('RH-05 longest phrase: overlap tap opens longest entry', (
    tester,
  ) async {
    await dictionary.add(
      lemma: 'look',
      surfaceKey: 'look',
      translation: 'смотреть',
    );
    await dictionary.add(
      lemma: 'look up',
      surfaceKey: 'look up',
      translation: 'искать',
    );
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['look up'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerEditVocabSheet')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('readerEditVocabLemma')),
        matching: find.text('look up'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('readerAddVocabCta')), findsNothing);
  });

  testWidgets('RH-03: Refresh highlight after Add save', (tester) async {
    final mark = _FakeMark();
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['hello world'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    pumpMark = mark.call;
    await pumpReader(tester);
    await tester.pumpAndSettle();
    final callsAfterOpen = mark.callCount;

    expect(
      _tokenBackground(tester, const Key('readerCueToken_0_0')),
      isNot(ReaderColors.light.lemmaHighlight),
    );

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerAddVocabCta')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('readerAddVocabTranslation')),
      'привет',
    );
    await tester.tap(find.byKey(const Key('readerAddVocabSave')));
    await tester.pumpAndSettle();

    expect(mark.callCount, greaterThan(callsAfterOpen));
    expect(
      _tokenBackground(tester, const Key('readerCueToken_0_0')),
      ReaderColors.light.lemmaHighlight,
    );
  });

  testWidgets('RH-05 / RT-15: Tap in_vocab opens edit sheet, no Add CTA', (
    tester,
  ) async {
    await dictionary.add(
      lemma: 'hello',
      surfaceKey: 'hello',
      translation: 'привет',
      context: 'ctx',
    );
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['hello world'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('readerAddVocabCta')), findsNothing);
    expect(find.byKey(const Key('readerEditVocabSheet')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('readerEditVocabLemma')),
        matching: find.text('hello'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('readerEditVocabSurface')),
        matching: find.text('hello'),
      ),
      findsOneWidget,
    );
    final translation = tester.widget<TextField>(
      find.byKey(const Key('readerEditVocabTranslation')),
    );
    expect(translation.controller!.text, 'привет');
  });

  testWidgets('RH-04 / RH-07: Edit delete clears highlight via re-mark', (
    tester,
  ) async {
    await dictionary.add(
      lemma: 'hello',
      surfaceKey: 'hello',
      translation: 'привет',
    );
    final mark = _FakeMark();
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['hello world'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    pumpMark = mark.call;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    expect(
      _tokenBackground(tester, const Key('readerCueToken_0_0')),
      ReaderColors.light.lemmaHighlight,
    );

    await tester.tap(find.byKey(const Key('readerCueToken_0_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('readerEditVocabDelete')));
    await tester.pumpAndSettle();

    expect(await dictionary.lookup('hello'), isNull);
    expect(
      _tokenBackground(tester, const Key('readerCueToken_0_0')),
      isNot(ReaderColors.light.lemmaHighlight),
    );
    expect(mark.callCount, greaterThanOrEqualTo(2));
  });

  testWidgets('RH-12: Translation pane has no vocab highlight UX', (
    tester,
  ) async {
    await dictionary.add(
      lemma: 'hello',
      surfaceKey: 'hello',
      translation: 'привет',
    );
    pumpCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['hello world'],
      ),
    ];
    pumpTranslationCues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(0),
        endMs: BigInt.from(1000),
        textLines: ['hello world'],
      ),
    ];
    pumpTokenize = _tokenizeFromTexts;
    await pumpReader(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('readerSplitToggle')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('readerTranslationCueList')),
        matching: find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('readerCueToken_'),
        ),
      ),
      findsNothing,
    );
  });
}
