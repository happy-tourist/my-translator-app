// Shared offline-translate facade types (design D4.1 / D4.5 / D4.6).
// Native: FRB ORT. Web: Transformers.js worker via offline_translate_web.

/// Production / test injectable translate callback.
typedef OfflineTranslateFn = Future<OfflineTranslateOutcome> Function({
  required String text,
  String sourceLang,
  String targetLang,
});

/// Result of one offline gloss request.
sealed class OfflineTranslateOutcome {
  const OfflineTranslateOutcome();
}

/// Non-empty Russian gloss.
final class OfflineTranslateOk extends OfflineTranslateOutcome {
  const OfflineTranslateOk({required this.primaryGloss});

  final String primaryGloss;
}

/// Typed failure (same kinds as FRB [TranslateErrorKind]).
final class OfflineTranslateErr extends OfflineTranslateOutcome {
  const OfflineTranslateErr({required this.kind});

  final OfflineTranslateErrorKind kind;
}

/// Logical error kinds shared by native FRB and Web Transformers.js.
enum OfflineTranslateErrorKind {
  emptyQuery,
  unsupportedLanguagePair,
  engineUnavailable,
  inferenceFailed,
  internal,
}

/// Locked EN user-visible copy (design D4.5).
String offlineTranslateUserMessage(OfflineTranslateErrorKind kind) {
  switch (kind) {
    case OfflineTranslateErrorKind.emptyQuery:
      return 'Enter a word or phrase to translate';
    case OfflineTranslateErrorKind.unsupportedLanguagePair:
      return 'Only English → Russian is supported';
    case OfflineTranslateErrorKind.engineUnavailable:
      return 'Translation unavailable. Try again later';
    case OfflineTranslateErrorKind.inferenceFailed:
    case OfflineTranslateErrorKind.internal:
      return "Couldn't translate. Try again";
  }
}

/// Locked attribution line (design D4.6).
const String kOfflineTranslateAttribution =
    'OPUS-MT (Helsinki-NLP), CC-BY 4.0';

/// Locked accuracy disclaimer (design D4.6).
const String kOfflineTranslateDisclaimer = 'Translation may be inaccurate';

/// Parse a worker / JS kind string into [OfflineTranslateErrorKind].
OfflineTranslateErrorKind offlineTranslateErrorKindFromJs(String? raw) {
  switch (raw) {
    case 'emptyQuery':
      return OfflineTranslateErrorKind.emptyQuery;
    case 'unsupportedLanguagePair':
      return OfflineTranslateErrorKind.unsupportedLanguagePair;
    case 'engineUnavailable':
      return OfflineTranslateErrorKind.engineUnavailable;
    case 'inferenceFailed':
      return OfflineTranslateErrorKind.inferenceFailed;
    case 'internal':
    default:
      return OfflineTranslateErrorKind.internal;
  }
}
