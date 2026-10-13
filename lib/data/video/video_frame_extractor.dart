import 'dart:typed_data';

/// Platform-agnostic video frame extract facade (design D2).
///
/// Native: FFmpegKit over a filesystem path. Web: canvas seek (block 3).
/// [ref] is a usable filesystem path on native, or a platform blob/handle id on web.
abstract class VideoFrameExtractor {
  /// Probe media duration for [ref].
  Future<Duration> probeDuration(String ref);

  /// Extract one JPEG frame at whole-second [second] (0-based).
  Future<Uint8List> extractJpegAtSecond(String ref, int second);
}

/// Injectable fake for widget/unit tests (no FFmpeg / canvas).
class FakeVideoFrameExtractor implements VideoFrameExtractor {
  FakeVideoFrameExtractor({
    this.duration = const Duration(seconds: 9),
    this.jpegBytes,
    this.failSeconds = const {},
    this.probeError,
  });

  Duration duration;
  Uint8List? jpegBytes;
  Set<int> failSeconds;
  Object? probeError;

  final List<(String, int)> extractCalls = [];
  final List<String> probeCalls = [];

  @override
  Future<Duration> probeDuration(String ref) async {
    probeCalls.add(ref);
    final err = probeError;
    if (err != null) {
      throw err;
    }
    return duration;
  }

  @override
  Future<Uint8List> extractJpegAtSecond(String ref, int second) async {
    extractCalls.add((ref, second));
    if (failSeconds.contains(second)) {
      throw StateError('Fake extract failed at second $second');
    }
    return jpegBytes ?? Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]);
  }
}
