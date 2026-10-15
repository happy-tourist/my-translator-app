import 'package:my_translator_app/src/rust/api/epub.dart';

/// Injectable FRB EPUB parse seam for Library / Reader widget tests.
typedef ParseEpubFn =
    Future<ParsedEpub> Function({required List<int> bytes});
