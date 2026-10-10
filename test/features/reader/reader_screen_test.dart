import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/data/library/parse_subtitles_fn.dart';
import 'package:my_translator_app/features/reader/cue_time_format.dart';
import 'package:my_translator_app/features/reader/nearest_cue_index.dart';
import 'package:my_translator_app/features/reader/reader_screen.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';

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

void main() {
  late final db = createTestDatabase();
  late MemoryDocumentContentStore store;
  late FolderRepository folders;
  late DocumentRepository documents;

  // Pump-helper overrides (skill: scenario via mutable fields, not ad-hoc trees).
  late List<CueDto> pumpCues;
  late String pumpTitle;
  late int pumpOriginalDocumentId;
  List<CueDto>? pumpTranslationCues;
  int? pumpTranslationDocumentId;
  ReadingAnchor? pumpInitialReadingAnchor;
  ParseSubtitlesFn? pumpParse;
  ReaderTranslationPicker? pumpPicker;

  setUp(() {
    store = MemoryDocumentContentStore();
    folders = FolderRepository(db, contentStore: store);
    documents = DocumentRepository(db, contentStore: store);
    pumpCues = _sampleCues();
    pumpTitle = 'doc';
    pumpOriginalDocumentId = 1;
    pumpTranslationCues = null;
    pumpTranslationDocumentId = null;
    pumpInitialReadingAnchor = null;
    pumpParse = null;
    pumpPicker = null;
  });

  tearDown(() async {
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
        home: ReaderScreen(
          title: pumpTitle,
          originalCues: pumpCues,
          originalDocumentId: pumpOriginalDocumentId,
          documentRepository: documents,
          translationCues: pumpTranslationCues,
          translationDocumentId: pumpTranslationDocumentId,
          initialReadingAnchor: pumpInitialReadingAnchor,
          parseSubtitles: pumpParse,
          filePicker: pumpPicker,
        ),
      ),
    );
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
}
