import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/features/reader/video_second_math.dart';

void main() {
  group('VF-05: clampReadingTimeToSecond', () {
    test('floor(readingTimeMs/1000) into [0, durationSeconds-1]', () {
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

  group('VF-05: clampReadingTimeToPage', () {
    test('maps clamped second to 1-based page of 3', () {
      expect(clampReadingTimeToPage(0, 90), 1);
      expect(clampReadingTimeToPage(1500, 90), 1);
      expect(clampReadingTimeToPage(3000, 90), 2);
      expect(clampReadingTimeToPage(600_000, 3600), 201);
    });
  });
}
