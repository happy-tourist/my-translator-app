import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/library/parse_error_messages.dart';
import 'package:my_translator_app/src/rust/api/epub.dart';

void main() {
  test('messageForEpubParseError distinguishes empty vs broken (PE-05 / D10)', () {
    final brokenUnsupported = messageForEpubParseError(
      EpubParseErrorKind.unsupportedFormat,
    );
    final brokenMalformed = messageForEpubParseError(
      EpubParseErrorKind.malformed,
    );
    final empty = messageForEpubParseError(EpubParseErrorKind.empty);

    expect(brokenUnsupported, brokenMalformed);
    expect(brokenUnsupported.toLowerCase(), contains('epub'));
    expect(empty.toLowerCase(), contains('text'));
    expect(empty, isNot(brokenUnsupported));
  });
}
