//! Typed offline-translate failures (design D3 / TO-03…TO-06, TO-08).
//! FRB DTO lives in `api::translate::TranslateErrorKind` — keep this name distinct.

/// Domain failure kinds (map to FRB at `api/`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(target_arch = "wasm32", allow(dead_code))]
pub(crate) enum TranslateError {
    /// Empty or whitespace-only query.
    EmptyQuery,
    /// Not EN→RU after casefold normalize.
    UnsupportedLanguagePair,
    /// No init / missing or corrupt assets / ORT session fail / wasm stub.
    EngineUnavailable,
    /// Session is up but inference failed.
    InferenceFailed,
    /// Unexpected; safe message outward only.
    Internal,
}

impl std::fmt::Display for TranslateError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EmptyQuery => write!(f, "empty_query"),
            Self::UnsupportedLanguagePair => write!(f, "unsupported_language_pair"),
            Self::EngineUnavailable => write!(f, "engine_unavailable"),
            Self::InferenceFailed => write!(f, "inference_failed"),
            Self::Internal => write!(f, "internal"),
        }
    }
}

impl std::error::Error for TranslateError {}
