import 'package:flutter/material.dart';

import 'package:my_translator_app/app/theme.dart';
import 'package:my_translator_app/features/reader/cue_char_slice.dart';
import 'package:my_translator_app/features/reader/cue_time_format.dart';
import 'package:my_translator_app/src/rust/api/parse.dart';
import 'package:my_translator_app/src/rust/api/tokenize.dart';

/// Shared cue row (timestamp + text_lines) for original and translation panes.
///
/// When [tokens] is non-null and non-empty on the original pane, word spans
/// become tappable. Subtitle mode uses per-token WidgetSpan Keys
/// (`readerCueToken_*`). Book mode ([lightweightHitTest]) uses TextSpan + one
/// paragraph gesture (D11 / RC-07) — no per-word WidgetSpan.
class CueRow extends StatelessWidget {
  const CueRow({
    super.key,
    required this.cue,
    this.keyPrefix = 'readerCue',
    this.cueListIndex,
    this.tokens,
    this.selectionStart,
    this.selectionEnd,
    this.flashTokenIndex,
    this.onTokenTap,
    this.showTimestamp = true,
    this.lightweightHitTest = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.keySuffix,
  });

  final CueDto cue;

  /// Prefix for Keys: `readerCue` (original) / `readerTranslationCue`.
  final String keyPrefix;

  /// Index in the original cues batch (for token Keys). Defaults to [cue.index].
  final int? cueListIndex;

  /// Word tokens for this cue (original pane only). Null/empty → plain text.
  final List<TokenDto>? tokens;

  /// Inclusive selection range within [tokens] when this cue is active.
  final int? selectionStart;
  final int? selectionEnd;

  /// Brief gap-reset flash target (D5).
  final int? flashTokenIndex;

  final ValueChanged<int>? onTokenTap;

  /// When false, omit the cue time range. Under video frames with cue text,
  /// pass `true` so file `startMs → endMs` shows (VF-04 / D5); empty slots
  /// omit CueRow entirely (VF-03).
  final bool showTimestamp;

  /// Book-mode path (D11): Text.rich TextSpans + one gesture layer; maps tap
  /// → char → tokenIndex. Subtitle CueRow keeps WidgetSpan-per-token.
  final bool lightweightHitTest;

  /// Outer padding; use [EdgeInsets.zero] when embedded under a video frame.
  final EdgeInsetsGeometry padding;

  /// Disambiguates Keys when the same cue is embedded under a frame second
  /// (`keySuffix: 's$second'` → `…_s12`) so list-pane and under-frame Keys
  /// never collide (VF-12).
  final String? keySuffix;

  String _keyed(String base) =>
      keySuffix == null ? base : '${base}_$keySuffix';

  @override
  Widget build(BuildContext context) {
    final timeStyle = Theme.of(context).textTheme.labelMedium;
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;
    final time =
        '${formatCueTimestamp(cue.startMs)} → ${formatCueTimestamp(cue.endMs)}';
    final text = cue.textLines.join('\n');
    final tokenList = tokens;
    final selectable =
        tokenList != null && tokenList.isNotEmpty && onTokenTap != null;

    return Padding(
      key: Key(_keyed('${keyPrefix}_${cue.index}')),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTimestamp) ...[
            Text(
              time,
              key: Key(_keyed('${keyPrefix}Time_${cue.index}')),
              style: timeStyle,
            ),
            const SizedBox(height: 4),
          ],
          if (selectable)
            lightweightHitTest
                ? _LightweightSelectableCueText(
                    cueText: text,
                    tokens: tokenList,
                    bodyStyle: bodyStyle,
                    textKey: Key(_keyed('${keyPrefix}Text_${cue.index}')),
                    selectionStart: selectionStart,
                    selectionEnd: selectionEnd,
                    flashTokenIndex: flashTokenIndex,
                    onTokenTap: onTokenTap!,
                  )
                : _SelectableCueText(
                    cueText: text,
                    cueListIndex: cueListIndex ?? cue.index,
                    tokens: tokenList,
                    bodyStyle: bodyStyle,
                    textKey: Key(_keyed('${keyPrefix}Text_${cue.index}')),
                    selectionStart: selectionStart,
                    selectionEnd: selectionEnd,
                    flashTokenIndex: flashTokenIndex,
                    onTokenTap: onTokenTap!,
                    keySuffix: keySuffix,
                  )
          else
            Text(
              text,
              key: Key(_keyed('${keyPrefix}Text_${cue.index}')),
              style: bodyStyle,
            ),
        ],
      ),
    );
  }
}

/// Book-mode selectable paragraph: TextSpans + one gesture (D11 / RC-07).
class _LightweightSelectableCueText extends StatelessWidget {
  const _LightweightSelectableCueText({
    required this.cueText,
    required this.tokens,
    required this.bodyStyle,
    required this.textKey,
    required this.selectionStart,
    required this.selectionEnd,
    required this.flashTokenIndex,
    required this.onTokenTap,
  });

  final String cueText;
  final List<TokenDto> tokens;
  final TextStyle? bodyStyle;
  final Key textKey;
  final int? selectionStart;
  final int? selectionEnd;
  final int? flashTokenIndex;
  final ValueChanged<int> onTokenTap;

  TextSpan _buildSpanTree(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final readerColors = Theme.of(context).extension<ReaderColors>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? ReaderColors.dark
            : ReaderColors.light);
    final selectedStyle = (bodyStyle ?? const TextStyle()).copyWith(
      backgroundColor: scheme.primaryContainer,
      color: scheme.onPrimaryContainer,
    );
    final flashStyle = (bodyStyle ?? const TextStyle()).copyWith(
      backgroundColor: scheme.tertiaryContainer,
      color: scheme.onTertiaryContainer,
      fontWeight: FontWeight.w700,
    );
    final highlightStyle = (bodyStyle ?? const TextStyle()).copyWith(
      backgroundColor: readerColors.lemmaHighlight,
      color: readerColors.lemmaHighlightOn,
    );

    final spans = <InlineSpan>[];
    var cursor = 0;
    final textCharLen = cueCharLength(cueText);
    for (final token in tokens) {
      final start = token.charStart;
      final end = token.charEnd;
      if (start < cursor || end > textCharLen || start >= end) {
        continue;
      }
      if (start > cursor) {
        spans.add(
          TextSpan(
            text: cueCharSlice(cueText, cursor, start),
            style: bodyStyle,
          ),
        );
      }
      final idx = token.tokenIndex;
      final inSelection = selectionStart != null &&
          selectionEnd != null &&
          idx >= selectionStart! &&
          idx <= selectionEnd!;
      final flashing = flashTokenIndex == idx;
      final style = flashing
          ? flashStyle
          : (inSelection
              ? selectedStyle
              : (token.isInVocab ? highlightStyle : bodyStyle));
      spans.add(
        TextSpan(
          text: cueCharSlice(cueText, start, end),
          style: style,
        ),
      );
      cursor = end;
    }
    if (cursor < textCharLen) {
      spans.add(
        TextSpan(
          text: cueCharSlice(cueText, cursor, textCharLen),
          style: bodyStyle,
        ),
      );
    }
    return TextSpan(children: spans, style: bodyStyle);
  }

  int? _tokenIndexAtChar(int charIndex) {
    for (final token in tokens) {
      if (charIndex >= token.charStart && charIndex < token.charEnd) {
        return token.tokenIndex;
      }
    }
    return null;
  }

  void _onTapUp(TapUpDetails details, double maxWidth, BuildContext context) {
    final spanTree = _buildSpanTree(context);
    // Match ambient Text.rich metrics so offset→char stays accurate under
    // text scale / RTL (D11 hit-test miss risk).
    final painter = TextPainter(
      text: spanTree,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: maxWidth);
    final pos = painter.getPositionForOffset(details.localPosition);
    var charIndex = cueUtf16OffsetToCharIndex(cueText, pos.offset);
    // Upstream affinity / trailing edge: prefer the character under the finger.
    if (pos.affinity == TextAffinity.upstream && charIndex > 0) {
      charIndex -= 1;
    }
    var tokenIndex = _tokenIndexAtChar(charIndex);
    // Whitespace between tokens: try previous scalar.
    tokenIndex ??=
        charIndex > 0 ? _tokenIndexAtChar(charIndex - 1) : null;
    if (tokenIndex != null) {
      onTokenTap(tokenIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spanTree = _buildSpanTree(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) =>
              _onTapUp(details, constraints.maxWidth, context),
          child: Text.rich(
            spanTree,
            key: textKey,
          ),
        );
      },
    );
  }
}

/// Subtitle-mode selectable cue: WidgetSpan + GestureDetector per token.
class _SelectableCueText extends StatelessWidget {
  const _SelectableCueText({
    required this.cueText,
    required this.cueListIndex,
    required this.tokens,
    required this.bodyStyle,
    required this.textKey,
    required this.selectionStart,
    required this.selectionEnd,
    required this.flashTokenIndex,
    required this.onTokenTap,
    this.keySuffix,
  });

  final String cueText;
  final int cueListIndex;
  final List<TokenDto> tokens;
  final TextStyle? bodyStyle;
  final Key textKey;
  final int? selectionStart;
  final int? selectionEnd;
  final int? flashTokenIndex;
  final ValueChanged<int> onTokenTap;
  final String? keySuffix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Design D5 / highlight.md: paint from ReaderColors (never silent no-op).
    final readerColors = Theme.of(context).extension<ReaderColors>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? ReaderColors.dark
            : ReaderColors.light);
    final selectedStyle = (bodyStyle ?? const TextStyle()).copyWith(
      backgroundColor: scheme.primaryContainer,
      color: scheme.onPrimaryContainer,
    );
    final flashStyle = (bodyStyle ?? const TextStyle()).copyWith(
      backgroundColor: scheme.tertiaryContainer,
      color: scheme.onTertiaryContainer,
      fontWeight: FontWeight.w700,
    );
    final highlightStyle = (bodyStyle ?? const TextStyle()).copyWith(
      backgroundColor: readerColors.lemmaHighlight,
      color: readerColors.lemmaHighlightOn,
    );

    final spans = <InlineSpan>[];
    var cursor = 0;
    final textCharLen = cueCharLength(cueText);
    for (final token in tokens) {
      final start = token.charStart;
      final end = token.charEnd;
      // DTO spans are Unicode scalar indices (design D2), not UTF-16.
      if (start < cursor || end > textCharLen || start >= end) {
        continue;
      }
      if (start > cursor) {
        spans.add(
          TextSpan(
            text: cueCharSlice(cueText, cursor, start),
            style: bodyStyle,
          ),
        );
      }
      final idx = token.tokenIndex;
      final inSelection = selectionStart != null &&
          selectionEnd != null &&
          idx >= selectionStart! &&
          idx <= selectionEnd!;
      final flashing = flashTokenIndex == idx;
      // Flash > selection > vocab highlight > body.
      final style = flashing
          ? flashStyle
          : (inSelection
              ? selectedStyle
              : (token.isInVocab ? highlightStyle : bodyStyle));
      // WidgetSpan (not TextSpan+recognizer): Keys for D9 finders need a Widget.
      final tokenKey = keySuffix == null
          ? 'readerCueToken_${cueListIndex}_$idx'
          : 'readerCueToken_${cueListIndex}_${idx}_$keySuffix';
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            key: Key(tokenKey),
            behavior: HitTestBehavior.translucent,
            onTap: () => onTokenTap(idx),
            child: Text(
              cueCharSlice(cueText, start, end),
              style: style,
            ),
          ),
        ),
      );
      cursor = end;
    }
    if (cursor < textCharLen) {
      spans.add(
        TextSpan(
          text: cueCharSlice(cueText, cursor, textCharLen),
          style: bodyStyle,
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans, style: bodyStyle),
      key: textKey,
    );
  }
}
