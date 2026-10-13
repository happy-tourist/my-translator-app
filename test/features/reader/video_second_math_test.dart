import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/features/reader/video_second_math.dart';

void main() {
  group('VF-02: videoTimelineSecondCount', () {
    test('duration N sec → N rows for seconds 0..N-1', () {
      expect(videoTimelineSecondCount(3), 3);
      expect(videoTimelineSecondCount(9), 9);
      expect(videoTimelineSecondCount(1), 1);
      expect(isValidTimelineSecond(0, 3), isTrue);
      expect(isValidTimelineSecond(2, 3), isTrue);
      expect(isValidTimelineSecond(3, 3), isFalse);
      expect(isValidTimelineSecond(-1, 3), isFalse);
    });

    test('returns 0 when durationSeconds < 1 (VF-11)', () {
      expect(videoTimelineSecondCount(0), 0);
      expect(videoTimelineSecondCount(-1), 0);
      expect(isValidTimelineSecond(0, 0), isFalse);
    });
  });

  group('VF-05: clampReadingTimeToSecond', () {
    test('floor(readingTimeMs/1000) into [0, durationSeconds-1]', () {
      // ~10 minutes → second 600
      expect(clampReadingTimeToSecond(600_000, 3600), 600);
      expect(clampReadingTimeToSecond(600_999, 3600), 600);
      expect(clampReadingTimeToSecond(0, 90), 0);
      expect(clampReadingTimeToSecond(1500, 90), 1);
    });

    test('clamps below 0 and at/above duration', () {
      expect(clampReadingTimeToSecond(-500, 10), 0);
      expect(clampReadingTimeToSecond(9_999, 10), 9);
      expect(clampReadingTimeToSecond(10_000, 10), 9);
      expect(clampReadingTimeToSecond(1_000_000, 10), 9);
    });

    test('returns -1 when durationSeconds < 1', () {
      expect(clampReadingTimeToSecond(5000, 0), -1);
      expect(clampReadingTimeToSecond(5000, -2), -1);
    });
  });
}
