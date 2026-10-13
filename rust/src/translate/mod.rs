//! Offline word/phrase translate domain (OPUS-MT EN→RU).
//!
//! Native: ORT Marian loop in [`opus`]. Wasm32: same public symbols stub to
//! [`TranslateError::EngineUnavailable`] so FRB WASM does not link ORT.
//!
//! FRB thin wrappers live in [`crate::api::translate`].

mod error;
mod types;

#[cfg(not(target_arch = "wasm32"))]
mod opus;

pub(crate) use error::TranslateError;
pub(crate) use types::{GlossResult, NamedAssetBytes};

use std::sync::{Arc, Mutex, OnceLock};

/// Internal engine contract (design D3).
pub(crate) trait OfflineTranslator: Send + Sync {
    fn translate(
        &self,
        text: &str,
        source_lang: &str,
        target_lang: &str,
    ) -> Result<GlossResult, TranslateError>;
}

fn engine_slot() -> &'static Mutex<Option<Arc<dyn OfflineTranslator>>> {
    static ENGINE: OnceLock<Mutex<Option<Arc<dyn OfflineTranslator>>>> = OnceLock::new();
    ENGINE.get_or_init(|| Mutex::new(None))
}

/// Normalize language tag to lower ASCII (trim + ASCII lower).
pub(crate) fn normalize_lang(lang: &str) -> String {
    lang.trim().to_ascii_lowercase()
}

/// Reject empty / whitespace-only queries.
pub(crate) fn validate_query(text: &str) -> Result<&str, TranslateError> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        Err(TranslateError::EmptyQuery)
    } else {
        Ok(trimmed)
    }
}

/// v1 supports only EN→RU after normalize.
pub(crate) fn validate_language_pair(
    source_lang: &str,
    target_lang: &str,
) -> Result<(), TranslateError> {
    if normalize_lang(source_lang) == "en" && normalize_lang(target_lang) == "ru" {
        Ok(())
    } else {
        Err(TranslateError::UnsupportedLanguagePair)
    }
}

/// Load ORT sessions from named asset bytes. Replaces any prior engine.
///
/// On `wasm32`, always [`TranslateError::EngineUnavailable`].
pub(crate) fn init_offline_translate(
    assets: Vec<NamedAssetBytes>,
) -> Result<(), TranslateError> {
    #[cfg(target_arch = "wasm32")]
    {
        let _ = assets;
        let mut slot = engine_slot()
            .lock()
            .map_err(|_| TranslateError::Internal)?;
        *slot = None;
        return Err(TranslateError::EngineUnavailable);
    }

    #[cfg(not(target_arch = "wasm32"))]
    {
        // Build sessions outside the slot lock so concurrent ready/translate
        // checks are not blocked for the whole ORT load.
        let engine = opus::OpusMtEnRu::from_assets(assets)?;
        let mut slot = engine_slot()
            .lock()
            .map_err(|_| TranslateError::Internal)?;
        *slot = Some(Arc::new(engine));
        Ok(())
    }
}

/// Whether a native engine has been successfully initialized.
pub(crate) fn is_offline_translate_ready() -> bool {
    engine_slot()
        .lock()
        .map(|g| g.is_some())
        .unwrap_or(false)
}

/// Translate surface text (word or phrase). Validates query + pair before engine.
pub(crate) fn translate_text(
    text: &str,
    source_lang: &str,
    target_lang: &str,
) -> Result<GlossResult, TranslateError> {
    let text = validate_query(text)?;
    validate_language_pair(source_lang, target_lang)?;

    // Clone Arc under a short lock; run ORT without holding the global slot
    // (avoids stalling is_offline_translate_ready / re-init during inference).
    let engine = {
        let slot = engine_slot()
            .lock()
            .map_err(|_| TranslateError::Internal)?;
        slot.as_ref()
            .cloned()
            .ok_or(TranslateError::EngineUnavailable)?
    };
    engine.translate(text, "en", "ru")
}

/// Test / fixture helper: install a fake engine (clears on next real init).
#[cfg(test)]
pub(crate) fn install_engine_for_test(engine: Box<dyn OfflineTranslator>) {
    let mut slot = engine_slot().lock().expect("engine mutex");
    *slot = Some(Arc::from(engine));
}

/// Test helper: drop the installed engine.
#[cfg(test)]
pub(crate) fn clear_engine_for_test() {
    let mut slot = engine_slot().lock().expect("engine mutex");
    *slot = None;
}

#[cfg(test)]
mod tests;
