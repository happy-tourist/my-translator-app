import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:my_translator_app/data/video/video_frame_extractor.dart';
import 'package:my_translator_app/features/reader/cue_text_at_second.dart';
import 'package:my_translator_app/features/reader/cue_time_format.dart';
import 'package:my_translator_app/features/reader/video_frame_cache.dart';
import 'package:my_translator_app/features/reader/video_second_math.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';

/// Vertical second-timeline for Reader original pane (VF-01…VF-03, VF-10).
///
/// One virtualized row per whole-video second: frame + timestamp + optional
/// cue text (or empty). Injectable [extractor] / [cache] for tests. Does not
/// wire AppBar load/remove — blocks 5/7 embed this widget.
class VideoSecondTimeline extends StatefulWidget {
  const VideoSecondTimeline({
    super.key,
    required this.videoRef,
    required this.totalSeconds,
    required this.originalCues,
    required this.extractor,
    required this.cache,
    this.initialSecond = 0,
    this.onSecondChanged,
    this.itemScrollController,
    this.itemPositionsListener,
    this.buildCueText,
  });

  /// Usable extract ref (filesystem path or web handle id).
  final String videoRef;

  /// Whole-second coverage (`floor(duration)`); must be ≥ 1 when shown.
  final int totalSeconds;

  /// Original cues for optional text under each frame (D5).
  final List<CueDto> originalCues;

  /// Injectable extract facade (fake in tests).
  final VideoFrameExtractor extractor;

  /// Injectable JPEG cache (memory fake in tests).
  final VideoFrameCache cache;

  /// 0-based starting second (clamped).
  final int initialSecond;

  /// Fired when the top-visible second changes (sync in blocks 5/7).
  final ValueChanged<int>? onSecondChanged;

  /// Optional external scroll controller (survive remount in block 7).
  final ItemScrollController? itemScrollController;

  /// Optional external positions listener.
  final ItemPositionsListener? itemPositionsListener;

  /// Optional cue text under the frame (tap/highlight). Default: plain [Text].
  final Widget Function(BuildContext context, int second, String cueText)?
      buildCueText;

  @override
  State<VideoSecondTimeline> createState() => VideoSecondTimelineState();
}

/// Public state so block 5/7 can jump / read [currentSecond] without remount hacks.
class VideoSecondTimelineState extends State<VideoSecondTimeline> {
  late final ItemScrollController _scrollController;
  late final ItemPositionsListener _positionsListener;

  late int _currentSecond;
  late int _secondCount;

  /// Second → JPEG bytes, loading, or fail sentinel.
  final Map<int, _RowImage> _images = {};
  /// Bumped only when video ref / duration changes (invalidates in-flight loads).
  int _loadGeneration = 0;
  final Set<int> _inflightSeconds = {};
  var _reportingSecond = false;

  int get currentSecond => _currentSecond;

  int get secondCount => _secondCount;

  ItemScrollController get itemScrollController => _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.itemScrollController ?? ItemScrollController();
    _positionsListener =
        widget.itemPositionsListener ?? ItemPositionsListener.create();
    _secondCount = videoTimelineSecondCount(widget.totalSeconds);
    _currentSecond = _clampSecond(widget.initialSecond);
    _positionsListener.itemPositions.addListener(_onPositionsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleLoadAround(_currentSecond);
    });
  }

  @override
  void dispose() {
    _positionsListener.itemPositions.removeListener(_onPositionsChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VideoSecondTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final refChanged = oldWidget.videoRef != widget.videoRef;
    final durationChanged = oldWidget.totalSeconds != widget.totalSeconds;
    if (refChanged || durationChanged) {
      _secondCount = videoTimelineSecondCount(widget.totalSeconds);
      _currentSecond = _clampSecond(
        refChanged ? widget.initialSecond : _currentSecond,
      );
      _images.clear();
      _inflightSeconds.clear();
      _loadGeneration++;
      _scheduleLoadAround(_currentSecond);
      if (_scrollController.isAttached && _secondCount >= 1) {
        _scrollController.jumpTo(index: _currentSecond, alignment: 0);
      }
    } else if (oldWidget.originalCues != widget.originalCues) {
      setState(() {});
    }
  }

  int _clampSecond(int second) {
    final clamped = clampReadingTimeToSecond(second * 1000, _secondCount);
    return clamped < 0 ? 0 : clamped;
  }

  /// Jump timeline to [second] (clamped). Used on Load / restore (VF-05).
  void jumpToSecond(int second) {
    if (_secondCount < 1) return;
    final next = _clampSecond(second);
    if (next != _currentSecond) {
      setState(() {
        _currentSecond = next;
      });
      widget.onSecondChanged?.call(_currentSecond);
    }
    if (_scrollController.isAttached) {
      _scrollController.jumpTo(index: next, alignment: 0);
    }
    _scheduleLoadAround(next);
  }

  void _onPositionsChanged() {
    if (!mounted || _secondCount < 1) return;
    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    // Prefer the first mostly-visible row near the top of the viewport.
    var best = positions.first.index;
    var bestEdge = double.infinity;
    for (final pos in positions) {
      if (pos.itemLeadingEdge >= -0.05 && pos.itemLeadingEdge < bestEdge) {
        bestEdge = pos.itemLeadingEdge;
        best = pos.index;
      }
    }

    _scheduleLoadVisible(positions.map((p) => p.index));

    if (best != _currentSecond && !_reportingSecond) {
      _reportingSecond = true;
      setState(() {
        _currentSecond = best;
      });
      widget.onSecondChanged?.call(_currentSecond);
      _reportingSecond = false;
    }
  }

  void _scheduleLoadAround(int center) {
    if (_secondCount < 1) return;
    final start = (center - 2).clamp(0, _secondCount - 1);
    final end = (center + 4).clamp(0, _secondCount - 1);
    _scheduleLoadVisible(
      List.generate(end - start + 1, (i) => start + i),
    );
  }

  void _scheduleLoadVisible(Iterable<int> seconds) {
    final generation = _loadGeneration;
    var scheduled = false;
    for (final second in seconds) {
      if (!isValidTimelineSecond(second, _secondCount)) continue;
      if (_images[second] is _RowReady ||
          _images[second] is _RowFailed ||
          _inflightSeconds.contains(second)) {
        continue;
      }
      _images[second] = const _RowLoading();
      _inflightSeconds.add(second);
      scheduled = true;
      _loadRow(second, generation);
    }
    if (scheduled && mounted) {
      setState(() {});
    }
  }

  Future<void> _loadRow(int second, int generation) async {
    try {
      final cached = await widget.cache.get(second);
      if (!mounted || generation != _loadGeneration) return;
      if (cached != null) {
        setState(() {
          _images[second] = _RowReady(cached);
          _inflightSeconds.remove(second);
        });
        return;
      }

      final jpeg = await widget.extractor.extractJpegAtSecond(
        widget.videoRef,
        second,
      );
      if (!mounted || generation != _loadGeneration) return;
      await widget.cache.put(second, jpeg);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _images[second] = _RowReady(jpeg);
        _inflightSeconds.remove(second);
      });
    } catch (e, st) {
      // VF-10: per-row placeholder (not SnackBar); log for debug.
      assert(() {
        debugPrint('VideoSecondTimeline row $second failed: $e\n$st');
        return true;
      }());
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _images[second] = const _RowFailed();
        _inflightSeconds.remove(second);
      });
    } finally {
      _inflightSeconds.remove(second);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_secondCount < 1) {
      return const SizedBox.shrink(key: Key('videoSecondTimelineEmpty'));
    }

    return Material(
      key: const Key('videoSecondTimeline'),
      color: theme.colorScheme.surface,
      child: ScrollablePositionedList.builder(
        itemScrollController: _scrollController,
        itemPositionsListener: _positionsListener,
        initialScrollIndex: _currentSecond.clamp(0, _secondCount - 1),
        itemCount: _secondCount,
        itemBuilder: (context, second) {
          return _SecondRow(
            second: second,
            image: _images[second],
            cueText: cueTextAtSecond(widget.originalCues, second),
            buildCueText: widget.buildCueText,
          );
        },
      ),
    );
  }
}

sealed class _RowImage {
  const _RowImage();
}

class _RowLoading extends _RowImage {
  const _RowLoading();
}

class _RowReady extends _RowImage {
  const _RowReady(this.bytes);
  final Uint8List bytes;
}

class _RowFailed extends _RowImage {
  const _RowFailed();
}

class _SecondRow extends StatelessWidget {
  const _SecondRow({
    required this.second,
    required this.image,
    required this.cueText,
    this.buildCueText,
  });

  final int second;
  final _RowImage? image;
  final String cueText;
  final Widget Function(BuildContext context, int second, String cueText)?
      buildCueText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = image is _RowFailed;
    final ready = image is _RowReady;
    final bytes = ready ? (image as _RowReady).bytes : null;
    final timestamp = formatCueTimestamp(BigInt.from(second) * BigInt.from(1000));
    final customText = buildCueText;

    return Padding(
      key: Key('videoSecondRow_$second'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Semantics(
              label: 'Video frame at ${second}s',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: failed
                      ? Center(
                          key: Key('videoSecondPlaceholder_$second'),
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : bytes != null
                          ? Image.memory(
                              bytes,
                              key: Key('videoSecondImage_$second'),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) =>
                                  Center(
                                key: Key('videoSecondPlaceholder_$second'),
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : Center(
                              key: Key('videoSecondLoading_$second'),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            timestamp,
            key: Key('videoSecondTimestamp_$second'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          if (customText != null)
            customText(context, second, cueText)
          else
            Text(
              cueText,
              key: Key('videoSecondText_$second'),
              style: theme.textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}
