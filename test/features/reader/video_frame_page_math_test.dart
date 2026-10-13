import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/features/reader/video_second_math.dart';

void main() {
  group('VF-02: videoFrameSecondsForPage', () {
    test('page 1 shows seconds 0, 1, 2 when duration >= 9', () {
      expect(videoFrameSecondsForPage(1, 9), [0, 1, 2]);
    });

    test('page 2 shows seconds 3, 4, 5', () {
      expect(videoFrameSecondsForPage(2, 9), [3, 4, 5]);
    });

    test('page 3 shows seconds 6, 7, 8', () {
      expect(videoFrameSecondsForPage(3, 9), [6, 7, 8]);
    });

    test('last page may have fewer than three slots', () {
      expect(videoFrameSecondsForPage(3, 7), [6]);
      expect(videoFrameSecondsForPage(2, 4), [3]);
      expect(videoFrameSecondsForPage(1, 2), [0, 1]);
    });

    test('out-of-range page returns empty', () {
      expect(videoFrameSecondsForPage(0, 9), isEmpty);
      expect(videoFrameSecondsForPage(4, 9), isEmpty);
      expect(videoFrameSecondsForPage(1, 0), isEmpty);
    });
  });

  group('videoFramePageCount', () {
    test('ceil(totalSeconds / 3) for totalSeconds >= 1', () {
      expect(videoFramePageCount(1), 1);
      expect(videoFramePageCount(3), 1);
      expect(videoFramePageCount(4), 2);
      expect(videoFramePageCount(9), 3);
      expect(videoFramePageCount(10), 4);
    });

    test('returns 0 when totalSeconds < 1', () {
      expect(videoFramePageCount(0), 0);
      expect(videoFramePageCount(-1), 0);
    });
  });

  test('videoFramePageFirstSecond anchors sync time', () {
    expect(videoFramePageFirstSecond(1, 9), 0);
    expect(videoFramePageFirstSecond(2, 9), 3);
    expect(videoFramePageFirstSecond(3, 7), 6);
    expect(videoFramePageFirstSecond(1, 0), -1);
  });

  group('VF-05: page containing reading second', () {
    test('videoFramePageForSecond maps second → 1-based page', () {
      expect(videoFramePageForSecond(0, 9), 1);
      expect(videoFramePageForSecond(2, 9), 1);
      expect(videoFramePageForSecond(3, 9), 2);
      expect(videoFramePageForSecond(600, 3600), 201);
      expect(videoFramePageForSecond(45, 90), 16);
    });

    test('clampReadingTimeToPage uses floor(ms/1000)', () {
      expect(clampReadingTimeToPage(600_000, 3600), 201);
      expect(clampReadingTimeToPage(0, 90), 1);
      expect(clampReadingTimeToPage(1500, 90), 1);
      expect(clampReadingTimeToPage(3000, 90), 2);
    });
  });
}
