import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'video_frame_errors.dart';
import 'video_frame_extractor.dart';
import 'video_usable_path.dart';

/// Native backend: FFmpegKit over a usable filesystem path (design D2 / D3).
///
/// Package: `ffmpeg_kit_flutter_new_video` (pub.dev video pack — D3 fallback).
/// Never passes raw `content://` to FFmpeg — call [resolveUsableVideoPath] first.
VideoFrameExtractor createVideoFrameExtractor() => NativeFfmpegFrameExtractor();

/// Probe + JPEG-at-second via FFprobeKit / FFmpegKit.
class NativeFfmpegFrameExtractor implements VideoFrameExtractor {
  NativeFfmpegFrameExtractor();

  @override
  Future<Duration> probeDuration(String ref) async {
    _ensureUsableFilesystemPath(ref);
    try {
      final session = await FFprobeKit.getMediaInformation(ref);
      final info = session.getMediaInformation();
      final durationStr = info?.getDuration();
      if (durationStr == null || durationStr.isEmpty) {
        throw const VideoFrameException(VideoFrameErrorKind.probeFailed);
      }
      final seconds = double.tryParse(durationStr);
      if (seconds == null ||
          seconds.isNaN ||
          seconds.isInfinite ||
          seconds <= 0) {
        throw const VideoFrameException(VideoFrameErrorKind.probeFailed);
      }
      return Duration(milliseconds: (seconds * 1000).round());
    } on VideoFrameException {
      rethrow;
    } catch (e, st) {
      assert(() {
        debugPrint('NativeFfmpegFrameExtractor.probeDuration: $e\n$st');
        return true;
      }());
      throw const VideoFrameException(VideoFrameErrorKind.probeFailed);
    }
  }

  @override
  Future<Uint8List> extractJpegAtSecond(String ref, int second) async {
    _ensureUsableFilesystemPath(ref);
    if (second < 0) {
      throw const VideoFrameException(VideoFrameErrorKind.extractFailed);
    }

    final tempDir = await getTemporaryDirectory();
    final outPath = p.join(
      tempDir.path,
      'vf_${DateTime.now().microsecondsSinceEpoch}_$second.jpg',
    );
    final outFile = File(outPath);

    try {
      // Design D2: `-ss <sec> -i <path> -frames:v 1 -q:v 2`
      final session = await FFmpegKit.executeWithArguments([
        '-ss',
        '$second',
        '-i',
        ref,
        '-frames:v',
        '1',
        '-q:v',
        '2',
        '-y',
        outPath,
      ]);
      final code = await session.getReturnCode();
      if (!ReturnCode.isSuccess(code)) {
        assert(() {
          debugPrint(
            'NativeFfmpegFrameExtractor extract failed rc=${code?.getValue()}',
          );
          return true;
        }());
        throw const VideoFrameException(VideoFrameErrorKind.extractFailed);
      }
      if (!await outFile.exists()) {
        throw const VideoFrameException(VideoFrameErrorKind.extractFailed);
      }
      final bytes = await outFile.readAsBytes();
      if (bytes.isEmpty) {
        throw const VideoFrameException(VideoFrameErrorKind.extractFailed);
      }
      return bytes;
    } on VideoFrameException {
      rethrow;
    } catch (e, st) {
      assert(() {
        debugPrint('NativeFfmpegFrameExtractor.extractJpegAtSecond: $e\n$st');
        return true;
      }());
      throw const VideoFrameException(VideoFrameErrorKind.extractFailed);
    } finally {
      try {
        if (await outFile.exists()) {
          await outFile.delete();
        }
      } catch (_) {
        // Best-effort temp cleanup.
      }
    }
  }

  void _ensureUsableFilesystemPath(String ref) {
    if (!isUsableFilesystemPath(ref) || isContentUri(ref)) {
      throw const VideoFrameException(VideoFrameErrorKind.pathUnresolved);
    }
  }
}
