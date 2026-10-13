import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'video_frame_errors.dart';
import 'video_frame_extractor.dart';

/// Web backend: hidden `<video>` + canvas seek (design D2).
///
/// [ref] is a blob/object URL (from [resolveUsableVideoPath] / picker), not a
/// filesystem path.
VideoFrameExtractor createVideoFrameExtractor() => WebCanvasFrameExtractor();

/// Probe + JPEG-at-second via `package:web` video/canvas.
class WebCanvasFrameExtractor implements VideoFrameExtractor {
  WebCanvasFrameExtractor();

  web.HTMLVideoElement? _video;
  String? _loadedRef;

  @override
  Future<Duration> probeDuration(String ref) async {
    if (ref.isEmpty) {
      throw const VideoFrameException(VideoFrameErrorKind.pathUnresolved);
    }
    try {
      final video = await _ensureVideo(ref);
      final seconds = video.duration;
      if (seconds.isNaN || seconds.isInfinite || seconds <= 0) {
        throw const VideoFrameException(VideoFrameErrorKind.probeFailed);
      }
      return Duration(milliseconds: (seconds * 1000).round());
    } on VideoFrameException {
      rethrow;
    } catch (e, st) {
      assert(() {
        debugPrint('WebCanvasFrameExtractor.probeDuration: $e\n$st');
        return true;
      }());
      throw const VideoFrameException(VideoFrameErrorKind.probeFailed);
    }
  }

  @override
  Future<Uint8List> extractJpegAtSecond(String ref, int second) async {
    if (ref.isEmpty) {
      throw const VideoFrameException(VideoFrameErrorKind.pathUnresolved);
    }
    if (second < 0) {
      throw const VideoFrameException(VideoFrameErrorKind.extractFailed);
    }
    try {
      final video = await _ensureVideo(ref);
      await _seekToSecond(video, second);

      final width = video.videoWidth;
      final height = video.videoHeight;
      if (width <= 0 || height <= 0) {
        throw const VideoFrameException(VideoFrameErrorKind.extractFailed);
      }

      final canvas = web.HTMLCanvasElement()
        ..width = width
        ..height = height;
      final ctx = canvas.getContext('2d');
      if (ctx == null) {
        throw const VideoFrameException(VideoFrameErrorKind.extractFailed);
      }
      final context = ctx as web.CanvasRenderingContext2D;
      context.drawImage(video, 0, 0);

      final dataUrl = canvas.toDataURL('image/jpeg', 0.92.toJS);
      return _jpegBytesFromDataUrl(dataUrl);
    } on VideoFrameException {
      rethrow;
    } catch (e, st) {
      assert(() {
        debugPrint('WebCanvasFrameExtractor.extractJpegAtSecond: $e\n$st');
        return true;
      }());
      throw const VideoFrameException(VideoFrameErrorKind.extractFailed);
    }
  }

  Future<web.HTMLVideoElement> _ensureVideo(String ref) async {
    final existing = _video;
    if (existing != null && _loadedRef == ref) {
      return existing;
    }
    _disposeVideo();

    final video = web.HTMLVideoElement()
      ..preload = 'auto'
      ..muted = true
      ..setAttribute('playsinline', 'true');
    video.style
      ..setProperty('display', 'none')
      ..setProperty('position', 'fixed')
      ..setProperty('width', '1px')
      ..setProperty('height', '1px');
    web.document.body?.append(video);

    video.src = ref;
    video.load();
    await _waitVideoEvent(
      success: video.onLoadedMetadata,
      error: video.onError,
      failureKind: VideoFrameErrorKind.probeFailed,
    );

    _video = video;
    _loadedRef = ref;
    return video;
  }

  Future<void> _seekToSecond(web.HTMLVideoElement video, int second) async {
    final target = second.toDouble();
    if ((video.currentTime - target).abs() < 0.01) {
      return;
    }
    video.currentTime = target;
    await _waitVideoEvent(
      success: video.onSeeked,
      error: video.onError,
      failureKind: VideoFrameErrorKind.extractFailed,
    );
  }

  /// Completes on first [success] or fails on [error]; cancels both subs.
  Future<void> _waitVideoEvent({
    required Stream<web.Event> success,
    required Stream<web.Event> error,
    required VideoFrameErrorKind failureKind,
  }) async {
    final completer = Completer<void>();
    late final StreamSubscription<web.Event> successSub;
    late final StreamSubscription<web.Event> errorSub;

    successSub = success.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    errorSub = error.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(VideoFrameException(failureKind));
      }
    });

    try {
      await completer.future;
    } finally {
      await successSub.cancel();
      await errorSub.cancel();
    }
  }

  void _disposeVideo() {
    final video = _video;
    _video = null;
    _loadedRef = null;
    if (video == null) return;
    try {
      video.pause();
      video.removeAttribute('src');
      video.load();
      video.remove();
    } catch (_) {
      // Best-effort teardown.
    }
  }

  static Uint8List _jpegBytesFromDataUrl(String dataUrl) {
    final comma = dataUrl.indexOf(',');
    if (comma < 0 || !dataUrl.startsWith('data:image/jpeg')) {
      throw const VideoFrameException(VideoFrameErrorKind.extractFailed);
    }
    final bytes = base64Decode(dataUrl.substring(comma + 1));
    if (bytes.isEmpty) {
      throw const VideoFrameException(VideoFrameErrorKind.extractFailed);
    }
    return bytes;
  }
}
