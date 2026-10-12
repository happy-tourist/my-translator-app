import 'package:flutter/material.dart';

/// Product accent colors for Reader (lemma highlight, etc.).
@immutable
class ReaderColors extends ThemeExtension<ReaderColors> {
  const ReaderColors({
    required this.lemmaHighlight,
    required this.lemmaHighlightOn,
  });

  /// Fill behind tokens with `is_in_vocab` (green tint).
  final Color lemmaHighlight;

  /// Ink on [lemmaHighlight] when needed for contrast.
  final Color lemmaHighlightOn;

  static const light = ReaderColors(
    lemmaHighlight: Color(0xFFC8E6C9),
    lemmaHighlightOn: Color(0xFF1B5E20),
  );

  static const dark = ReaderColors(
    lemmaHighlight: Color(0xFF1B3D24),
    lemmaHighlightOn: Color(0xFFA5D6A7),
  );

  @override
  ReaderColors copyWith({
    Color? lemmaHighlight,
    Color? lemmaHighlightOn,
  }) {
    return ReaderColors(
      lemmaHighlight: lemmaHighlight ?? this.lemmaHighlight,
      lemmaHighlightOn: lemmaHighlightOn ?? this.lemmaHighlightOn,
    );
  }

  @override
  ReaderColors lerp(ThemeExtension<ReaderColors>? other, double t) {
    if (other is! ReaderColors) return this;
    return ReaderColors(
      lemmaHighlight: Color.lerp(lemmaHighlight, other.lemmaHighlight, t)!,
      lemmaHighlightOn:
          Color.lerp(lemmaHighlightOn, other.lemmaHighlightOn, t)!,
    );
  }
}

/// App ThemeData pair (Material 3 + [ReaderColors]).
abstract final class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        extensions: const [ReaderColors.light],
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
        extensions: const [ReaderColors.dark],
      );
}
