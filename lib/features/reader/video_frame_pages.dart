import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:my_translator_app/data/video/video_frame_extractor.dart';
import 'package:my_translator_app/features/reader/cue_text_at_second.dart';
import 'package:my_translator_app/features/reader/video_frame_cache.dart';
import 'package:my_translator_app/features/reader/video_second_math.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';

/// Paged vertical triple of video frames for Reader original pane (VF-01…VF-15).
///
/// Replaces the cue list: one page = up to three stacked seconds; pager chrome
/// pinned under the frame list (VF-14). Page change scrolls to the first slot
/// (VF-15). Cue timestamps come from [buildCueText] / CueRow when text is
/// present (VF-03/VF-04). Injectable [extractor] / [cache] for tests.
class VideoFramePages extends StatefulWidget {
  const VideoFramePages({
    super.key,
    required this.videoRef,
    required this.totalSeconds,
    required this.originalCues,
    required this.extractor,
    required this.cache,
    this.initialPage = 1,
    this.initialSecond,
    this.onPageChanged,
    this.buildCueText,
  });

  /// Usable extract ref (filesystem path or web handle id).
  final String videoRef;

  /// Whole-second coverage (`floor(duration)`); must be ≥ 1 when shown.
  final int totalSeconds;

  /// Original cues for optional text under each slot (D5 / end-second).
  final List<CueDto> originalCues;

  /// Injectable extract facade (fake in tests).
  final VideoFrameExtractor extractor;

  /// Injectable JPEG cache (memory fake in tests).
  final VideoFrameCache cache;

  /// 1-based starting page (used when [initialSecond] is null).
  final int initialPage;

  /// When set, starting page is the page containing this whole second (VF-05).
  final int? initialSecond;

  /// Fired after page changes (split sync / persist in Reader).
  final ValueChanged<int>? onPageChanged;

  /// Optional cue text under the frame (tap/highlight). Default: plain [Text].
  final Widget Function(BuildContext context, int second, String cueText)?
      buildCueText;

  @override
  State<VideoFramePages> createState() => VideoFramePagesState();
}

/// Public state so Reader can jump / read [currentPage] without remount hacks.
class VideoFramePagesState extends State<VideoFramePages> {
  late int _page;
  late int _pageCount;
  final ScrollController _listScrollController = ScrollController();

  /// Second → JPEG bytes, loading, or fail sentinel.
  final Map<int, _SlotImage> _images = {};
  int _loadGeneration = 0;

  int get currentPage => _page;

  int get pageCount => _pageCount;

  /// Frame-list scroll controller (tests / VF-15 offset checks).
  @visibleForTesting
  ScrollController get listScrollController => _listScrollController;

  /// First whole second on the current page (sync / remove anchor).
  int get currentSecond {
    final first = videoFramePageFirstSecond(_page, widget.totalSeconds);
    return first < 0 ? 0 : first;
  }

  @override
  void initState() {
    super.initState();
    _pageCount = videoFramePageCount(widget.totalSeconds);
    _page = _resolveInitialPage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleLoadCurrentPage();
    });
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VideoFramePages oldWidget) {
    super.didUpdateWidget(oldWidget);
    final refChanged = oldWidget.videoRef != widget.videoRef;
    final durationChanged = oldWidget.totalSeconds != widget.totalSeconds;
    if (refChanged || durationChanged) {
      _pageCount = videoFramePageCount(widget.totalSeconds);
      _page = _clampPage(
        refChanged ? _resolveInitialPage() : _page,
      );
      _images.clear();
      _loadGeneration++;
      _scheduleLoadCurrentPage();
      _scrollListToFirstSlot();
    } else if (oldWidget.originalCues != widget.originalCues) {
      setState(() {});
    } else if (oldWidget.initialSecond != widget.initialSecond &&
        widget.initialSecond != null) {
      goToSecond(widget.initialSecond!);
    } else if (oldWidget.initialPage != widget.initialPage &&
        widget.initialSecond == null) {
      goToPage(widget.initialPage);
    }
  }

  int _resolveInitialPage() {
    final second = widget.initialSecond;
    if (second != null) {
      return _clampPage(videoFramePageForSecond(second, widget.totalSeconds));
    }
    return _clampPage(widget.initialPage);
  }

  int _clampPage(int page) {
    if (_pageCount < 1) return 1;
    if (page < 1) return 1;
    if (page > _pageCount) return _pageCount;
    return page;
  }

  /// Jump to 1-based [page] (clamped). Scrolls list to first slot (VF-15).
  void goToPage(int page) {
    final next = _clampPage(page);
    if (next == _page) return;
    setState(() {
      _page = next;
    });
    widget.onPageChanged?.call(_page);
    _scheduleLoadCurrentPage();
    _scrollListToFirstSlot();
  }

  /// VF-15: after page change, first frame of the new page is visible.
  void _scrollListToFirstSlot() {
    void jump() {
      if (!mounted) return;
      if (!_listScrollController.hasClients) return;
      _listScrollController.jumpTo(0);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      // ListView may attach one frame later after page rebuild (VF-15 race).
      if (mounted && !_listScrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) => jump());
      }
    });
  }

  /// Jump to the page containing whole-second [second] (VF-05 / VF-13).
  void jumpToSecond(int second) => goToSecond(second);

  void goToSecond(int second) {
    if (widget.totalSeconds < 1) return;
    final clamped = clampReadingTimeToSecond(second * 1000, widget.totalSeconds);
    if (clamped < 0) return;
    goToPage(videoFramePageForSecond(clamped, widget.totalSeconds));
  }

  void _goPrev() => goToPage(_page - 1);

  void _goNext() => goToPage(_page + 1);

  void _scheduleLoadCurrentPage() {
    final seconds = videoFrameSecondsForPage(_page, widget.totalSeconds);
    final generation = _loadGeneration;
    for (final second in seconds) {
      if (_images[second] is _SlotReady || _images[second] is _SlotFailed) {
        continue;
      }
      _images[second] = const _SlotLoading();
      _loadSlot(second, generation);
    }
    if (mounted) setState(() {});
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
        debugPrint('VideoFramePages slot $second failed: $e\n$st');
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
    final theme = Theme.of(context);
    if (_pageCount < 1) {
      return const SizedBox.shrink(key: Key('videoFramePagesEmpty'));
    }

    final seconds = videoFrameSecondsForPage(_page, widget.totalSeconds);
    final canPrev = _page > 1;
    final canNext = _page < _pageCount;

    // VF-14: pager chrome pinned under the scrollable frame list.
    return Material(
      key: const Key('videoFramePages'),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView.builder(
              controller: _listScrollController,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: seconds.length,
              itemBuilder: (context, index) {
                final second = seconds[index];
                return _FrameSlot(
                  second: second,
                  image: _images[second],
                  cueText: cueTextAtSecond(widget.originalCues, second),
                  buildCueText: widget.buildCueText,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Row(
              children: [
                IconButton(
                  key: const Key('videoFramePagesPrev'),
                  tooltip: 'Previous frames',
                  onPressed: canPrev ? _goPrev : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '$_page / $_pageCount',
                    key: const Key('videoFramePagesCounter'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  key: const Key('videoFramePagesNext'),
                  tooltip: 'Next frames',
                  onPressed: canNext ? _goNext : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
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
    required this.second,
    required this.image,
    required this.cueText,
    this.buildCueText,
  });

  final int second;
  final _SlotImage? image;
  final String cueText;
  final Widget Function(BuildContext context, int second, String cueText)?
      buildCueText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = image is _SlotFailed;
    final ready = image is _SlotReady;
    final bytes = ready ? (image as _SlotReady).bytes : null;
    final customText = buildCueText;

    return Padding(
      key: Key('videoFrameSlot_$second'),
      padding: const EdgeInsets.only(bottom: 12),
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
                          key: Key('videoFrameSlotPlaceholder_$second'),
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : bytes != null
                          ? Image.memory(
                              bytes,
                              key: Key('videoFrameSlotImage_$second'),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (context, error, stackTrace) =>
                                  Center(
                                key: Key('videoFrameSlotPlaceholder_$second'),
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : Center(
                              key: Key('videoFrameSlotLoading_$second'),
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
          // VF-03/VF-04: empty → no time label; with text, buildCueText may
          // embed CueRow(showTimestamp: true) for file start→end.
          if (customText != null)
            customText(context, second, cueText)
          else
            Text(
              cueText,
              key: Key('videoFrameSlotText_$second'),
              style: theme.textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}
