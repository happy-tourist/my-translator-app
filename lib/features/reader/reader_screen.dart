import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show AnyhowException, PanicException;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/dictionary/dictionary_exceptions.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';
import 'package:my_translator_app/data/library/document_format.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/library_exceptions.dart';
import 'package:my_translator_app/data/library/parse_epub_fn.dart';
import 'package:my_translator_app/data/library/parse_error_messages.dart';
import 'package:my_translator_app/data/library/parse_subtitles_fn.dart';
import 'package:my_translator_app/data/translate/offline_translate.dart';
import 'package:my_translator_app/data/translate/offline_translate_platform.dart';
import 'package:my_translator_app/data/video/reader_video_picker.dart';
import 'package:my_translator_app/data/video/video_frame_errors.dart';
import 'package:my_translator_app/data/video/video_frame_extractor.dart';
import 'package:my_translator_app/data/video/video_frame_extractor_platform.dart';
import 'package:my_translator_app/data/video/video_playback_ref.dart';
import 'package:my_translator_app/data/video/video_usable_path.dart';
import 'package:my_translator_app/data/video/video_usable_path_platform.dart'
    as video_path;
import 'package:my_translator_app/features/reader/cue_row.dart';
import 'package:my_translator_app/features/reader/cue_text_at_second.dart';
import 'package:my_translator_app/features/reader/nearest_cue_index.dart';
import 'package:my_translator_app/features/reader/tokenize_cues_fn.dart';
import 'package:my_translator_app/features/reader/video_frame_cache.dart';
import 'package:my_translator_app/features/reader/video_frame_pages.dart';
import 'package:my_translator_app/features/reader/video_second_math.dart';
import 'package:my_translator_app/src/rust/api/epub.dart' as rust_epub;
import 'package:my_translator_app/src/rust/api/parse.dart' as rust_parse;
import 'package:my_translator_app/src/rust/api/tokenize.dart' as rust_tokenize;

/// Picked translation file for injectable Reader load (tests / file_picker).
class PickedTranslationFile {
  const PickedTranslationFile({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

typedef ReaderTranslationPicker = Future<PickedTranslationFile?> Function();

/// Cues-first Reader with optional split / EPUB book mode and tap selection.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.title,
    this.originalCues = const [],
    required this.originalDocumentId,
    required this.documentRepository,
    required this.dictionaryRepository,
    this.documentFormat,
    this.originalChapters,
    this.translationChapters,
    this.translationCues,
    this.translationDocumentId,
    this.initialReadingAnchor,
    this.initialVideoAttachment,
    this.parseSubtitles,
    this.parseEpub,
    this.tokenizeCues,
    this.markVocabTokens,
    this.filePicker,
    this.offlineTranslate,
    this.videoPicker,
    this.videoFrameExtractor,
    this.videoFrameCache,
    this.resolveUsableVideoPath,
  });

  final String title;

  /// Subtitle cues for the original pane. Empty in EPUB book mode (D4).
  final List<rust_parse.CueDto> originalCues;
  final int originalDocumentId;
  final DocumentRepository documentRepository;
  final DictionaryRepository dictionaryRepository;

  /// Stored format (`srt` / `vtt` / `ass` / `epub`). Book mode when `epub`.
  final String? documentFormat;

  /// EPUB chapters for book-mode original pane (D4 / LD-25).
  final List<rust_epub.EpubChapterDto>? originalChapters;

  /// Optional linked EPUB translation chapters (LD-16).
  final List<rust_epub.EpubChapterDto>? translationChapters;

  final List<rust_parse.CueDto>? translationCues;
  final int? translationDocumentId;

  /// Saved original-pane position from Library open (RS-12 / LD-17 / LD-28).
  ///
  /// For EPUB, [ReadingAnchor.startMs] is the 0-based chapter index.
  final ReadingAnchor? initialReadingAnchor;

  /// Best-effort video meta from Library open (LD-19); null → Reader loads.
  /// Unused / ignored for EPUB book mode (RC-05).
  final VideoAttachment? initialVideoAttachment;

  /// Defaults to generated FRB [rust_parse.parseSubtitles].
  final ParseSubtitlesFn? parseSubtitles;

  /// Defaults to generated FRB [rust_epub.parseEpub].
  final ParseEpubFn? parseEpub;

  /// Defaults to generated FRB [rust_tokenize.tokenizeCues].
  final TokenizeCuesFn? tokenizeCues;

  /// Defaults to generated FRB [rust_tokenize.markVocabTokens].
  final MarkVocabTokensFn? markVocabTokens;

  /// Defaults to [FilePicker.pickFiles].
  final ReaderTranslationPicker? filePicker;

  /// Offline EN→RU gloss for Add/Edit sheets. Defaults to platform facade.
  final OfflineTranslateFn? offlineTranslate;

  /// Injectable video pick (design D8). Defaults to [defaultReaderVideoPicker].
  final ReaderVideoPicker? videoPicker;

  /// Injectable frame extract facade. Defaults to platform FFmpeg/canvas.
  final VideoFrameExtractor? videoFrameExtractor;

  /// Injectable JPEG cache. Defaults to Drift [DocumentRepositoryVideoFrameCache].
  final VideoFrameCache? videoFrameCache;

  /// Injectable usable-path resolve after pick (tests). Defaults to platform.
  final ResolveUsableVideoPathFn? resolveUsableVideoPath;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

/// In-memory tokenize(+mark) cache for one EPUB chapter (D12 / RC-09).
class _ChapterTokenCache {
  const _ChapterTokenCache({required this.tokens, required this.markReady});

  final List<rust_tokenize.CueTokensDto> tokens;
  final bool markReady;
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const double _dividerHandleHeight = 16;
  static const double _minRatio = 0.2;
  static const double _maxRatio = 0.8;
  static const Duration _gapFlashDuration = Duration(milliseconds: 300);

  /// First-pass paragraph count before idle remainder (D12 / RC-08).
  static const int _bookTokenizePrefixCount = 4;

  var _splitEnabled = false;
  /// Subtitle split still uses this field with setState; book split uses
  /// [_bookDividerRatio] (D13 / RS-17).
  var _dividerRatio = 0.5;
  final ValueNotifier<double> _bookDividerRatio = ValueNotifier(0.5);
  var _syncing = false;
  var _userInitiatedScroll = false;
  var _loadingTranslation = false;
  var _loadingVideo = false;
  var _didRestoreInitialAnchor = false;

  /// Applied as [ScrollablePositionedList.initialScrollIndex] on original
  /// remount (Show/Hide split) so the first frame is not cue 0 (RS-10/11).
  var _originalInitialScrollIndex = 0;
  var _originalInitialAlignment = 0.0;

  List<rust_parse.CueDto>? _translationCues;
  int? _translationDocumentId;
  List<rust_epub.EpubChapterDto>? _translationChapters;

  /// Current EPUB chapter index (0-based). Book mode only.
  var _chapterIndex = 0;

  /// Active video pages session (VF-01…VF-13). Null ref → cue list shown.
  String? _videoRef;
  var _videoTotalSeconds = 0;
  var _videoInitialSecond = 0;
  var _videoCurrentSecond = 0;
  late VideoFrameCache _videoCache;
  /// Outside Show/Hide remount so page state survives split toggle (VF-09).
  final _videoPagesKey = GlobalKey<VideoFramePagesState>();

  /// Batch tokenize+mark cache (D5). Null while in-flight or after failure.
  /// Book mode: current chapter view; also keyed in [_chapterTokenCache].
  List<rust_tokenize.CueTokensDto>? _cueTokensByIndex;
  var _tokenizeReady = false;

  /// Session cache: chapterIndex → tokenize(+mark) (D12 / RC-09). Not persisted.
  final Map<int, _ChapterTokenCache> _chapterTokenCache = {};

  /// Invalidates in-flight tokenize/mark when chapter changes (book mode) or a
  /// newer batch starts — prevents stale FRB results from binding wrong text.
  var _tokenizeGeneration = 0;

  /// Contiguous Add selection: active cue + inclusive token range (D5).
  int? _activeCueIndex;
  int? _selectionStart;
  int? _selectionEnd;
  int? _flashTokenIndex;
  Timer? _flashTimer;

  final _originalScrollController = ItemScrollController();
  final _translationScrollController = ItemScrollController();
  final _originalPositions = ItemPositionsListener.create();
  final _translationPositions = ItemPositionsListener.create();

  ParseSubtitlesFn get _parse =>
      widget.parseSubtitles ?? rust_parse.parseSubtitles;

  ParseEpubFn get _parseEpub => widget.parseEpub ?? rust_epub.parseEpub;

  TokenizeCuesFn get _tokenize =>
      widget.tokenizeCues ??
      ((texts) => rust_tokenize.tokenizeCues(texts: texts));

  MarkVocabTokensFn get _mark =>
      widget.markVocabTokens ??
      (({required cues, required vocabLemmas}) =>
          rust_tokenize.markVocabTokens(cues: cues, vocabLemmas: vocabLemmas));

  late final OfflineTranslateFn _offlineTranslate =
      widget.offlineTranslate ?? createPlatformOfflineTranslate();

  late final VideoFrameExtractor _videoExtractor =
      widget.videoFrameExtractor ?? createPlatformVideoFrameExtractor();

  bool get _isBookMode => isEpubFormat(widget.documentFormat);

  List<rust_epub.EpubChapterDto> get _originalChapters =>
      widget.originalChapters ?? const [];

  /// Paragraphs of the current EPUB chapter (book mode).
  List<String> get _currentChapterParagraphs {
    final chapters = _originalChapters;
    if (chapters.isEmpty) return const [];
    final index = _chapterIndex.clamp(0, chapters.length - 1);
    return chapters[index].paragraphs;
  }

  bool get _hasTranslationCues =>
      _translationCues != null && _translationCues!.isNotEmpty;

  bool get _hasTranslationChapters =>
      _translationChapters != null && _translationChapters!.isNotEmpty;

  /// Linked translation exists in Drift (may lack cues after failed restore).
  bool get _hasLinkedTranslation => _translationDocumentId != null;

  bool get _hasSelection =>
      _activeCueIndex != null &&
      _selectionStart != null &&
      _selectionEnd != null;

  bool get _hasVideo =>
      !_isBookMode && _videoRef != null && _videoTotalSeconds >= 1;

  @override
  void initState() {
    super.initState();
    _translationCues = widget.translationCues;
    _translationDocumentId = widget.translationDocumentId;
    _translationChapters = widget.translationChapters;
    if (_isBookMode) {
      final chapters = _originalChapters;
      final anchor = widget.initialReadingAnchor;
      if (chapters.isNotEmpty) {
        final raw = anchor?.startMs ?? 0;
        _chapterIndex = raw.clamp(0, chapters.length - 1);
      }
      // D4 / RC-04: tokenize current chapter paragraphs (not empty originalCues).
      unawaited(_runBatchTokenize());
      // RS-16 / D5: linked translation with unequal N — notice on open (not silent).
      final linkedChapters = widget.translationChapters;
      if (linkedChapters != null &&
          chapters.isNotEmpty &&
          linkedChapters.length != chapters.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showError(mismatchedEpubChapterCountMessage);
        });
      }
    }
    _videoCache = widget.videoFrameCache ??
        DocumentRepositoryVideoFrameCache(
          widget.documentRepository,
          widget.originalDocumentId,
        );
    if (!_isBookMode) {
      final initialVideo = widget.initialVideoAttachment;
      if (initialVideo != null) {
        unawaited(_hydrateVideoAttachment(initialVideo));
      } else {
        unawaited(_loadVideoAttachmentBestEffort());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreInitialReadingAnchor();
      });
      unawaited(_runBatchTokenize());
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _bookDividerRatio.dispose();
    // RS-12 / D10: best-effort save on pop/dispose (do not block).
    // Force: skip `_syncing` guard — pop must still persist even mid-sync.
    unawaited(_persistReadingAnchor(force: true));
    super.dispose();
  }

  List<rust_tokenize.CueTokensDto> _normalizeCueTokensCache(
    List<rust_tokenize.CueTokensDto> result,
    int length,
  ) {
    final byIndex = List<rust_tokenize.CueTokensDto?>.filled(length, null);
    for (final dto in result) {
      if (dto.cueIndex >= 0 && dto.cueIndex < byIndex.length) {
        byIndex[dto.cueIndex] = dto;
      }
    }
    final cached = <rust_tokenize.CueTokensDto>[];
    for (var i = 0; i < byIndex.length; i++) {
      cached.add(
        byIndex[i] ??
            rust_tokenize.CueTokensDto(cueIndex: i, tokens: const []),
      );
    }
    return cached;
  }

  Future<void> _runBatchTokenize() async {
    if (_isBookMode) {
      await _runBookChapterTokenize();
      return;
    }
    // Subtitle mode: cue display strings (full batch).
    final generation = ++_tokenizeGeneration;
    final texts = widget.originalCues
        .map((c) => c.textLines.join('\n'))
        .toList(growable: false);
    if (texts.isEmpty) {
      if (!mounted || generation != _tokenizeGeneration) return;
      setState(() {
        _cueTokensByIndex = const [];
        _tokenizeReady = true;
      });
      return;
    }
    try {
      final result = await _tokenize(texts);
      if (!mounted || generation != _tokenizeGeneration) return;
      final cached = _normalizeCueTokensCache(result, texts.length);
      // Mark failure must not wipe a successful tokenize (tap still works;
      // highlights refresh on next save/open).
      try {
        final lemmas = (await widget.dictionaryRepository.list())
            .map((e) => e.lemma)
            .toList(growable: false);
        if (!mounted || generation != _tokenizeGeneration) return;
        final marked = await _mark(cues: cached, vocabLemmas: lemmas);
        if (!mounted || generation != _tokenizeGeneration) return;
        setState(() {
          _cueTokensByIndex =
              _normalizeCueTokensCache(marked, texts.length);
          _tokenizeReady = true;
        });
      } catch (e, st) {
        assert(() {
          debugPrint('markVocabTokens on open failed: $e\n$st');
          return true;
        }());
        if (!mounted || generation != _tokenizeGeneration) return;
        setState(() {
          _cueTokensByIndex = cached;
          _tokenizeReady = true;
        });
        _showMarkRefreshError();
      }
    } on AnyhowException catch (e) {
      assert(() {
        debugPrint('tokenizeCues Anyhow: ${e.message}');
        return true;
      }());
      _failTokenizeBatch(generation);
    } on PanicException catch (e) {
      assert(() {
        debugPrint('tokenizeCues panic: ${e.message}');
        return true;
      }());
      _failTokenizeBatch(generation);
    } catch (e, st) {
      assert(() {
        debugPrint('tokenizeCues failed: $e\n$st');
        return true;
      }());
      _failTokenizeBatch(generation);
    }
  }

  int get _currentChapterIndexClamped {
    final chapters = _originalChapters;
    if (chapters.isEmpty) return 0;
    return _chapterIndex.clamp(0, chapters.length - 1);
  }

  /// Progressive tokenize + chapter cache for EPUB (D12 / RC-08 / RC-09).
  Future<void> _runBookChapterTokenize() async {
    final chapterIndex = _currentChapterIndexClamped;
    final generation = ++_tokenizeGeneration;
    final texts = List<String>.from(_currentChapterParagraphs);

    final hit = _chapterTokenCache[chapterIndex];
    if (hit != null) {
      if (!mounted || generation != _tokenizeGeneration) return;
      setState(() {
        _cueTokensByIndex = hit.tokens;
        _tokenizeReady = true;
      });
      if (!hit.markReady) {
        await _markBookChapterTokens(
          chapterIndex: chapterIndex,
          tokens: hit.tokens,
          generation: generation,
        );
      }
      return;
    }

    if (texts.isEmpty) {
      if (!mounted || generation != _tokenizeGeneration) return;
      setState(() {
        _cueTokensByIndex = const [];
        _tokenizeReady = true;
      });
      _chapterTokenCache[chapterIndex] = const _ChapterTokenCache(
        tokens: [],
        markReady: true,
      );
      return;
    }

    try {
      final prefixLen = texts.length <= _bookTokenizePrefixCount
          ? texts.length
          : _bookTokenizePrefixCount;

      // Phase 1: prefix — tap-ready early (RC-08); highlight MAY lag.
      final prefixResult = await _tokenize(texts.sublist(0, prefixLen));
      if (!mounted || generation != _tokenizeGeneration) return;
      var working = _normalizeCueTokensCache(prefixResult, texts.length);
      setState(() {
        _cueTokensByIndex = working;
        _tokenizeReady = true;
      });

      // Phase 2: remainder after a frame / idle yield (D12).
      if (prefixLen < texts.length) {
        await SchedulerBinding.instance.scheduleTask(
          () {},
          Priority.idle,
        );
        if (!mounted || generation != _tokenizeGeneration) return;
        final restResult = await _tokenize(texts.sublist(prefixLen));
        if (!mounted || generation != _tokenizeGeneration) return;
        final remapped = [
          for (final dto in restResult)
            rust_tokenize.CueTokensDto(
              cueIndex: dto.cueIndex + prefixLen,
              tokens: dto.tokens,
            ),
        ];
        // Merge prefix slots + remapped rest into a full-length cache.
        final merged = List<rust_tokenize.CueTokensDto>.from(working);
        for (final dto in remapped) {
          if (dto.cueIndex >= 0 && dto.cueIndex < merged.length) {
            merged[dto.cueIndex] = dto;
          }
        }
        working = merged;
        setState(() {
          _cueTokensByIndex = working;
        });
      }

      // Cache tokenize before mark so pager return is a hit even if mark lags.
      _chapterTokenCache[chapterIndex] = _ChapterTokenCache(
        tokens: working,
        markReady: false,
      );
      await _markBookChapterTokens(
        chapterIndex: chapterIndex,
        tokens: working,
        generation: generation,
      );
    } on AnyhowException catch (e) {
      assert(() {
        debugPrint('tokenizeCues Anyhow: ${e.message}');
        return true;
      }());
      _failTokenizeBatch(generation);
    } on PanicException catch (e) {
      assert(() {
        debugPrint('tokenizeCues panic: ${e.message}');
        return true;
      }());
      _failTokenizeBatch(generation);
    } catch (e, st) {
      assert(() {
        debugPrint('tokenizeCues failed: $e\n$st');
        return true;
      }());
      _failTokenizeBatch(generation);
    }
  }

  Future<void> _markBookChapterTokens({
    required int chapterIndex,
    required List<rust_tokenize.CueTokensDto> tokens,
    required int generation,
  }) async {
    try {
      final lemmas = (await widget.dictionaryRepository.list())
          .map((e) => e.lemma)
          .toList(growable: false);
      if (!mounted || generation != _tokenizeGeneration) return;
      final marked = await _mark(cues: tokens, vocabLemmas: lemmas);
      if (!mounted || generation != _tokenizeGeneration) return;
      final normalized = _normalizeCueTokensCache(marked, tokens.length);
      setState(() {
        _cueTokensByIndex = normalized;
        _tokenizeReady = true;
      });
      _chapterTokenCache[chapterIndex] = _ChapterTokenCache(
        tokens: normalized,
        markReady: true,
      );
    } catch (e, st) {
      assert(() {
        debugPrint('markVocabTokens on open failed: $e\n$st');
        return true;
      }());
      if (!mounted || generation != _tokenizeGeneration) return;
      _chapterTokenCache[chapterIndex] = _ChapterTokenCache(
        tokens: tokens,
        markReady: false,
      );
      _showMarkRefreshError();
    }
  }

  /// Re-read Drift morph lemmas → markVocabTokens on live cache (D5 / RH-03/04).
  Future<void> _refreshVocabMarks() async {
    final cache = _cueTokensByIndex;
    if (cache == null || !_tokenizeReady) return;
    final generation = _tokenizeGeneration;
    try {
      final lemmas = (await widget.dictionaryRepository.list())
          .map((e) => e.lemma)
          .toList(growable: false);
      if (!mounted || generation != _tokenizeGeneration) return;
      final marked = await _mark(cues: cache, vocabLemmas: lemmas);
      if (!mounted || generation != _tokenizeGeneration) return;
      final normalized = _normalizeCueTokensCache(marked, cache.length);
      setState(() {
        _cueTokensByIndex = normalized;
      });
      if (_isBookMode) {
        final chapterIndex = _currentChapterIndexClamped;
        _chapterTokenCache[chapterIndex] = _ChapterTokenCache(
          tokens: normalized,
          markReady: true,
        );
        // Other chapters: keep tokens, force re-mark on next visit (D12).
        for (final key in _chapterTokenCache.keys.toList()) {
          if (key == chapterIndex) continue;
          final entry = _chapterTokenCache[key]!;
          _chapterTokenCache[key] = _ChapterTokenCache(
            tokens: entry.tokens,
            markReady: false,
          );
        }
      }
    } catch (e, st) {
      assert(() {
        debugPrint('markVocabTokens refresh failed: $e\n$st');
        return true;
      }());
      if (!mounted || generation != _tokenizeGeneration) return;
      _showMarkRefreshError();
    }
  }

  /// RT-13 / D4: plain text + SnackBar; no token selection.
  void _failTokenizeBatch(int generation) {
    if (!mounted || generation != _tokenizeGeneration) return;
    setState(() {
      _cueTokensByIndex = null;
      _tokenizeReady = false;
      _clearSelection(updateState: false);
    });
    _showTokenizeError();
  }

  void _showTokenizeError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: Key('readerTokenizeErrorSnack'),
        content: Text('Could not prepare word selection'),
      ),
    );
  }

  void _showMarkRefreshError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: Key('readerMarkRefreshErrorSnack'),
        content: Text('Could not refresh vocabulary highlights'),
      ),
    );
  }

  void _clearSelection({bool updateState = true}) {
    _cancelFlash();
    _activeCueIndex = null;
    _selectionStart = null;
    _selectionEnd = null;
    if (updateState && mounted) setState(() {});
  }

  void _cancelFlash() {
    _flashTimer?.cancel();
    _flashTimer = null;
    _flashTokenIndex = null;
  }

  /// Starts gap-reset flash; call **after** setState (no Timer side effects inside).
  void _armFlash(int tokenIndex) {
    _flashTimer?.cancel();
    _flashTokenIndex = tokenIndex;
    _flashTimer = Timer(_gapFlashDuration, () {
      if (!mounted) return;
      setState(() => _flashTokenIndex = null);
    });
  }

  void _onOriginalTokenTap(int cueIndex, int tokenIndex) {
    if (!_tokenizeReady || _cueTokensByIndex == null) return;
    if (cueIndex < 0 || cueIndex >= _cueTokensByIndex!.length) return;
    final tokens = _cueTokensByIndex![cueIndex].tokens;
    if (tokenIndex < 0 || tokenIndex >= tokens.length) return;

    final token = tokens[tokenIndex];
    // in_vocab → clear Add selection → edit sheet (no CTA); D8 resolve.
    if (token.isInVocab) {
      _clearSelection();
      unawaited(
        _openEditVocabSheet(cueIndex: cueIndex, tokenIndex: tokenIndex),
      );
      return;
    }

    var shouldFlash = false;
    setState(() {
      // Other cue → clear previous, start new anchor (no gap-flash).
      if (_activeCueIndex != null && _activeCueIndex != cueIndex) {
        _cancelFlash();
        _activeCueIndex = cueIndex;
        _selectionStart = tokenIndex;
        _selectionEnd = tokenIndex;
        return;
      }

      _activeCueIndex = cueIndex;
      final start = _selectionStart;
      final end = _selectionEnd;

      // Empty → select [T,T].
      if (start == null || end == null) {
        _cancelFlash();
        _selectionStart = tokenIndex;
        _selectionEnd = tokenIndex;
        return;
      }

      final t = tokenIndex;
      // Expand adjacent.
      if (t == start - 1 || t == end + 1) {
        _cancelFlash();
        _selectionStart = t < start ? t : start;
        _selectionEnd = t > end ? t : end;
        return;
      }

      // Inside multi-word range → shrink to [T,T].
      if (t >= start && t <= end && (end - start) >= 1) {
        _cancelFlash();
        _selectionStart = t;
        _selectionEnd = t;
        return;
      }

      // Single selected word tapped again → clear selection (hide CTA).
      if (t == start && t == end) {
        _cancelFlash();
        _activeCueIndex = null;
        _selectionStart = null;
        _selectionEnd = null;
        return;
      }

      // Gap → reset to [T,T] + flash (timer armed after setState).
      _selectionStart = t;
      _selectionEnd = t;
      _flashTokenIndex = t;
      shouldFlash = true;
    });
    if (shouldFlash) _armFlash(tokenIndex);
  }

  /// Display surface for Add sheet: single token surface, or casefold(join).
  String? _selectedDisplaySurface() {
    if (!_hasSelection || _cueTokensByIndex == null) return null;
    final cueIndex = _activeCueIndex!;
    final tokens = _cueTokensByIndex![cueIndex].tokens;
    final start = _selectionStart!;
    final end = _selectionEnd!;
    if (start > end || start < 0 || end >= tokens.length) return null;
    if (start == end) return tokens[start].surface;
    return DictionaryRepository.normalizeSurface(
      tokens.sublist(start, end + 1).map((t) => t.surface).join(' '),
    );
  }

  /// Persist keys for Add: single → morph lemma + surfaceKey; phrase → join.
  ({String lemma, String surfaceKey, String displaySurface})?
      _selectedPersistKeys() {
    if (!_hasSelection || _cueTokensByIndex == null) return null;
    final cueIndex = _activeCueIndex!;
    final tokens = _cueTokensByIndex![cueIndex].tokens;
    final start = _selectionStart!;
    final end = _selectionEnd!;
    if (start > end || start < 0 || end >= tokens.length) return null;
    if (start == end) {
      final t = tokens[start];
      return (
        lemma: t.lemmaKey,
        surfaceKey: DictionaryRepository.normalizeSurface(t.surface),
        displaySurface: t.surface,
      );
    }
    final joined = DictionaryRepository.normalizeSurface(
      tokens.sublist(start, end + 1).map((t) => t.surface).join(' '),
    );
    return (lemma: joined, surfaceKey: joined, displaySurface: joined);
  }

  String? _activeCueText() {
    if (!_hasSelection) return null;
    final cueIndex = _activeCueIndex!;
    if (_isBookMode) {
      final paragraphs = _currentChapterParagraphs;
      if (cueIndex < 0 || cueIndex >= paragraphs.length) return null;
      return paragraphs[cueIndex];
    }
    if (cueIndex < 0 || cueIndex >= widget.originalCues.length) return null;
    return widget.originalCues[cueIndex].textLines.join('\n');
  }

  /// Display-only CueDto adapters for paragraph rows (D4). Times are unused.
  List<rust_parse.CueDto> _paragraphDisplayCues(List<String> paragraphs) {
    return [
      for (var i = 0; i < paragraphs.length; i++)
        rust_parse.CueDto(
          index: i,
          startMs: BigInt.zero,
          endMs: BigInt.zero,
          textLines: [paragraphs[i]],
        ),
    ];
  }

  /// Shared 0-based chapter index for both EPUB panes (D5 / RS-14).
  ///
  /// Each pane clamps for display when N differs (RS-16).
  void _goToChapter(int next) {
    if (!_isBookMode) return;
    if (_originalChapters.isEmpty && !_hasTranslationChapters) return;
    final maxOrig =
        _originalChapters.isEmpty ? 0 : _originalChapters.length - 1;
    final maxTrans = _hasTranslationChapters
        ? _translationChapters!.length - 1
        : maxOrig;
    final maxShared = maxOrig > maxTrans ? maxOrig : maxTrans;
    final clamped = next.clamp(0, maxShared);
    if (clamped == _chapterIndex) return;

    final prevOrig = _originalChapters.isEmpty
        ? 0
        : _chapterIndex.clamp(0, maxOrig);
    final nextOrig =
        _originalChapters.isEmpty ? 0 : clamped.clamp(0, maxOrig);
    final origChapterChanged =
        _originalChapters.isNotEmpty && nextOrig != prevOrig;

    setState(() {
      _chapterIndex = clamped;
      if (origChapterChanged) {
        _clearSelection(updateState: false);
        // RC-09: restore from session cache when available; else clear until batch.
        final cached = _chapterTokenCache[nextOrig];
        if (cached != null) {
          _cueTokensByIndex = cached.tokens;
          _tokenizeReady = true;
        } else {
          _cueTokensByIndex = null;
          _tokenizeReady = false;
        }
        // Invalidate in-flight tokenize before starting the next batch so a
        // slower chapter-A response cannot bind onto chapter-B paragraphs.
        _tokenizeGeneration++;
      }
    });
    // ListView key includes chapter index → remount resets scroll to start (RC-02).
    if (origChapterChanged) {
      // Cache hit still runs through _runBookChapterTokenize for optional re-mark.
      unawaited(_runBatchTokenize());
    }
    // Persist chapter index on pager settle (LD-28 / RC-06); not nearestCueIndex.
    unawaited(_persistReadingAnchor(force: true));
  }

  /// D8: longest phrase span covering [tokenIndex] > shorter > single morph.
  Future<String?> _resolveEditLemmaKey({
    required int cueIndex,
    required int tokenIndex,
  }) async {
    final cache = _cueTokensByIndex;
    if (cache == null || cueIndex < 0 || cueIndex >= cache.length) {
      return null;
    }
    final tokens = cache[cueIndex].tokens;
    if (tokenIndex < 0 || tokenIndex >= tokens.length) return null;

    final entries = await widget.dictionaryRepository.list();
    // Match on collapsed join; return Drift lemma for lookup (may differ only
    // by irregular whitespace on legacy rows).
    final phrases = <({String matchKey, String driftLemma, int wordCount})>[];
    for (final e in entries) {
      final matchKey = DictionaryRepository.normalizeSurface(e.lemma);
      if (matchKey.isEmpty) continue;
      if (matchKey.contains(RegExp(r'\s'))) {
        final wordCount = matchKey.split(RegExp(r'\s+')).length;
        if (wordCount >= 2) {
          phrases.add((
            matchKey: matchKey,
            driftLemma: e.lemma,
            wordCount: wordCount,
          ));
        }
      }
    }
    phrases.sort((a, b) => b.wordCount.compareTo(a.wordCount));

    final n = tokens.length;
    for (final phrase in phrases) {
      final w = phrase.wordCount;
      if (w > n) continue;
      for (var start = 0; start <= n - w; start++) {
        final end = start + w - 1;
        if (tokenIndex < start || tokenIndex > end) continue;
        final joined = tokens
            .sublist(start, end + 1)
            .map((t) => DictionaryRepository.normalizeSurface(t.surface))
            .join(' ');
        if (joined == phrase.matchKey) return phrase.driftLemma;
      }
    }
    return tokens[tokenIndex].lemmaKey;
  }

  Future<void> _openAddVocabSheet() async {
    final keys = _selectedPersistKeys();
    final cueText = _activeCueText();
    if (keys == null || cueText == null || keys.displaySurface.isEmpty) {
      return;
    }

    final scrollAnchor = _captureOriginalScrollAnchor();
    _scheduleOriginalScrollRestore(scrollAnchor);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _AddVocabSheet(
          surface: keys.displaySurface,
          lemmaKey: keys.lemma,
          surfaceKey: keys.surfaceKey,
          initialContext: cueText,
          dictionaryRepository: widget.dictionaryRepository,
          offlineTranslate: _offlineTranslate,
        );
      },
    );

    if (!mounted) return;
    _restoreOriginalScrollAnchor(scrollAnchor);
    if (saved == true) {
      _clearSelection();
      await _refreshVocabMarks();
    }
  }

  Future<void> _openEditVocabSheet({
    required int cueIndex,
    required int tokenIndex,
  }) async {
    final cache = _cueTokensByIndex;
    if (cache == null || cueIndex < 0 || cueIndex >= cache.length) return;
    final tokens = cache[cueIndex].tokens;
    if (tokenIndex < 0 || tokenIndex >= tokens.length) return;

    final lemmaKey = await _resolveEditLemmaKey(
      cueIndex: cueIndex,
      tokenIndex: tokenIndex,
    );
    if (!mounted || lemmaKey == null) return;

    final entry = await widget.dictionaryRepository.lookup(lemmaKey);
    if (!mounted) return;
    if (entry == null) {
      // Stale flag / race — fall back to Add selection on the tapped token.
      setState(() {
        _cancelFlash();
        _activeCueIndex = cueIndex;
        _selectionStart = tokenIndex;
        _selectionEnd = tokenIndex;
      });
      return;
    }

    // Display surface: phrase key as joined words, else token surface.
    final displaySurface = entry.lemma.contains(RegExp(r'\s'))
        ? entry.lemma
        : tokens[tokenIndex].surface;

    final scrollAnchor = _captureOriginalScrollAnchor();
    _scheduleOriginalScrollRestore(scrollAnchor);

    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _EditVocabSheet(
          entry: entry,
          surface: displaySurface,
          dictionaryRepository: widget.dictionaryRepository,
          offlineTranslate: _offlineTranslate,
        );
      },
    );

    if (!mounted) return;
    _restoreOriginalScrollAnchor(scrollAnchor);
    if (changed == true) {
      await _refreshVocabMarks();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('readerTranslationErrorSnack'),
        content: Text(message),
      ),
    );
  }

  void _showVideoError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('readerVideoErrorSnack'),
        content: Text(message),
      ),
    );
  }

  /// Prefer durable Drift media → session playback ref; else sandbox/path.
  /// Dead link still yields a weak ref so JPEG cache can show (LD-22).
  Future<String?> _resolveVideoRef(VideoAttachment attachment) async {
    if (attachment.hasStoredMedia) {
      final media = await widget.documentRepository
          .getVideoMedia(widget.originalDocumentId);
      if (media != null && media.bytes.isNotEmpty) {
        return playbackRefFromMediaBytes(
          bytes: media.bytes,
          fileName: media.fileName,
          documentId: '${widget.originalDocumentId}',
        );
      }
    }
    final sandbox = attachment.sandboxPath;
    if (sandbox == 'drift-media') {
      return null;
    }
    if (isUsableFilesystemPath(sandbox)) return sandbox;
    final uri = attachment.videoUri;
    if (isUsableFilesystemPath(uri)) return uri;
    // Avoid restoring ephemeral blob: URLs (die after reload).
    if (sandbox != null &&
        sandbox.isNotEmpty &&
        !sandbox.startsWith('blob:')) {
      return sandbox;
    }
    if (uri != null && uri.isNotEmpty && !uri.startsWith('blob:')) {
      return uri;
    }
    return null;
  }

  Future<void> _hydrateVideoAttachment(VideoAttachment attachment) async {
    if (attachment.durationSec < 1) return;
    final ref = await _resolveVideoRef(attachment);
    if (!mounted) return;
    if (ref == null) {
      // Meta present but no playable ref — still expose duration for cache-only
      // pages if we have a sentinel; without ref pages cannot extract.
      return;
    }
    final lastSecond = attachment.lastFramePage;
    final jumpSecond = lastSecond != null
        ? clampReadingTimeToSecond(lastSecond * 1000, attachment.durationSec)
        : clampReadingTimeToSecond(
            widget.initialReadingAnchor?.startMs ?? 0,
            attachment.durationSec,
          );
    final safeSecond = jumpSecond < 0 ? 0 : jumpSecond;
    setState(() {
      _videoRef = ref;
      _videoTotalSeconds = attachment.durationSec;
      _videoInitialSecond = safeSecond;
      _videoCurrentSecond = safeSecond;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hasVideo) return;
      _videoPagesKey.currentState?.jumpToSecond(_videoInitialSecond);
    });
  }

  Future<void> _loadVideoAttachmentBestEffort() async {
    try {
      final attachment = await widget.documentRepository
          .getVideoAttachment(widget.originalDocumentId);
      if (!mounted || attachment == null) return;
      await _hydrateVideoAttachment(attachment);
    } catch (e, st) {
      assert(() {
        debugPrint('getVideoAttachment failed (ignored): $e\n$st');
        return true;
      }());
    }
  }

  /// Reading time before Load transform (visible cue top, video page second, or
  /// reading anchor) — VF-05 / D6.
  int _currentReadingTimeMs() {
    if (_hasVideo) {
      final second = _videoPagesKey.currentState?.currentSecond ??
          _videoCurrentSecond;
      return second * 1000;
    }
    final top = _topVisible(_originalPositions);
    if (top != null &&
        top.index >= 0 &&
        top.index < widget.originalCues.length) {
      return widget.originalCues[top.index].startMs.toInt();
    }
    return widget.initialReadingAnchor?.startMs ?? 0;
  }

  Future<void> _loadVideo() async {
    if (_loadingVideo) return;
    // Capture before async pick so jump reflects cue-list position (VF-05).
    final readingTimeMs = _currentReadingTimeMs();
    setState(() => _loadingVideo = true);
    try {
      final pick = widget.videoPicker != null
          ? await widget.videoPicker!()
          : await defaultReaderVideoPicker();
      if (pick == null || !mounted) return;

      final resolve =
          widget.resolveUsableVideoPath ?? video_path.resolveUsableVideoPath;
      final usable = await resolve(
        pick.toPickedVideoSource(),
        documentId: '${widget.originalDocumentId}',
      );
      if (!mounted) return;

      final duration = await _videoExtractor.probeDuration(usable.filesystemPath);
      if (!mounted) return;
      final totalSeconds = duration.inSeconds;
      if (totalSeconds < 1) {
        _showVideoError(
          videoFrameUserMessage(VideoFrameErrorKind.probeFailed),
        );
        return;
      }

      // LD-22: same duration re-pick (dead link) keeps JPEG cache.
      // LD-23 / VF replace: different duration → clear prior frames.
      final previous = await widget.documentRepository
          .getVideoAttachment(widget.originalDocumentId);
      if (!mounted) return;
      final clearFrameCache =
          previous == null || previous.durationSec != totalSeconds;
      final jumpSecond = !clearFrameCache && _hasVideo
          ? (_videoPagesKey.currentState?.currentSecond ??
              _videoCurrentSecond)
          : clampReadingTimeToSecond(readingTimeMs, totalSeconds);
      final safeSecond = jumpSecond < 0 ? 0 : jumpSecond;

      final mediaBytes = pick.bytes ?? await pick.readBytes?.call();
      if (!mounted) return;
      // Web: never persist ephemeral blob: URLs — store bytes + sentinel.
      // Native: keep sandbox filesystem path for FFmpeg.
      final persistSandbox =
          kIsWeb ? 'drift-media' : usable.filesystemPath;

      await widget.documentRepository.attachVideo(
        documentId: widget.originalDocumentId,
        videoUri: usable.originalUri ?? pick.originalUri ?? usable.filesystemPath,
        sandboxPath: persistSandbox,
        durationSec: totalSeconds,
        lastFramePage: safeSecond,
        clearFrameCache: clearFrameCache,
        mediaBytes: mediaBytes,
        mediaFileName: pick.fileName,
      );
      if (!mounted) return;

      // Session ref: live usable path (blob or file) for this run.
      setState(() {
        _videoRef = usable.filesystemPath;
        _videoTotalSeconds = totalSeconds;
        _videoInitialSecond = safeSecond;
        _videoCurrentSecond = safeSecond;
        if (widget.videoFrameCache == null) {
          _videoCache = DocumentRepositoryVideoFrameCache(
            widget.documentRepository,
            widget.originalDocumentId,
          );
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _videoPagesKey.currentState?.jumpToSecond(safeSecond);
        if (_splitEnabled && _hasTranslationCues) {
          unawaited(_syncTranslationToTimeMs(safeSecond * 1000));
        }
      });
    } on VideoFrameException catch (e) {
      _showVideoError(e.userMessage);
    } catch (e, st) {
      assert(() {
        debugPrint('Load video failed: $e\n$st');
        return true;
      }());
      _showVideoError(videoFrameUserMessage(VideoFrameErrorKind.probeFailed));
    } finally {
      if (mounted) {
        setState(() => _loadingVideo = false);
      }
    }
  }

  Future<void> _removeVideo() async {
    if (!_hasVideo || _loadingVideo) return;
    final second = _videoPagesKey.currentState?.currentSecond ??
        _videoCurrentSecond;
    setState(() => _loadingVideo = true);
    try {
      await widget.documentRepository.detachVideo(widget.originalDocumentId);
      if (!mounted) return;
      final restoreIndex = widget.originalCues.isEmpty
          ? 0
          : nearestCueIndex(
              widget.originalCues,
              BigInt.from(second * 1000),
            ).clamp(0, widget.originalCues.length - 1);
      setState(() {
        _videoRef = null;
        _videoTotalSeconds = 0;
        _videoInitialSecond = 0;
        _videoCurrentSecond = 0;
        _originalInitialScrollIndex = restoreIndex;
        _originalInitialAlignment = 0;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.originalCues.isNotEmpty &&
            _originalScrollController.isAttached) {
          _originalScrollController.jumpTo(
            index: restoreIndex,
            alignment: 0,
          );
        }
        if (_splitEnabled && _hasTranslationCues) {
          unawaited(
            _syncPanes(
              fromOriginal: true,
              sourceIndex: restoreIndex,
              sourceAlignment: 0,
            ),
          );
        }
      });
    } on LibraryValidationException catch (e) {
      _showVideoError(e.message);
    } catch (e, st) {
      assert(() {
        debugPrint('Remove video failed: $e\n$st');
        return true;
      }());
      _showVideoError("Couldn't remove video. Try again.");
    } finally {
      if (mounted) {
        setState(() => _loadingVideo = false);
      }
    }
  }

  Future<void> _persistVideoLastSecond(int second) async {
    try {
      await widget.documentRepository.saveVideoLastFramePage(
        documentId: widget.originalDocumentId,
        lastFramePage: second,
      );
    } catch (e, st) {
      assert(() {
        debugPrint('saveVideoLastFramePage failed (ignored): $e\n$st');
        return true;
      }());
    }
  }

  /// Page change → translation sync (one-way) + persist last_second (D6 / VF-06).
  void _onVideoPageChanged(int page) {
    final first = videoFramePageFirstSecond(page, _videoTotalSeconds);
    final second = first < 0 ? 0 : first;
    _videoCurrentSecond = second;
    _videoInitialSecond = second;
    unawaited(_persistVideoLastSecond(second));
    if (_splitEnabled && _hasTranslationCues) {
      unawaited(_syncTranslationToTimeMs(second * 1000));
    }
  }

  /// Sync translation pane to [timeMs] without moving the video pages.
  Future<void> _syncTranslationToTimeMs(int timeMs, {int attempt = 0}) async {
    if (_syncing || !_splitEnabled) return;
    final translation = _translationCues;
    if (translation == null || translation.isEmpty) return;

    if (!_translationScrollController.isAttached) {
      if (attempt >= 8) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_syncTranslationToTimeMs(timeMs, attempt: attempt + 1));
      });
      return;
    }

    final nearest = nearestCueIndex(translation, BigInt.from(timeMs));
    if (nearest < 0) return;

    _syncing = true;
    try {
      if (!_translationScrollController.isAttached) return;
      // Jump (not animated scroll): page/second changes are discrete and
      // must not leave the bottom pane mid-animation in tests / remounts.
      _translationScrollController.jumpTo(index: nearest, alignment: 0);
    } finally {
      _syncing = false;
    }
  }

  void _toggleSplit() {
    // Book mode: chapter index is session state (no cue-list remount).
    if (_isBookMode) {
      setState(() => _splitEnabled = !_splitEnabled);
      return;
    }

    // RS-10 / RS-11 / D7: remounting the original list resets scroll — capture
    // top-visible anchor before Show *and* Hide; seed initialScrollIndex so
    // the first painted frame is not cue 0; jumpTo after layout as backup.
    // With video: preserve page second (VF-09); do not reset to 0.
    final enabling = !_splitEnabled;
    final restoreSecond = _hasVideo
        ? (_videoPagesKey.currentState?.currentSecond ??
            _videoCurrentSecond)
        : null;
    final anchor = _hasVideo ? null : _topVisible(_originalPositions);
    final restoreIndex = (anchor?.index ?? 0).clamp(
      0,
      widget.originalCues.isEmpty ? 0 : widget.originalCues.length - 1,
    );
    final restoreAlignment =
        (anchor?.itemLeadingEdge ?? 0.0).clamp(0.0, 1.0);

    setState(() {
      if (restoreSecond != null) {
        _videoInitialSecond = restoreSecond;
        _videoCurrentSecond = restoreSecond;
      } else {
        _originalInitialScrollIndex = restoreIndex;
        _originalInitialAlignment = restoreAlignment;
      }
      _splitEnabled = enabling;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hasVideo) {
        final second = restoreSecond ?? _videoCurrentSecond;
        _videoPagesKey.currentState?.jumpToSecond(second);
        if (enabling && _hasTranslationCues) {
          unawaited(_syncTranslationToTimeMs(second * 1000));
        }
        return;
      }
      if (widget.originalCues.isNotEmpty &&
          _originalScrollController.isAttached) {
        _originalScrollController.jumpTo(
          index: restoreIndex,
          alignment: restoreAlignment,
        );
      }
      // Show + translation: sync from *captured* original anchor. Re-reading
      // ItemPositionsListener right after remount often still reports cue 0;
      // the translation ItemScrollController may also not be attached yet.
      if (enabling && _hasTranslationCues) {
        unawaited(
          _syncPanes(
            fromOriginal: true,
            sourceIndex: restoreIndex,
            sourceAlignment: restoreAlignment,
          ),
        );
      }
    });
  }

  void _restoreInitialReadingAnchor({int attempt = 0}) {
    if (_didRestoreInitialAnchor || !mounted) return;

    // VF-13: with video, pages already have initialSecond / last_second.
    if (_hasVideo) {
      _didRestoreInitialAnchor = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _videoPagesKey.currentState?.jumpToSecond(_videoInitialSecond);
        if (_hasTranslationCues && _splitEnabled) {
          unawaited(_syncTranslationToTimeMs(_videoInitialSecond * 1000));
        }
      });
      return;
    }

    final saved = widget.initialReadingAnchor;
    if (saved == null || widget.originalCues.isEmpty) {
      _didRestoreInitialAnchor = true;
      return;
    }
    if (!_originalScrollController.isAttached) {
      if (attempt >= 5) {
        _didRestoreInitialAnchor = true;
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreInitialReadingAnchor(attempt: attempt + 1);
      });
      return;
    }

    _didRestoreInitialAnchor = true;
    final index = nearestCueIndex(
      widget.originalCues,
      BigInt.from(saved.startMs),
    );
    if (index < 0) return;
    final alignment = (saved.alignment ?? 0.0).clamp(0.0, 1.0);
    _originalScrollController.jumpTo(index: index, alignment: alignment);

    if (_hasTranslationCues && _splitEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncPanes(fromOriginal: true);
      });
    }
  }

  Future<void> _persistReadingAnchor({bool force = false}) async {
    // D10: never write while programmatic sync is in flight (unless pop/dispose).
    if (!force && _syncing) return;

    if (_isBookMode) {
      // LD-28 / D6: lastReadStartMs = 0-based chapter index for EPUB.
      if (_originalChapters.isEmpty) return;
      try {
        await widget.documentRepository.saveReadingAnchor(
          documentId: widget.originalDocumentId,
          startMs: _chapterIndex.clamp(0, _originalChapters.length - 1),
          alignment: null,
        );
      } catch (e, st) {
        assert(() {
          debugPrint('saveReadingAnchor (epub) failed: $e\n$st');
          return true;
        }());
      }
      return;
    }

    if (widget.originalCues.isEmpty) return;

    final top = _topVisible(_originalPositions);
    if (top == null) return;
    final index = top.index;
    if (index < 0 || index >= widget.originalCues.length) return;

    // Best-effort: fail MUST NOT block UI (D10). Whole body in try (incl. toInt).
    try {
      final startMs = widget.originalCues[index].startMs.toInt();
      final alignment = top.itemLeadingEdge.clamp(0.0, 1.0);
      await widget.documentRepository.saveReadingAnchor(
        documentId: widget.originalDocumentId,
        startMs: startMs,
        alignment: alignment,
      );
    } catch (e, st) {
      assert(() {
        debugPrint('saveReadingAnchor failed: $e\n$st');
        return true;
      }());
    }
  }

  Future<PickedTranslationFile?> _defaultPick() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return null;
    final file = files.first;
    final bytes = await file.readAsBytes();
    return PickedTranslationFile(fileName: file.name, bytes: bytes);
  }

  Future<void> _loadTranslation() async {
    // One slot per original: delete first when a link exists (RS-07 / D5).
    if (_loadingTranslation ||
        _hasTranslationCues ||
        _hasTranslationChapters ||
        _hasLinkedTranslation) {
      return;
    }
    setState(() => _loadingTranslation = true);
    try {
      final picked = widget.filePicker != null
          ? await widget.filePicker!()
          : await _defaultPick();
      if (picked == null || !mounted) return;

      final formatHint = formatFromFileName(picked.fileName);

      if (_isBookMode) {
        // LD-26: EPUB original accepts only .epub translation.
        if (!isEpubFormat(formatHint)) {
          _showError(incompatibleTranslationFormatMessage);
          return;
        }
        final parsed = await _parseEpub(bytes: picked.bytes);
        if (!mounted) return;
        if (parsed.chapters.isEmpty) {
          _showError(
            messageForEpubParseError(rust_epub.EpubParseErrorKind.empty),
          );
          return;
        }
        final attached = await widget.documentRepository.attachTranslation(
          originalDocumentId: widget.originalDocumentId,
          fileName: picked.fileName,
          bytes: picked.bytes,
        );
        if (!mounted) return;
        // RS-16 / D5: unequal N → noticeable error; still attach + clamp display.
        final mismatched =
            _originalChapters.isNotEmpty &&
            parsed.chapters.length != _originalChapters.length;
        setState(() {
          _translationChapters = parsed.chapters;
          _translationDocumentId = attached.id;
        });
        if (mismatched) {
          _showError(mismatchedEpubChapterCountMessage);
        }
        return;
      }

      // LD-26 / D5: subtitle original accepts only subtitle translations.
      if (isEpubFormat(formatHint)) {
        _showError(incompatibleTranslationFormatMessage);
        return;
      }

      final parsed = await _parse(
        bytes: picked.bytes,
        formatHint: formatHint,
      );
      if (!mounted) return;
      if (parsed.cues.isEmpty) {
        _showError(messageForParseError(rust_parse.ParseErrorKind.empty));
        return;
      }

      final attached = await widget.documentRepository.attachTranslation(
        originalDocumentId: widget.originalDocumentId,
        fileName: picked.fileName,
        bytes: picked.bytes,
      );
      if (!mounted) return;

      setState(() {
        _translationCues = parsed.cues;
        _translationDocumentId = attached.id;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_hasVideo) {
          final second = _videoPagesKey.currentState?.currentSecond ??
              _videoCurrentSecond;
          unawaited(_syncTranslationToTimeMs(second * 1000));
        } else {
          unawaited(_syncPanes(fromOriginal: true));
        }
      });
    } on rust_epub.EpubParseErrorKind catch (kind) {
      _showError(messageForEpubParseError(kind));
    } on rust_parse.ParseErrorKind catch (kind) {
      _showError(messageForParseError(kind));
    } on LibraryValidationException catch (e) {
      _showError(e.message);
    } on AnyhowException catch (e) {
      assert(() {
        debugPrint('FRB Anyhow loading translation: ${e.message}');
        return true;
      }());
      _showError('Could not load document');
    } on PanicException catch (e) {
      assert(() {
        debugPrint('Rust panic loading translation: ${e.message}');
        return true;
      }());
      _showError('Could not load document');
    } catch (e, st) {
      assert(() {
        debugPrint('Load translation failed: $e\n$st');
        return true;
      }());
      _showError('Could not load document');
    } finally {
      if (mounted) {
        setState(() => _loadingTranslation = false);
      }
    }
  }

  Future<void> _deleteTranslation() async {
    if (!_hasTranslationCues &&
        !_hasTranslationChapters &&
        !_hasLinkedTranslation) {
      return;
    }
    try {
      await widget.documentRepository.detachAndDeleteTranslation(
        widget.originalDocumentId,
      );
      if (!mounted) return;
      setState(() {
        _translationCues = null;
        _translationChapters = null;
        _translationDocumentId = null;
      });
    } on LibraryValidationException catch (e) {
      _showError(e.message);
    } catch (e, st) {
      assert(() {
        debugPrint('Delete translation failed: $e\n$st');
        return true;
      }());
      _showError('Could not delete translation');
    }
  }

  ItemPosition? _topVisible(ItemPositionsListener listener) {
    final positions = listener.itemPositions.value;
    ItemPosition? best;
    for (final p in positions) {
      if (p.itemTrailingEdge <= 0 || p.itemLeadingEdge >= 1) continue;
      if (best == null ||
          p.itemLeadingEdge < best.itemLeadingEdge ||
          (p.itemLeadingEdge == best.itemLeadingEdge && p.index < best.index)) {
        best = p;
      }
    }
    return best;
  }

  ({int index, double alignment}) _captureOriginalScrollAnchor() {
    final anchor = _topVisible(_originalPositions);
    final maxIndex =
        widget.originalCues.isEmpty ? 0 : widget.originalCues.length - 1;
    return (
      index: (anchor?.index ?? 0).clamp(0, maxIndex),
      alignment: (anchor?.itemLeadingEdge ?? 0.0).clamp(0.0, 1.0),
    );
  }

  void _restoreOriginalScrollAnchor(({int index, double alignment}) anchor) {
    if (!mounted || widget.originalCues.isEmpty) return;
    if (!_originalScrollController.isAttached) return;
    _originalScrollController.jumpTo(
      index: anchor.index,
      alignment: anchor.alignment,
    );
  }

  /// Re-apply scroll after sheet/keyboard layout pulses (same idea as split).
  void _scheduleOriginalScrollRestore(({int index, double alignment}) anchor) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _restoreOriginalScrollAnchor(anchor);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _restoreOriginalScrollAnchor(anchor);
      });
    });
  }

  Future<void> _syncPanes({
    required bool fromOriginal,
    int? sourceIndex,
    double? sourceAlignment,
    int attempt = 0,
  }) async {
    if (_syncing || !_splitEnabled) return;
    final translation = _translationCues;
    if (translation == null || translation.isEmpty) return;
    if (widget.originalCues.isEmpty) return;

    // Video replaces the original cue list: VF-07 blocks bottom→original;
    // original→bottom must use page second (not detached cue positions).
    if (_hasVideo) {
      if (!fromOriginal) return;
      final second = _videoPagesKey.currentState?.currentSecond ??
          _videoCurrentSecond;
      await _syncTranslationToTimeMs(second * 1000);
      return;
    }

    final sourceListener =
        fromOriginal ? _originalPositions : _translationPositions;
    final sourceCues = fromOriginal ? widget.originalCues : translation;
    final targetCues = fromOriginal ? translation : widget.originalCues;
    final targetController =
        fromOriginal ? _translationScrollController : _originalScrollController;

    // Bottom (or remounted) list may not have attached the scroll controller
    // on the first post-frame after Show/load — retry instead of no-op @ 0.
    if (!targetController.isAttached) {
      if (attempt >= 8) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          _syncPanes(
            fromOriginal: fromOriginal,
            sourceIndex: sourceIndex,
            sourceAlignment: sourceAlignment,
            attempt: attempt + 1,
          ),
        );
      });
      return;
    }

    final anchor =
        sourceIndex == null ? _topVisible(sourceListener) : null;
    final anchorIndex = sourceIndex ?? anchor?.index ?? 0;
    if (anchorIndex < 0 || anchorIndex >= sourceCues.length) return;

    final nearest =
        nearestCueIndex(targetCues, sourceCues[anchorIndex].startMs);
    if (nearest < 0) return;

    // Pixel settle: match source anchor leading-edge within the viewport.
    final alignment = (sourceAlignment ?? anchor?.itemLeadingEdge ?? 0.0)
        .clamp(0.0, 1.0);

    _syncing = true;
    try {
      if (!targetController.isAttached) return;
      // (1) Time match — nearest CueDto.startMs → scroll-to-index.
      await targetController.scrollTo(
        index: nearest,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        alignment: 0,
      );
      if (!mounted || !targetController.isAttached) return;
      // (2) Pixel settle after time jump (alignment mirror, not continuous offset).
      targetController.jumpTo(index: nearest, alignment: alignment);
    } finally {
      _syncing = false;
    }
  }

  bool _onScrollNotification(
    ScrollNotification notification, {
    required bool fromOriginal,
  }) {
    // Only pointer drags arm settle-sync / settle-persist. Programmatic
    // scrollTo/jumpTo also emit scrollDelta without dragDetails — treating
    // those as user input re-enters A↔B after `_syncing` clears (RS-06).
    // Wheel/trackpad: no dragDetails → no settle sync; dispose still persists.
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _userInitiatedScroll = true;
    }
    if (notification is! ScrollEndNotification) return false;
    if (!_userInitiatedScroll) return false;

    final userScroll = _userInitiatedScroll;
    _userInitiatedScroll = false;

    // RS-12 / D10: persist original anchor on user settle (skip while syncing).
    if (fromOriginal && userScroll && !_syncing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _persistReadingAnchor();
      });
    }

    if (_syncing || !_splitEnabled) return false;
    // Book mode syncs by chapter index (pager), not cue startMs (RS-05/06 vs RS-14).
    if (_isBookMode) return false;
    if (_translationCues == null || _translationCues!.isEmpty) return false;
    // VF-07 / D6: with video, bottom scroll must not move original pages.
    if (_hasVideo && !fromOriginal) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPanes(fromOriginal: fromOriginal);
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('readerScreen'),
      // Sheet handles keyboard via viewInsets; resizing body jumps
      // ScrollablePositionedList toward the top.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          key: const Key('readerBack'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!_isBookMode) ...[
            IconButton(
              key: const Key('readerLoadVideo'),
              tooltip: _hasVideo ? 'Replace video' : 'Load video',
              icon: _loadingVideo
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.video_file_outlined),
              onPressed: _loadingVideo ? null : _loadVideo,
            ),
            if (_hasVideo)
              IconButton(
                key: const Key('readerRemoveVideo'),
                tooltip: 'Remove video',
                icon: const Icon(Icons.videocam_off_outlined),
                onPressed: _loadingVideo ? null : _removeVideo,
              ),
          ],
          IconButton(
            key: const Key('readerSplitToggle'),
            tooltip: _splitEnabled ? 'Hide split' : 'Show split',
            icon: Icon(
              _splitEnabled ? Icons.vertical_split : Icons.vertical_split_outlined,
            ),
            onPressed: _toggleSplit,
          ),
        ],
      ),
      // D4 revision 2: paged frames replace original cue body (not a strip).
      // Book mode: chapter paragraphs (full pager chrome in Block 3).
      body: _isBookMode
          ? (_splitEnabled ? _buildBookSplitBody() : _buildBookPane())
          : (_splitEnabled ? _buildSplitBody() : _buildSinglePane()),
      // D6: CTA when selection non-empty; sheet/save is block 3.
      bottomNavigationBar: _hasSelection ? _buildAddVocabCta() : null,
    );
  }

  /// EPUB book pane: paragraph list + bottom chapter pager (RC-01…RC-04).
  Widget _buildBookPane() {
    return _buildBookPaneContent(
      chapters: _originalChapters,
      paneKey: const Key('readerBookPane'),
      emptyKey: const Key('readerBookEmpty'),
      titleKeyPrefix: 'readerBookChapterTitle',
      listKey: const Key('readerBookParagraphList'),
      listKeyPrefix: 'readerBookParagraphList',
      prevKey: const Key('readerBookChapterPrev'),
      pagerKey: const Key('readerBookChapterPager'),
      nextKey: const Key('readerBookChapterNext'),
      cueKeyPrefix: 'readerCue',
      fromOriginal: true,
      interactive: true,
    );
  }

  /// Shared chapter book column for original or translation (D5 / RS-13…RS-15).
  Widget _buildBookPaneContent({
    required List<rust_epub.EpubChapterDto> chapters,
    required Key paneKey,
    required Key emptyKey,
    required String titleKeyPrefix,
    required Key listKey,
    required String listKeyPrefix,
    required Key prevKey,
    required Key pagerKey,
    required Key nextKey,
    required String cueKeyPrefix,
    required bool fromOriginal,
    required bool interactive,
  }) {
    if (chapters.isEmpty) {
      return Center(
        key: emptyKey,
        child: const Text('No chapters'),
      );
    }
    // Shared index; clamp per pane when N differs (RS-16).
    final index = _chapterIndex.clamp(0, chapters.length - 1);
    final chapter = chapters[index];
    final paragraphs = chapter.paragraphs;
    final displayCues = _paragraphDisplayCues(paragraphs);
    final pageCount = chapters.length;
    final canPrev = index > 0;
    final canNext = index < pageCount - 1;

    return Column(
      key: paneKey,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            chapter.title,
            key: Key('${titleKeyPrefix}_$index'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: KeyedSubtree(
            key: listKey,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) =>
                  _onScrollNotification(n, fromOriginal: fromOriginal),
              child: ListView.builder(
                // Remount per chapter so scroll resets to start (RC-02).
                key: Key('${listKeyPrefix}_$index'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: displayCues.length,
                itemBuilder: (context, i) {
                  if (!interactive) {
                    return CueRow(
                      cue: displayCues[i],
                      keyPrefix: cueKeyPrefix,
                      cueListIndex: i,
                      showTimestamp: false,
                    );
                  }
                  final tokensReady = _tokenizeReady &&
                      _cueTokensByIndex != null &&
                      i < _cueTokensByIndex!.length;
                  final tokens =
                      tokensReady ? _cueTokensByIndex![i].tokens : null;
                  final isActive = _hasSelection && _activeCueIndex == i;
                  return CueRow(
                    cue: displayCues[i],
                    keyPrefix: cueKeyPrefix,
                    cueListIndex: i,
                    tokens: tokens,
                    selectionStart: isActive ? _selectionStart : null,
                    selectionEnd: isActive ? _selectionEnd : null,
                    flashTokenIndex: isActive ? _flashTokenIndex : null,
                    onTokenTap:
                        tokensReady && tokens != null && tokens.isNotEmpty
                            ? (tokenIndex) =>
                                _onOriginalTokenTap(i, tokenIndex)
                            : null,
                    // D4 / RC-04: no timed cue chrome on paragraphs.
                    showTimestamp: false,
                    // D11 / RC-07: TextSpan + one gesture; no WidgetSpan-per-word.
                    lightweightHitTest: true,
                  );
                },
              ),
            ),
          ),
        ),
        // Bottom chapter pager — same chrome pattern as VideoFramePages (RC-02/03).
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Row(
              children: [
                IconButton(
                  key: prevKey,
                  tooltip: 'Previous chapter',
                  // Drive shared index from this pane's displayed chapter (RS-14).
                  onPressed: canPrev ? () => _goToChapter(index - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${index + 1} / $pageCount',
                    key: pagerKey,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  key: nextKey,
                  tooltip: 'Next chapter',
                  onPressed: canNext ? () => _goToChapter(index + 1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBookSplitBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Build panes outside ValueListenableBuilder so drag only changes
        // SizedBox heights (D13 / RS-17) — same child widget instances reused.
        final topPane = _buildBookPane();
        final bottomPane = _buildBookBottomPane();
        final dividerColor =
            Theme.of(context).colorScheme.surfaceContainerHighest;
        final outlineColor = Theme.of(context).colorScheme.outline;

        return ValueListenableBuilder<double>(
          valueListenable: _bookDividerRatio,
          builder: (context, ratio, _) {
            final usable = constraints.maxHeight - _dividerHandleHeight;
            final needsDeleteChrome =
                _hasTranslationChapters || _hasLinkedTranslation;
            final ratioMin = usable * _minRatio;
            final chromeFloor = usable < kMinInteractiveDimension
                ? usable
                : kMinInteractiveDimension.toDouble();
            final minBottom = needsDeleteChrome && chromeFloor > ratioMin
                ? chromeFloor
                : ratioMin;
            final maxTop = (usable - minBottom).clamp(0.0, usable);
            final minTop = ratioMin > maxTop ? maxTop : ratioMin;
            final rawTop = usable * ratio;
            final topH = rawTop < minTop
                ? minTop
                : (rawTop > maxTop ? maxTop : rawTop);
            final bottomH = usable - topH;

            return Column(
              children: [
                SizedBox(
                  height: topH,
                  child: topPane,
                ),
                GestureDetector(
                  key: const Key('readerSplitDivider'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    final h = constraints.maxHeight;
                    if (h <= 0) return;
                    // No setState — heights via notifier only (D13 / RS-17).
                    _bookDividerRatio.value =
                        (_bookDividerRatio.value + details.delta.dy / h)
                            .clamp(_minRatio, _maxRatio);
                  },
                  child: Material(
                    color: dividerColor,
                    child: SizedBox(
                      height: _dividerHandleHeight,
                      width: double.infinity,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: outlineColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: bottomH,
                  child: bottomPane,
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Bottom pane for EPUB split: load CTA, book chapters, or stuck link (RS-13/07/09).
  Widget _buildBookBottomPane() {
    final showDeleteChrome =
        _hasTranslationChapters || _hasLinkedTranslation;
    final stuckLink = !_hasTranslationChapters && _hasLinkedTranslation;

    final Widget content;
    if (!_hasTranslationChapters) {
      content = Center(
        key: const Key('readerTranslationEmpty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stuckLink
                    ? 'Saved translation could not be shown'
                    : 'No translation loaded',
              ),
              if (!stuckLink) ...[
                const SizedBox(height: 12),
                ElevatedButton(
                  key: const Key('readerTranslationLoad'),
                  onPressed: _loadingTranslation ? null : _loadTranslation,
                  child: _loadingTranslation
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Load translation'),
                ),
              ],
            ],
          ),
        ),
      );
    } else {
      content = _buildBookPaneContent(
        chapters: _translationChapters!,
        paneKey: const Key('readerTranslationBookPane'),
        emptyKey: const Key('readerTranslationBookEmpty'),
        titleKeyPrefix: 'readerTranslationBookChapterTitle',
        listKey: const Key('readerTranslationBookParagraphList'),
        listKeyPrefix: 'readerTranslationBookParagraphList',
        prevKey: const Key('readerTranslationBookChapterPrev'),
        pagerKey: const Key('readerTranslationBookChapterPager'),
        nextKey: const Key('readerTranslationBookChapterNext'),
        cueKeyPrefix: 'readerTranslationCue',
        fromOriginal: false,
        interactive: false,
      );
    }

    if (!showDeleteChrome) return content;

    return Column(
      children: [
        _buildBottomDeleteChrome(emptyVariant: stuckLink),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildAddVocabCta() {
    final surface = _selectedDisplaySurface();
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('readerAddVocabCta'),
              onPressed: surface == null || surface.isEmpty
                  ? null
                  : _openAddVocabSheet,
              child: const Text('Add to vocabulary'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSinglePane() {
    return _buildOriginalPane(listKey: const Key('readerCueList'));
  }

  /// Original pane: video pages (VF-01) or cue list. Frames never in bottom.
  Widget _buildOriginalPane({required Key listKey}) {
    if (_hasVideo) {
      return VideoFramePages(
        key: _videoPagesKey,
        videoRef: _videoRef!,
        totalSeconds: _videoTotalSeconds,
        originalCues: widget.originalCues,
        extractor: _videoExtractor,
        cache: _videoCache,
        initialSecond: _videoInitialSecond,
        onPageChanged: _onVideoPageChanged,
        buildCueText: _buildVideoCueText,
      );
    }
    return _buildCueList(
      listKey: listKey,
      cues: widget.originalCues,
      keyPrefix: 'readerCue',
      itemScrollController: _originalScrollController,
      itemPositionsListener: _originalPositions,
      fromOriginal: true,
    );
  }

  /// Cue text under a frame with tap/highlight when tokenize is ready (VF-12).
  ///
  /// End-second rule may attach several cues to one second — stack CueRows
  /// with `showTimestamp: true` (file start→end, VF-04). Empty slot → no
  /// timestamp (VF-03).
  Widget _buildVideoCueText(
    BuildContext context,
    int second,
    String cueText,
  ) {
    // Rebuild from end-second indices so multi-cue seconds get stacked CueRows.
    // [cueText] matches [cueTextAtSecond] from VideoFramePages (VF-04).
    final indices = cueIndicesAtEndSecond(widget.originalCues, second);
    assert(cueText.isEmpty == indices.isEmpty);
    if (indices.isEmpty) {
      return Text(
        cueText,
        key: Key('videoFrameSlotText_$second'),
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final rows = <Widget>[];
    for (final cueIndex in indices) {
      final tokensReady = _tokenizeReady &&
          _cueTokensByIndex != null &&
          cueIndex < _cueTokensByIndex!.length;
      final tokens =
          tokensReady ? _cueTokensByIndex![cueIndex].tokens : null;
      final isActive = _hasSelection && _activeCueIndex == cueIndex;
      rows.add(
        CueRow(
          cue: widget.originalCues[cueIndex],
          keyPrefix: 'readerCue',
          cueListIndex: cueIndex,
          tokens: tokens,
          selectionStart: isActive ? _selectionStart : null,
          selectionEnd: isActive ? _selectionEnd : null,
          flashTokenIndex: isActive ? _flashTokenIndex : null,
          onTokenTap: tokensReady && tokens != null && tokens.isNotEmpty
              ? (tokenIndex) => _onOriginalTokenTap(cueIndex, tokenIndex)
              : null,
          showTimestamp: true,
          padding: EdgeInsets.zero,
          keySuffix: 's$second',
        ),
      );
    }

    return KeyedSubtree(
      key: Key('videoFrameSlotText_$second'),
      child: rows.length == 1
          ? rows.first
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
    );
  }

  Widget _buildSplitBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final usable = constraints.maxHeight - _dividerHandleHeight;
        // Delete chrome (D8) needs ≥48dp; keep bottom pane tall enough when shown.
        final needsDeleteChrome =
            _hasTranslationCues || _hasLinkedTranslation;
        final ratioMin = usable * _minRatio;
        final chromeFloor = usable < kMinInteractiveDimension
            ? usable
            : kMinInteractiveDimension.toDouble();
        final minBottom = needsDeleteChrome && chromeFloor > ratioMin
            ? chromeFloor
            : ratioMin;
        final maxTop = (usable - minBottom).clamp(0.0, usable);
        final minTop = ratioMin > maxTop ? maxTop : ratioMin;
        final rawTop = usable * _dividerRatio;
        final topH = rawTop < minTop
            ? minTop
            : (rawTop > maxTop ? maxTop : rawTop);
        final bottomH = usable - topH;

        return Column(
          children: [
            SizedBox(
              height: topH,
              child: _buildOriginalPane(
                listKey: const Key('readerOriginalCueList'),
              ),
            ),
            GestureDetector(
              key: const Key('readerSplitDivider'),
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                final h = constraints.maxHeight;
                if (h <= 0) return;
                setState(() {
                  _dividerRatio = (_dividerRatio + details.delta.dy / h)
                      .clamp(_minRatio, _maxRatio);
                });
              },
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: SizedBox(
                  height: _dividerHandleHeight,
                  width: double.infinity,
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: bottomH,
              child: _buildBottomPane(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomPane() {
    final cues = _translationCues;
    final showDeleteChrome =
        _hasTranslationCues || _hasLinkedTranslation;
    final stuckLink = !_hasTranslationCues && _hasLinkedTranslation;

    final Widget content;
    if (cues == null || cues.isEmpty) {
      content = Center(
        key: const Key('readerTranslationEmpty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stuckLink
                    ? 'Saved translation could not be shown'
                    : 'No translation loaded',
              ),
              if (!stuckLink) ...[
                const SizedBox(height: 12),
                ElevatedButton(
                  key: const Key('readerTranslationLoad'),
                  onPressed: _loadingTranslation ? null : _loadTranslation,
                  child: _loadingTranslation
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Load translation'),
                ),
              ],
            ],
          ),
        ),
      );
    } else {
      content = _buildCueList(
        listKey: const Key('readerTranslationCueList'),
        cues: cues,
        keyPrefix: 'readerTranslationCue',
        itemScrollController: _translationScrollController,
        itemPositionsListener: _translationPositions,
        fromOriginal: false,
      );
    }

    if (!showDeleteChrome) return content;

    // RS-07 / D8: Delete lives in bottom-pane top chrome, not AppBar.
    return Column(
      children: [
        _buildBottomDeleteChrome(emptyVariant: stuckLink),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildBottomDeleteChrome({required bool emptyVariant}) {
    // Match Material min tap target (48) so IconButton does not overflow.
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: kMinInteractiveDimension,
        width: double.infinity,
        child: Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            key: Key(
              emptyVariant
                  ? 'readerTranslationDeleteEmpty'
                  : 'readerTranslationDelete',
            ),
            tooltip: 'Delete translation',
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteTranslation,
          ),
        ),
      ),
    );
  }

  Widget _buildCueList({
    required Key listKey,
    required List<rust_parse.CueDto> cues,
    required String keyPrefix,
    required ItemScrollController itemScrollController,
    required ItemPositionsListener itemPositionsListener,
    required bool fromOriginal,
  }) {
    final maxIndex = cues.isEmpty ? 0 : cues.length - 1;
    final initialIndex = fromOriginal
        ? _originalInitialScrollIndex.clamp(0, maxIndex)
        : 0;
    final initialAlignment =
        fromOriginal ? _originalInitialAlignment.clamp(0.0, 1.0) : 0.0;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) =>
          _onScrollNotification(n, fromOriginal: fromOriginal),
      child: ScrollablePositionedList.builder(
        key: listKey,
        itemScrollController: itemScrollController,
        itemPositionsListener: itemPositionsListener,
        initialScrollIndex: initialIndex,
        initialAlignment: initialAlignment,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: cues.length,
        itemBuilder: (context, index) {
          // RT-08: token selection only on original pane.
          final tokensReady = fromOriginal &&
              _tokenizeReady &&
              _cueTokensByIndex != null &&
              index < _cueTokensByIndex!.length;
          final tokens =
              tokensReady ? _cueTokensByIndex![index].tokens : null;
          final isActive =
              fromOriginal && _hasSelection && _activeCueIndex == index;
          return CueRow(
            cue: cues[index],
            keyPrefix: keyPrefix,
            cueListIndex: fromOriginal ? index : null,
            tokens: tokens,
            selectionStart: isActive ? _selectionStart : null,
            selectionEnd: isActive ? _selectionEnd : null,
            flashTokenIndex: isActive ? _flashTokenIndex : null,
            onTokenTap: tokensReady && tokens != null && tokens.isNotEmpty
                ? (tokenIndex) => _onOriginalTokenTap(index, tokenIndex)
                : null,
          );
        },
      ),
    );
  }
}

/// Bottom sheet to add Reader selection (single or phrase) (D5 / RT-05…RT-07).
class _AddVocabSheet extends StatefulWidget {
  const _AddVocabSheet({
    required this.surface,
    required this.lemmaKey,
    required this.surfaceKey,
    required this.initialContext,
    required this.dictionaryRepository,
    required this.offlineTranslate,
  });

  final String surface;
  final String lemmaKey;
  final String surfaceKey;
  final String initialContext;
  final DictionaryRepository dictionaryRepository;
  final OfflineTranslateFn offlineTranslate;

  @override
  State<_AddVocabSheet> createState() => _AddVocabSheetState();
}

class _AddVocabSheetState extends State<_AddVocabSheet> {
  late final TextEditingController _translationController;
  late final TextEditingController _contextController;
  String? _validationError;
  var _saving = false;
  var _translating = false;
  /// After Translate starts once, stays disabled until sheet closes (RT-19).
  var _translateStarted = false;

  @override
  void initState() {
    super.initState();
    _translationController = TextEditingController();
    _contextController = TextEditingController(text: widget.initialContext);
  }

  @override
  void dispose() {
    _translationController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  bool get _canTranslate => !_translating && !_translateStarted;

  Future<void> _onTranslate() async {
    if (!_canTranslate) return;
    setState(() {
      _translating = true;
      _translateStarted = true;
    });
    try {
      final outcome = await widget.offlineTranslate(text: widget.surface);
      if (!mounted) return;
      switch (outcome) {
        case OfflineTranslateOk(:final primaryGloss):
          _translationController.text = primaryGloss;
        case OfflineTranslateErr(:final kind):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: const Key('readerAddVocabTranslateErrorSnack'),
              content: Text(offlineTranslateUserMessage(kind)),
            ),
          );
      }
    } catch (e, st) {
      assert(() {
        debugPrint('reader add translate unexpected: $e\n$st');
        return true;
      }());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('readerAddVocabTranslateErrorSnack'),
          content: Text(
            offlineTranslateUserMessage(OfflineTranslateErrorKind.internal),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _onSave() async {
    final trimmedTranslation = _translationController.text.trim();
    // RT-07 / D5: empty translation → validation error, no persist.
    if (trimmedTranslation.isEmpty) {
      setState(() {
        _validationError = 'Translation must not be empty';
      });
      return;
    }

    setState(() {
      _validationError = null;
      _saving = true;
    });

    try {
      await widget.dictionaryRepository.add(
        lemma: widget.lemmaKey,
        surfaceKey: widget.surfaceKey,
        translation: trimmedTranslation,
        context: _contextController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DictionaryValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationError = e.message;
      });
    } catch (e, st) {
      assert(() {
        debugPrint('dict persist from Reader: $e\n$st');
        return true;
      }());
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);

    return Padding(
      key: const Key('readerAddVocabSheet'),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add to vocabulary',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InputDecorator(
                    key: const Key('readerAddVocabSurface'),
                    decoration: const InputDecoration(
                      labelText: 'Word',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(widget.surface),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    key: const Key('readerAddVocabTranslate'),
                    onPressed: _canTranslate ? _onTranslate : null,
                    child: _translating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Translate'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Column(
              key: Key('readerAddVocabTranslateAttribution'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kOfflineTranslateAttribution),
                Text(kOfflineTranslateDisclaimer),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('readerAddVocabTranslation'),
              controller: _translationController,
              decoration: const InputDecoration(
                labelText: 'Translation',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              enabled: !_saving,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('readerAddVocabContext'),
              controller: _contextController,
              decoration: const InputDecoration(
                labelText: 'Context',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
              enabled: !_saving,
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 8),
              Text(
                _validationError!,
                key: const Key('readerAddVocabValidationError'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('readerAddVocabSave'),
              onPressed: _saving ? null : _onSave,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edit sheet for in-vocab token tap (D5 / RH-05…RH-07).
class _EditVocabSheet extends StatefulWidget {
  const _EditVocabSheet({
    required this.entry,
    required this.surface,
    required this.dictionaryRepository,
    required this.offlineTranslate,
  });

  final DictionaryEntry entry;
  final String surface;
  final DictionaryRepository dictionaryRepository;
  final OfflineTranslateFn offlineTranslate;

  @override
  State<_EditVocabSheet> createState() => _EditVocabSheetState();
}

class _EditVocabSheetState extends State<_EditVocabSheet> {
  late final TextEditingController _translationController;
  late final TextEditingController _contextController;
  String? _validationError;
  var _busy = false;
  var _translating = false;
  /// After Translate starts once, stays disabled until sheet closes (RT-24).
  var _translateStarted = false;

  @override
  void initState() {
    super.initState();
    _translationController =
        TextEditingController(text: widget.entry.translation);
    _contextController =
        TextEditingController(text: widget.entry.context ?? '');
  }

  @override
  void dispose() {
    _translationController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  bool get _canTranslate => !_translating && !_translateStarted;

  Future<void> _onTranslate() async {
    if (!_canTranslate) return;
    setState(() {
      _translating = true;
      _translateStarted = true;
    });
    try {
      final outcome = await widget.offlineTranslate(text: widget.surface);
      if (!mounted) return;
      switch (outcome) {
        case OfflineTranslateOk(:final primaryGloss):
          _translationController.text = primaryGloss;
        case OfflineTranslateErr(:final kind):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: const Key('readerEditVocabTranslateErrorSnack'),
              content: Text(offlineTranslateUserMessage(kind)),
            ),
          );
      }
    } catch (e, st) {
      assert(() {
        debugPrint('reader edit translate unexpected: $e\n$st');
        return true;
      }());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('readerEditVocabTranslateErrorSnack'),
          content: Text(
            offlineTranslateUserMessage(OfflineTranslateErrorKind.internal),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _onSave() async {
    final trimmedTranslation = _translationController.text.trim();
    if (trimmedTranslation.isEmpty) {
      setState(() {
        _validationError = 'Translation must not be empty';
      });
      return;
    }

    setState(() {
      _validationError = null;
      _busy = true;
    });

    try {
      await widget.dictionaryRepository.add(
        lemma: widget.entry.lemma,
        surfaceKey: widget.entry.surfaceKey ??
            DictionaryRepository.normalizeSurface(widget.surface),
        translation: trimmedTranslation,
        context: _contextController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DictionaryValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _validationError = e.message;
      });
    } catch (e, st) {
      assert(() {
        debugPrint('dict edit from Reader: $e\n$st');
        return true;
      }());
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save. Try again.")),
      );
    }
  }

  Future<void> _onDelete() async {
    setState(() {
      _validationError = null;
      _busy = true;
    });
    try {
      await widget.dictionaryRepository.remove(widget.entry.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DictionaryValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _validationError = e.message;
      });
    } catch (e, st) {
      assert(() {
        debugPrint('dict delete from Reader: $e\n$st');
        return true;
      }());
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);

    return Padding(
      key: const Key('readerEditVocabSheet'),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit vocabulary',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            InputDecorator(
              key: const Key('readerEditVocabLemma'),
              decoration: const InputDecoration(
                labelText: 'Lemma',
                border: OutlineInputBorder(),
              ),
              child: Text(widget.entry.lemma),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InputDecorator(
                    key: const Key('readerEditVocabSurface'),
                    decoration: const InputDecoration(
                      labelText: 'Surface',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(widget.surface),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    key: const Key('readerEditVocabTranslate'),
                    onPressed: _canTranslate ? _onTranslate : null,
                    child: _translating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Translate'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Column(
              key: Key('readerEditVocabTranslateAttribution'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kOfflineTranslateAttribution),
                Text(kOfflineTranslateDisclaimer),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('readerEditVocabTranslation'),
              controller: _translationController,
              decoration: const InputDecoration(
                labelText: 'Translation',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              enabled: !_busy,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('readerEditVocabContext'),
              controller: _contextController,
              decoration: const InputDecoration(
                labelText: 'Context',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
              enabled: !_busy,
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 8),
              Text(
                _validationError!,
                key: const Key('readerEditVocabValidationError'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('readerEditVocabSave'),
              onPressed: _busy ? null : _onSave,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('readerEditVocabDelete'),
              onPressed: _busy ? null : _onDelete,
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
