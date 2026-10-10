import 'package:my_translator_app/src/rust/api/parse.dart';

/// Injectable FRB parse seam for Library / Reader widget tests (frb-boundary).
typedef ParseSubtitlesFn =
    Future<ParsedSubtitles> Function({
      required List<int> bytes,
      String? formatHint,
    });
