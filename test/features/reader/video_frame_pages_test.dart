import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/app/theme.dart';
import 'package:my_translator_app/data/video/video_frame_extractor.dart';
import 'package:my_translator_app/features/reader/cue_row.dart';
import 'package:my_translator_app/features/reader/cue_text_at_second.dart';
import 'package:my_translator_app/features/reader/cue_time_format.dart';
import 'package:my_translator_app/features/reader/video_frame_cache.dart';
import 'package:my_translator_app/features/reader/video_frame_pages.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';

/// Valid 1×1 JPEG so [Image.memory] does not fall through to errorBuilder.
final Uint8List _tinyJpeg = Uint8List.fromList(
  base64Decode(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkS'
    'Ew8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJ'
    'CQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy'
    'MjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAA'
    'AAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAA'
    'AAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAA8A/9k=',
  ),
);

CueDto _cue({
  required int index,
  required int startMs,
  required int endMs,
  required List<String> lines,
}) {
  return CueDto(
    index: index,
    startMs: BigInt.from(startMs),
    endMs: BigInt.from(endMs),
    textLines: lines,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SizedBox(
        height: 800,
        width: 400,
        child: child,
      ),
    ),
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}

/// Reader-like under-frame embed: CueRow + file timestamps (VF-03/VF-04).
Widget Function(BuildContext, int, String) _readerLikeCueText(
  List<CueDto> cues,
) {
  return (context, second, cueText) {
    final indices = cueIndicesAtEndSecond(cues, second);
    if (indices.isEmpty) {
      return Text(
        cueText,
        key: Key('videoFrameSlotText_$second'),
      );
    }
    return KeyedSubtree(
      key: Key('videoFrameSlotText_$second'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final i in indices)
            CueRow(
              cue: cues[i],
              cueListIndex: i,
              showTimestamp: true,
              padding: EdgeInsets.zero,
              keySuffix: 's$second',
            ),
        ],
      ),
    );
  };
}

void main() {
  testWidgets('VF-01/VF-02: column of 3 + pager (not infinite / strip)', (
    tester,
  ) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
    final cache = MemoryVideoFrameCache();
    final key = GlobalKey<VideoFramePagesState>();

    await tester.pumpWidget(
      _wrap(
        VideoFramePages(
          key: key,
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 9,
          originalCues: const [],
          extractor: extractor,
          cache: cache,
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byKey(const Key('videoFramePages')), findsOneWidget);
    expect(find.byKey(const Key('videoSecondTimeline')), findsNothing);
    expect(find.byKey(const Key('videoFrameStrip')), findsNothing);
    expect(key.currentState!.pageCount, 3);
    expect(find.byKey(const Key('videoFrameSlot_0')), findsOneWidget);
    expect(find.byKey(const Key('videoFrameSlot_1')), findsOneWidget);
    expect(find.byKey(const Key('videoFrameSlot_2')), findsOneWidget);
    expect(find.byKey(const Key('videoFramePagesCounter')), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    // Empty slots: no invented frame-second timestamp keys.
    expect(find.byKey(const Key('videoSecondTimestamp_0')), findsNothing);
    expect(extractor.extractCalls.map((c) => c.$2).toList(), [0, 1, 2]);
  });

  testWidgets('VF-14: pager chrome is below the frame list', (tester) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);

    await tester.pumpWidget(
      _wrap(
        VideoFramePages(
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 9,
          originalCues: const [],
          extractor: extractor,
          cache: MemoryVideoFrameCache(),
        ),
      ),
    );
    await _pumpFrames(tester);

    final slotTop = tester.getTopLeft(find.byKey(const Key('videoFrameSlot_0'))).dy;
    final pagerTop =
        tester.getTopLeft(find.byKey(const Key('videoFramePagesCounter'))).dy;
    expect(pagerTop, greaterThan(slotTop));
    final nextTop =
        tester.getTopLeft(find.byKey(const Key('videoFramePagesNext'))).dy;
    expect(nextTop, greaterThan(slotTop));
  });

  testWidgets('VF-15: page change scrolls frame list to first slot', (
    tester,
  ) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
    final key = GlobalKey<VideoFramePagesState>();

    // Short viewport so three 16:9 slots overflow and can scroll (VF-15).
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            height: 280,
            width: 400,
            child: VideoFramePages(
              key: key,
              videoRef: '/tmp/vid.mp4',
              totalSeconds: 9,
              originalCues: const [],
              extractor: extractor,
              cache: MemoryVideoFrameCache(),
            ),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    // Scroll down within the current page so offset is non-zero.
    final controller = key.currentState!.listScrollController;
    expect(controller.hasClients, isTrue);
    expect(controller.position.maxScrollExtent, greaterThan(0));
    controller.jumpTo(120);
    await tester.pump();
    expect(controller.offset, greaterThan(0));

    await tester.tap(find.byKey(const Key('videoFramePagesNext')));
    await _pumpFrames(tester);

    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byKey(const Key('videoFrameSlot_3')), findsOneWidget);
    expect(controller.offset, 0);
  });

  testWidgets('VF-02: pager advances to next page of three', (tester) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
    final pages = <int>[];

    await tester.pumpWidget(
      _wrap(
        VideoFramePages(
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 9,
          originalCues: const [],
          extractor: extractor,
          cache: MemoryVideoFrameCache(),
          onPageChanged: pages.add,
        ),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(find.byKey(const Key('videoFramePagesNext')));
    await _pumpFrames(tester);

    expect(find.text('2 / 3'), findsOneWidget);
    expect(pages, [2]);
    expect(find.byKey(const Key('videoFrameSlot_3')), findsOneWidget);
    expect(find.byKey(const Key('videoFrameSlot_0')), findsNothing);
  });

  testWidgets('VF-03: empty cue text still shows frame; no timestamp', (
    tester,
  ) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
    final cues = [
      _cue(index: 0, startMs: 5000, endMs: 6000, lines: ['later']),
    ];

    await tester.pumpWidget(
      _wrap(
        VideoFramePages(
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 3,
          originalCues: cues,
          extractor: extractor,
          cache: MemoryVideoFrameCache(),
          buildCueText: _readerLikeCueText(cues),
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byKey(const Key('videoFrameSlot_0')), findsOneWidget);
    expect(find.byKey(const Key('videoFrameSlotImage_0')), findsOneWidget);
    final text0 = tester.widget<Text>(
      find.byKey(const Key('videoFrameSlotText_0')),
    );
    expect(text0.data, '');
    expect(find.byKey(const Key('videoSecondTimestamp_0')), findsNothing);
    expect(find.byKey(const Key('readerCueTime_0_s0')), findsNothing);
    expect(find.byKey(const Key('readerCueTime_0_s1')), findsNothing);
    expect(find.byKey(const Key('readerCueTime_0_s2')), findsNothing);
  });

  testWidgets('VF-04: cue text under rounded end second only', (tester) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);

    await tester.pumpWidget(
      _wrap(
        VideoFramePages(
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 6,
          originalCues: [
            _cue(
              index: 0,
              startMs: 1000,
              endMs: 2500,
              lines: ['Hello', 'world'],
            ),
          ],
          extractor: extractor,
          cache: MemoryVideoFrameCache(),
        ),
      ),
    );
    await _pumpFrames(tester);

    // round(2500/1000)=3 → only under second 3 (page 2).
    expect(
      tester.widget<Text>(find.byKey(const Key('videoFrameSlotText_0'))).data,
      '',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('videoFrameSlotText_1'))).data,
      '',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('videoFrameSlotText_2'))).data,
      '',
    );

    await tester.tap(find.byKey(const Key('videoFramePagesNext')));
    await _pumpFrames(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('videoFrameSlotText_3'))).data,
      'Hello\nworld',
    );
  });

  testWidgets(
    'VF-04: CueRow under frame shows file start→end timestamps',
    (tester) async {
      final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
      final cues = [
        _cue(
          index: 0,
          startMs: 1000,
          endMs: 2500,
          lines: ['Hello', 'world'],
        ),
      ];
      final expectedTime =
          '${formatCueTimestamp(BigInt.from(1000))} → '
          '${formatCueTimestamp(BigInt.from(2500))}';

      await tester.pumpWidget(
        _wrap(
          VideoFramePages(
            videoRef: '/tmp/vid.mp4',
            totalSeconds: 6,
            originalCues: cues,
            extractor: extractor,
            cache: MemoryVideoFrameCache(),
            buildCueText: _readerLikeCueText(cues),
          ),
        ),
      );
      await _pumpFrames(tester);

      // Empty slots on page 1: no CueRow time keys.
      expect(find.byKey(const Key('readerCueTime_0_s0')), findsNothing);
      expect(find.byKey(const Key('readerCueTime_0_s1')), findsNothing);
      expect(find.byKey(const Key('readerCueTime_0_s2')), findsNothing);

      await tester.tap(find.byKey(const Key('videoFramePagesNext')));
      await _pumpFrames(tester);

      expect(find.byKey(const Key('readerCueTime_0_s3')), findsOneWidget);
      expect(find.text(expectedTime), findsOneWidget);
      expect(find.text('Hello\nworld'), findsOneWidget);
    },
  );

  testWidgets('VF-04: multi-cue same end second shows each file timestamp', (
    tester,
  ) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
    final cues = [
      _cue(index: 0, startMs: 0, endMs: 2000, lines: ['first']),
      _cue(index: 1, startMs: 500, endMs: 2100, lines: ['second']),
    ];
    final time0 =
        '${formatCueTimestamp(BigInt.from(0))} → '
        '${formatCueTimestamp(BigInt.from(2000))}';
    final time1 =
        '${formatCueTimestamp(BigInt.from(500))} → '
        '${formatCueTimestamp(BigInt.from(2100))}';

    await tester.pumpWidget(
      _wrap(
        VideoFramePages(
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 3,
          originalCues: cues,
          extractor: extractor,
          cache: MemoryVideoFrameCache(),
          buildCueText: _readerLikeCueText(cues),
        ),
      ),
    );
    await _pumpFrames(tester);

    // round(2000/1000)=2 and round(2100/1000)=2 → both under second 2.
    expect(find.byKey(const Key('videoFrameSlotText_0')), findsOneWidget);
    expect(find.byKey(const Key('readerCueTime_0_s0')), findsNothing);
    expect(find.byKey(const Key('readerCueTime_0_s1')), findsNothing);
    expect(find.byKey(const Key('readerCueTime_0_s2')), findsOneWidget);
    expect(find.byKey(const Key('readerCueTime_1_s2')), findsOneWidget);
    expect(find.text(time0), findsOneWidget);
    expect(find.text(time1), findsOneWidget);
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('VF-05: jumpToSecond opens page containing second', (
    tester,
  ) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
    final key = GlobalKey<VideoFramePagesState>();

    await tester.pumpWidget(
      _wrap(
        VideoFramePages(
          key: key,
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 90,
          originalCues: const [],
          extractor: extractor,
          cache: MemoryVideoFrameCache(),
          initialSecond: 0,
        ),
      ),
    );
    await _pumpFrames(tester);

    key.currentState!.jumpToSecond(60);
    await _pumpFrames(tester);

    expect(key.currentState!.currentPage, 21); // seconds 60..62
    expect(key.currentState!.currentSecond, 60);
    expect(find.byKey(const Key('videoFrameSlot_60')), findsOneWidget);
  });

  testWidgets('VF-10: failed extract shows placeholder; neighbors ok', (
    tester,
  ) async {
    final extractor = FakeVideoFrameExtractor(
      jpegBytes: _tinyJpeg,
      failSeconds: {1},
    );

    await tester.pumpWidget(
      _wrap(
        VideoFramePages(
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 3,
          originalCues: const [],
          extractor: extractor,
          cache: MemoryVideoFrameCache(),
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(
      find.byKey(const Key('videoFrameSlotPlaceholder_1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('videoFrameSlotImage_0')), findsOneWidget);
    expect(find.byKey(const Key('videoFramePages')), findsOneWidget);
  });

  testWidgets('uses cache and skips re-extract on revisit', (tester) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
    final cache = MemoryVideoFrameCache();
    final key = GlobalKey<VideoFramePagesState>();

    await tester.pumpWidget(
      _wrap(
        VideoFramePages(
          key: key,
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 12,
          originalCues: const [],
          extractor: extractor,
          cache: cache,
        ),
      ),
    );
    await _pumpFrames(tester);
    final firstCount = extractor.extractCalls.length;
    expect(firstCount, 3);

    key.currentState!.goToPage(3);
    await _pumpFrames(tester);
    expect(extractor.extractCalls.length, greaterThan(firstCount));

    key.currentState!.goToPage(1);
    await _pumpFrames(tester);
    final revisited = extractor.extractCalls.where((c) => c.$2 == 0).length;
    expect(revisited, 1);
    expect(cache.entries.containsKey(0), isTrue);
  });
}
