import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/app/theme.dart';
import 'package:my_translator_app/data/video/video_frame_extractor.dart';
import 'package:my_translator_app/features/reader/cue_time_format.dart';
import 'package:my_translator_app/features/reader/video_frame_cache.dart';
import 'package:my_translator_app/features/reader/video_second_timeline.dart';
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

/// Fixed pumps — avoid [pumpAndSettle] with ScrollablePositionedList + loaders.
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}

void main() {
  testWidgets('VF-01/VF-02: vertical second rows (not 3-across strip)', (
    tester,
  ) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
    final cache = MemoryVideoFrameCache();
    final key = GlobalKey<VideoSecondTimelineState>();

    await tester.pumpWidget(
      _wrap(
        VideoSecondTimeline(
          key: key,
          videoRef: '/tmp/vid.mp4',
          totalSeconds: 5,
          originalCues: const [],
          extractor: extractor,
          cache: cache,
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byKey(const Key('videoSecondTimeline')), findsOneWidget);
    expect(find.byKey(const Key('videoFrameStrip')), findsNothing);
    expect(key.currentState!.secondCount, 5);

    // Vertical rows for early seconds (virtualized — at least 0 present).
    expect(find.byKey(const Key('videoSecondRow_0')), findsOneWidget);
    expect(find.byKey(const Key('videoSecondTimestamp_0')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('videoSecondTimestamp_0'))).data,
      formatCueTimestamp(BigInt.zero),
    );

    // No pager chrome from the old 3-slot strip.
    expect(find.byKey(const Key('videoFrameStripCounter')), findsNothing);
    expect(find.byKey(const Key('videoFrameStripNext')), findsNothing);
  });

  testWidgets('VF-03: empty cue text still shows frame row', (tester) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);

    await tester.pumpWidget(
      _wrap(
        VideoSecondTimeline(
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
    await _pumpFrames(tester);

    expect(find.byKey(const Key('videoSecondRow_0')), findsOneWidget);
    expect(find.byKey(const Key('videoSecondImage_0')), findsOneWidget);
    final text0 = tester.widget<Text>(
      find.byKey(const Key('videoSecondText_0')),
    );
    expect(text0.data, '');
    expect(find.textContaining('error', findRichText: true), findsNothing);
  });

  testWidgets('VF-04: cue text under frame when interval covers second', (
    tester,
  ) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);

    await tester.pumpWidget(
      _wrap(
        VideoSecondTimeline(
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
    await _pumpFrames(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('videoSecondText_0'))).data,
      '',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('videoSecondText_1'))).data,
      'Hello\nworld',
    );
  });

  testWidgets('VF-05 math: jumpToSecond scrolls near reading time', (
    tester,
  ) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
    final key = GlobalKey<VideoSecondTimelineState>();

    await tester.pumpWidget(
      _wrap(
        VideoSecondTimeline(
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

    expect(key.currentState!.currentSecond, 60);
    expect(find.byKey(const Key('videoSecondRow_60')), findsOneWidget);
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
        VideoSecondTimeline(
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
      find.byKey(const Key('videoSecondPlaceholder_1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('videoSecondImage_0')), findsOneWidget);
    expect(find.byKey(const Key('videoSecondTimeline')), findsOneWidget);
  });

  testWidgets('uses cache and skips re-extract on revisit', (tester) async {
    final extractor = FakeVideoFrameExtractor(jpegBytes: _tinyJpeg);
    final cache = MemoryVideoFrameCache();
    final key = GlobalKey<VideoSecondTimelineState>();

    await tester.pumpWidget(
      _wrap(
        VideoSecondTimeline(
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
    expect(firstCount, greaterThan(0));

    key.currentState!.jumpToSecond(8);
    await _pumpFrames(tester);
    final midCount = extractor.extractCalls.length;
    expect(midCount, greaterThan(firstCount));

    key.currentState!.jumpToSecond(0);
    await _pumpFrames(tester);
    // Revisiting second 0 should hit cache, not re-extract those seconds.
    final revisited = extractor.extractCalls.where((c) => c.$2 == 0).length;
    expect(revisited, 1);
    expect(cache.entries.containsKey(0), isTrue);
  });
}
