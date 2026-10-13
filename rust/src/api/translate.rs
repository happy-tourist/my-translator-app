//! Thin FRB export for offline translate (design D3).
//! Domain logic lives in [`crate::translate`]; this module only maps DTOs.

use crate::translate::{self, TranslateError as DomainError};

/// Successful gloss for one word or phrase query.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TranslationResult {
    /// Non-empty Russian gloss when `Ok`.
    pub primary_gloss: String,
}

/// Hard-failure kinds Flutter can switch on (design D3).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TranslateErrorKind {
    EmptyQuery,
    UnsupportedLanguagePair,
    EngineUnavailable,
    InferenceFailed,
    Internal,
}

impl From<DomainError> for TranslateErrorKind {
    fn from(value: DomainError) -> Self {
        match value {
            DomainError::EmptyQuery => Self::EmptyQuery,
            DomainError::UnsupportedLanguagePair => Self::UnsupportedLanguagePair,
            DomainError::EngineUnavailable => Self::EngineUnavailable,
            DomainError::InferenceFailed => Self::InferenceFailed,
            DomainError::Internal => Self::Internal,
        }
    }
}

impl std::fmt::Display for TranslateErrorKind {
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

impl std::error::Error for TranslateErrorKind {}

/// Named model asset bytes from Flutter `AssetBundle` (no OS paths).
#[derive(Debug, Clone)]
pub struct OfflineModelAsset {
    /// Basename, e.g. `tokenizer.json` or `encoder_model_uint8.onnx`.
    pub name: String,
    pub bytes: Vec<u8>,
}

/// Load offline OPUS-MT from named asset bytes. Do **not** call from `init_app`.
pub fn init_offline_translate(
    assets: Vec<OfflineModelAsset>,
) -> Result<(), TranslateErrorKind> {
    let domain_assets = assets
        .into_iter()
        .map(|a| translate::NamedAssetBytes {
            name: a.name,
            bytes: a.bytes,
        })
        .collect();
    translate::init_offline_translate(domain_assets).map_err(Into::into)
}

/// Translate a word or phrase (surface as displayed). Pair: EN→RU only (case-insensitive).
pub fn translate_text(
    text: String,
    source_lang: String,
    target_lang: String,
) -> Result<TranslationResult, TranslateErrorKind> {
    let result = translate::translate_text(&text, &source_lang, &target_lang)?;
    Ok(TranslationResult {
        primary_gloss: result.primary_gloss,
    })
}

/// Whether native offline translate has been successfully initialized.
pub fn is_offline_translate_ready() -> bool {
    translate::is_offline_translate_ready()
}
