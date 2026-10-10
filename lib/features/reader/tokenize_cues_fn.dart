import 'package:my_translator_app/src/rust/api/tokenize.dart';

/// Injectable FRB tokenize seam for Reader widget tests (frb-boundary).
typedef TokenizeCuesFn = Future<List<CueTokensDto>> Function(List<String> texts);
