import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show AnyhowException, PanicException;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import 'package:my_translator_app/data/library/document_format.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/library_exceptions.dart';
import 'package:my_translator_app/data/library/parse_error_messages.dart';
import 'package:my_translator_app/data/library/parse_subtitles_fn.dart';
import 'package:my_translator_app/features/reader/cue_row.dart';
import 'package:my_translator_app/features/reader/nearest_cue_index.dart';
import 'package:my_translator_app/src/rust/api/parse.dart' as rust_parse;

/// Picked translation file for injectable Reader load (tests / file_picker).
class PickedTranslationFile {
  const PickedTranslationFile({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

typedef ReaderTranslationPicker = Future<PickedTranslationFile?> Function();

/// Cues-first Reader with optional split mode (RS-01…RS-12).
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.title,
    required this.originalCues,
    required this.originalDocumentId,
    required this.documentRepository,
    this.translationCues,
    this.translationDocumentId,
    this.initialReadingAnchor,
    this.parseSubtitles,
    this.filePicker,
  });

  final String title;
  final List<rust_parse.CueDto> originalCues;
  final int originalDocumentId;
  final DocumentRepository documentRepository;
  final List<rust_parse.CueDto>? translationCues;
  final int? translationDocumentId;

  /// Saved original-pane position from Library open (RS-12 / LD-17).
  final ReadingAnchor? initialReadingAnchor;

  /// Defaults to generated FRB [rust_parse.parseSubtitles].
  final ParseSubtitlesFn? parseSubtitles;

  /// Defaults to [FilePicker.pickFiles].
  final ReaderTranslationPicker? filePicker;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const double _dividerHandleHeight = 16;
  static const double _minRatio = 0.2;
  static const double _maxRatio = 0.8;

  var _splitEnabled = false;
  var _dividerRatio = 0.5;
  var _syncing = false;
  var _userInitiatedScroll = false;
  var _loadingTranslation = false;
  var _didRestoreInitialAnchor = false;

  List<rust_parse.CueDto>? _translationCues;
  int? _translationDocumentId;

  final _originalScrollController = ItemScrollController();
  final _translationScrollController = ItemScrollController();
  final _originalPositions = ItemPositionsListener.create();
  final _translationPositions = ItemPositionsListener.create();

  ParseSubtitlesFn get _parse =>
      widget.parseSubtitles ?? rust_parse.parseSubtitles;

  bool get _hasTranslationCues =>
      _translationCues != null && _translationCues!.isNotEmpty;

  /// Linked translation exists in Drift (may lack cues after failed restore).
  bool get _hasLinkedTranslation => _translationDocumentId != null;

  @override
  void initState() {
    super.initState();
    _translationCues = widget.translationCues;
    _translationDocumentId = widget.translationDocumentId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreInitialReadingAnchor();
    });
  }

  @override
  void dispose() {
    // RS-12 / D10: best-effort save on pop/dispose (do not block).
    // Force: skip `_syncing` guard — pop must still persist even mid-sync.
    unawaited(_persistReadingAnchor(force: true));
    super.dispose();
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

  void _toggleSplit() {
    // RS-10 / RS-11 / D7: remounting the original list resets scroll — capture
    // top-visible anchor before Show *and* Hide, restore after layout.
    final enabling = !_splitEnabled;
    final anchor = _topVisible(_originalPositions);
    final restoreIndex = (anchor?.index ?? 0).clamp(
      0,
      widget.originalCues.isEmpty ? 0 : widget.originalCues.length - 1,
    );
    final restoreAlignment =
        (anchor?.itemLeadingEdge ?? 0.0).clamp(0.0, 1.0);

    setState(() => _splitEnabled = enabling);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
        _syncPanes(fromOriginal: true);
      });
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
    if (!_hasTranslationCues && !_hasLinkedTranslation) return;
    try {
      await widget.documentRepository.detachAndDeleteTranslation(
        widget.originalDocumentId,
      );
      if (!mounted) return;
      setState(() {
        _translationCues = null;
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
    if (_translationCues == null || _translationCues!.isEmpty) return false;
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
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          key: const Key('readerBack'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
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
      body: _splitEnabled ? _buildSplitBody() : _buildSinglePane(),
    );
  }

  Widget _buildSinglePane() {
    return _buildCueList(
      listKey: const Key('readerCueList'),
      cues: widget.originalCues,
      keyPrefix: 'readerCue',
      itemScrollController: _originalScrollController,
      itemPositionsListener: _originalPositions,
      fromOriginal: true,
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
              child: _buildCueList(
                listKey: const Key('readerOriginalCueList'),
                cues: widget.originalCues,
                keyPrefix: 'readerCue',
                itemScrollController: _originalScrollController,
                itemPositionsListener: _originalPositions,
                fromOriginal: true,
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
    return NotificationListener<ScrollNotification>(
      onNotification: (n) =>
          _onScrollNotification(n, fromOriginal: fromOriginal),
      child: ScrollablePositionedList.builder(
        key: listKey,
        itemScrollController: itemScrollController,
        itemPositionsListener: itemPositionsListener,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: cues.length,
        itemBuilder: (context, index) {
          return CueRow(cue: cues[index], keyPrefix: keyPrefix);
        },
      ),
    );
  }
}
