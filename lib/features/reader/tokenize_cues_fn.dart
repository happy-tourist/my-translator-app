import 'package:my_translator_app/src/rust/api/tokenize.dart';

export 'package:my_translator_app/data/dictionary/lemma_keys_for_surfaces_fn.dart'
    show LemmaKeysForSurfacesFn;

/// Injectable FRB tokenize seam for Reader widget tests (frb-boundary).
typedef TokenizeCuesFn = Future<List<CueTokensDto>> Function(List<String> texts);

/// Injectable FRB `markVocabTokens` seam (membership from Drift morph lemmas).
typedef MarkVocabTokensFn = Future<List<CueTokensDto>> Function({
  required List<CueTokensDto> cues,
  required List<String> vocabLemmas,
});
