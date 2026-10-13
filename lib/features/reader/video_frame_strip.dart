import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:my_translator_app/data/video/video_frame_extractor.dart';
import 'package:my_translator_app/features/reader/cue_text_at_second.dart';
import 'package:my_translator_app/features/reader/video_frame_cache.dart';
import 'package:my_translator_app/features/reader/video_frame_page_math.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';

/// Paginated 3-slot video frame strip for Reader (VF-01…VF-05, VF-10).
///
/// Lives **outside** the Show/Hide split remount branch (design D4). Does not
/// wire AppBar load/remove — block 5 embeds this widget.
class VideoFrameStrip extends StatefulWidget {
  const VideoFrameStrip({
    super.key,
    required this.videoRef,
    required this.totalSeconds,
    required this.originalCues,
    required this.extractor,
    required this.cache,
    this.initialPage = 1,
    this.onPageChanged,
  });

  /// Usable extract ref (filesystem path or web handle id).
  final String videoRef;

  /// Whole-second coverage (`floor(duration)`); must be ≥ 1 when shown.
  final int totalSeconds;

  /// Original cues for optional text under each slot (D5).
  final List<CueDto> originalCues;

  /// Injectable extract facade (fake in tests).
  final VideoFrameExtractor extractor;

  /// Injectable JPEG cache (memory fake in tests).
  final VideoFrameCache cache;

  /// 1-based starting page.
  final int initialPage;

  /// Fired after page changes (for cue scroll sync in block 5).
  final ValueChanged<int>? onPageChanged;

  @override
  State<VideoFrameStrip> createState() => VideoFrameStripState();
}

/// Public state so block 5 can read [currentPage] without remount hacks.
class VideoFrameStripState extends State<VideoFrameStrip> {
  late int _page;
  late int _pageCount;

  /// Slot index → JPEG bytes, or `null` while loading, or sentinel fail.
  final Map<int, _SlotImage> _images = {};
  int _loadGeneration = 0;

  int get currentPage => _page;

  int get pageCount => _pageCount;

  @override
  void initState() {
    super.initState();
    _pageCount = videoFramePageCount(widget.totalSeconds);
    _page = _clampPage(widget.initialPage);
    // Avoid setState during initState — load slots after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleLoadCurrentPage();
    });
  }

  @override
  void didUpdateWidget(covariant VideoFrameStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final refChanged = oldWidget.videoRef != widget.videoRef;
    final durationChanged = oldWidget.totalSeconds != widget.totalSeconds;
    if (refChanged || durationChanged) {
      _pageCount = videoFramePageCount(widget.totalSeconds);
      _page = _clampPage(refChanged ? widget.initialPage : _page);
      _images.clear();
      _scheduleLoadCurrentPage();
    } else if (oldWidget.originalCues != widget.originalCues) {
      // Text-only refresh; frames stay.
      setState(() {});
    }
  }

  int _clampPage(int page) {
    if (_pageCount < 1) return 1;
    if (page < 1) return 1;
    if (page > _pageCount) return _pageCount;
    return page;
  }

  void goToPage(int page) {
    final next = _clampPage(page);
    if (next == _page) return;
    setState(() {
      _page = next;
    });
    widget.onPageChanged?.call(_page);
    _scheduleLoadCurrentPage();
  }

  void _goPrev() => goToPage(_page - 1);

  void _goNext() => goToPage(_page + 1);

  void _scheduleLoadCurrentPage() {
    final seconds = videoFrameSecondsForPage(_page, widget.totalSeconds);
    final generation = ++_loadGeneration;
    for (final second in seconds) {
      if (_images[second] is _SlotReady || _images[second] is _SlotFailed) {
        continue;
      }
      _images[second] = const _SlotLoading();
      _loadSlot(second, generation);
    }
    setState(() {});
  }

  Future<void> _loadSlot(int second, int generation) async {
    try {
      final cached = await widget.cache.get(second);
      if (!mounted || generation != _loadGeneration) return;
      if (cached != null) {
        setState(() {
          _images[second] = _SlotReady(cached);
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
        _images[second] = _SlotReady(jpeg);
      });
    } catch (e, st) {
      // VF-10: per-slot placeholder (not SnackBar); log for debug.
      assert(() {
        debugPrint('VideoFrameStrip slot $second failed: $e\n$st');
        return true;
      }());
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _images[second] = const _SlotFailed();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final seconds = videoFrameSecondsForPage(_page, widget.totalSeconds);
    final theme = Theme.of(context);
    final canPrev = _page > 1;
    final canNext = _page < _pageCount;

    return Material(
      key: const Key('videoFrameStrip'),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('videoFrameStripPrev'),
                  tooltip: 'Previous frames',
                  onPressed: canPrev ? _goPrev : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '$_page / $_pageCount',
                    key: const Key('videoFrameStripCounter'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  key: const Key('videoFrameStripNext'),
                  tooltip: 'Next frames',
                  onPressed: canNext ? _goNext : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: i == 0 ? 0 : 4,
                        right: i == 2 ? 0 : 4,
                      ),
                      child: i < seconds.length
                          ? _FrameSlot(
                              slotIndex: i,
                              second: seconds[i],
                              image: _images[seconds[i]],
                              cueText: cueTextAtSecond(
                                widget.originalCues,
                                seconds[i],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

sealed class _SlotImage {
  const _SlotImage();
}

class _SlotLoading extends _SlotImage {
  const _SlotLoading();
}

class _SlotReady extends _SlotImage {
  const _SlotReady(this.bytes);
  final Uint8List bytes;
}

class _SlotFailed extends _SlotImage {
  const _SlotFailed();
}

class _FrameSlot extends StatelessWidget {
  const _FrameSlot({
    required this.slotIndex,
    required this.second,
    required this.image,
    required this.cueText,
  });

  final int slotIndex;
  final int second;
  final _SlotImage? image;
  final String cueText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = image is _SlotFailed;
    final ready = image is _SlotReady;
    final bytes = ready ? (image as _SlotReady).bytes : null;

    return Column(
      key: Key('videoFrameSlot_$slotIndex'),
      mainAxisSize: MainAxisSize.min,
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
                        key: Key('videoFrameSlotPlaceholder_$slotIndex'),
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : bytes != null
                        ? Image.memory(
                            bytes,
                            key: Key('videoFrameSlotImage_$slotIndex'),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stackTrace) => Center(
                              key: Key('videoFrameSlotPlaceholder_$slotIndex'),
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Center(
                            key: Key('videoFrameSlotLoading_$slotIndex'),
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
        const SizedBox(height: 4),
        Text(
          cueText,
          key: Key('videoFrameSlotText_$slotIndex'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
