import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/app/theme.dart';
import 'package:my_translator_app/data/video/video_frame_extractor.dart';
import 'package:my_translator_app/features/reader/video_frame_cache.dart';
import 'package:my_translator_app/features/reader/video_frame_strip.dart';
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
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('VF-01/VF-02: strip shows three slots for seconds 0–2', (
    tester,
  ) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
    final cache = MemoryVideoFrameCache();

    await tester.pumpWidget(
      _wrap(
        VideoFrameStrip(
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 9,
          originalCues: const [],
          extractor: extractor,
          cache: cache,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('videoFrameStrip')), findsOneWidget);
    expect(find.byKey(const Key('videoFrameSlot_0')), findsOneWidget);
    expect(find.byKey(const Key('videoFrameSlot_1')), findsOneWidget);
    expect(find.byKey(const Key('videoFrameSlot_2')), findsOneWidget);
    expect(find.byKey(const Key('videoFrameStripCounter')), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(extractor.extractCalls.map((c) => c.$2).toList(), [0, 1, 2]);
  });

  testWidgets('VF-03: pager advances and updates counter', (tester) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
    final cache = MemoryVideoFrameCache();
    final pages = <int>[];

    await tester.pumpWidget(
      _wrap(
        VideoFrameStrip(
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 9,
          originalCues: const [],
          extractor: extractor,
          cache: cache,
          onPageChanged: pages.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('videoFrameStripNext')));
    await tester.pumpAndSettle();

    expect(find.text('2 / 3'), findsOneWidget);
    expect(pages, [2]);
    expect(
      extractor.extractCalls.map((c) => c.$2).toSet(),
      containsAll([0, 1, 2, 3, 4, 5]),
    );

    await tester.tap(find.byKey(const Key('videoFrameStripNext')));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('videoFrameStripPrev')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('VF-05: empty cue text under slot is allowed', (tester) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);

    await tester.pumpWidget(
      _wrap(
        VideoFrameStrip(
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 3,
          originalCues: [
            _cue(index: 0, startMs: 5000, endMs: 6000, lines: ['later']),
          ],
          extractor: extractor,
          cache: MemoryVideoFrameCache(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final text0 = tester.widget<Text>(
      find.byKey(const Key('videoFrameSlotText_0')),
    );
    expect(text0.data, '');
    expect(find.textContaining('error', findRichText: true), findsNothing);
  });

  testWidgets('VF-04: cue text shown when interval covers second', (
    tester,
  ) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);

    await tester.pumpWidget(
      _wrap(
        VideoFrameStrip(
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 3,
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
    await tester.pumpAndSettle();

    // startMs=1000,endMs=2500 covers seconds 1 and 2, not 0.
    expect(
      tester.widget<Text>(find.byKey(const Key('videoFrameSlotText_0'))).data,
      '',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('videoFrameSlotText_1'))).data,
      'Hello\nworld',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('videoFrameSlotText_2'))).data,
      'Hello\nworld',
    );
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
        VideoFrameStrip(
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 3,
          originalCues: const [],
          extractor: extractor,
          cache: MemoryVideoFrameCache(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('videoFrameSlotPlaceholder_1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('videoFrameSlotImage_0')), findsOneWidget);
    expect(find.byKey(const Key('videoFrameSlotImage_2')), findsOneWidget);
    expect(find.byKey(const Key('videoFrameStrip')), findsOneWidget);
  });

  testWidgets('uses cache and skips re-extract on revisit', (tester) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
    final cache = MemoryVideoFrameCache();

    await tester.pumpWidget(
      _wrap(
        VideoFrameStrip(
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 6,
          originalCues: const [],
          extractor: extractor,
          cache: cache,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final firstCount = extractor.extractCalls.length;

    await tester.tap(find.byKey(const Key('videoFrameStripNext')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('videoFrameStripPrev')));
    await tester.pumpAndSettle();

    expect(extractor.extractCalls.length, firstCount + 3);
    expect(cache.entries.keys, containsAll([0, 1, 2, 3, 4, 5]));
  });
}
