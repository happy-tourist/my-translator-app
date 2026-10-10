import 'package:my_translator_app/src/rust/api/parse.dart';

/// Shared Library / Reader copy for FRB [ParseErrorKind] (frb-parse.md).
String messageForParseError(ParseErrorKind kind) {
  switch (kind) {
    case ParseErrorKind.unsupportedFormat:
      return 'Unsupported or unrecognized subtitle format';
    case ParseErrorKind.encoding:
      return 'File encoding is not valid UTF-8';
    case ParseErrorKind.empty:
      return 'No subtitle cues found in this file';
    case ParseErrorKind.malformed:
      return 'Could not parse this subtitle file';
  }
}
