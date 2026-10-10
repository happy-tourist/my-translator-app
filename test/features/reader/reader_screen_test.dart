import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/features/reader/cue_time_format.dart';
import 'package:my_translator_app/features/reader/reader_screen.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';

List<CueDto> _sampleCues({int count = 3}) {
  return List.generate(count, (i) {
    final start = BigInt.from(i * 1500);
    final end = BigInt.from(i * 1500 + 1000);
    return CueDto(
      index: i,
      startMs: start,
      endMs: end,
      textLines: ['Cue line $i'],
    );
  });
}

void main() {
  test('formatCueTimestamp zero-pads HH:MM:SS,mmm', () {
    expect(formatCueTimestamp(BigInt.from(0)), '00:00:00,000');
    expect(formatCueTimestamp(BigInt.from(3661001)), '01:01:01,001');
    expect(formatCueTimestamp(BigInt.from(61)), '00:00:00,061');
  });

  testWidgets('RC-01: Open Reader with cue list', (tester) async {
    final cues = _sampleCues();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(title: 'episode1', cues: cues),
      ),
    );
    expect(find.byKey(const Key('readerScreen')), findsOneWidget);
    expect(find.byKey(const Key('readerCueList')), findsOneWidget);
    expect(find.byKey(const Key('readerCue_0')), findsOneWidget);
    expect(find.byKey(const Key('readerCue_1')), findsOneWidget);
    expect(find.byKey(const Key('readerCue_2')), findsOneWidget);
    expect(find.text('Cue line 0'), findsOneWidget);
    expect(find.text('episode1'), findsOneWidget);
  });

  testWidgets('RC-02: Show start and end times per cue', (tester) async {
    final cues = [
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
    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(title: 'doc', cues: cues)),
    );
    expect(find.text('00:00:01,000 → 00:00:02,500'), findsOneWidget);
    expect(find.text('01:01:01,001 → 01:01:02,002'), findsOneWidget);
  });

  testWidgets('RC-01: Multi-line cue text shows all text_lines', (tester) async {
    final cues = [
      CueDto(
        index: 0,
        startMs: BigInt.from(1000),
        endMs: BigInt.from(2000),
        textLines: ['Line one', 'Line two', 'Line three'],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(title: 'doc', cues: cues)),
    );
    expect(find.text('Line one\nLine two\nLine three'), findsOneWidget);
  });

  testWidgets('RC-03: Scroll through all cues', (tester) async {
    final cues = _sampleCues(count: 40);
    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(title: 'long', cues: cues)),
    );
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
                          cues: _sampleCues(count: 1),
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
}
