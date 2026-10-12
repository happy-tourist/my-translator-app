//! EN WordNet morph lemma keys (design D1 / D3).
//!
//! `OnceLock<Lemmatizer>` + POS cascade Noun → Verb → Adj; whitespace → casefold only.

use std::sync::OnceLock;

use wordnet_lemmatizer::{Lemmatizer, Pos};

static LEMMATIZER: OnceLock<Lemmatizer> = OnceLock::new();

fn lemmatizer() -> &'static Lemmatizer {
    LEMMATIZER.get_or_init(Lemmatizer::embedded)
}

/// Unicode lowercase (BMP-aligned with Flutter `toLowerCase` for fixtures).
pub fn casefold(s: &str) -> String {
    s.to_lowercase()
}

/// Locked D3 algorithm: trim → casefold → whitespace short-circuit → POS cascade.
pub fn lemma_key_for_surface(surface: &str) -> String {
    let trimmed = surface.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let lower = casefold(trimmed);
    if lower.chars().any(|c| c.is_whitespace()) {
        return lower;
    }
    let lem = lemmatizer();
    for pos in [Pos::Noun, Pos::Verb, Pos::Adj] {
        let candidate = lem.lemmatize(&lower, pos);
        if candidate != lower {
            return candidate;
        }
    }
    lower
}

/// Batch map of [`lemma_key_for_surface`] — same order as input.
pub fn lemma_keys_for_surfaces(surfaces: &[String]) -> Vec<String> {
    surfaces
        .iter()
        .map(|s| lemma_key_for_surface(s))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// RH-10: EN wordforms dogs/running → dog/run.
    #[test]
    fn rh10_en_wordforms_dogs_running() {
        assert_eq!(lemma_key_for_surface("dogs"), "dog");
        assert_eq!(lemma_key_for_surface("Dogs"), "dog");
        assert_eq!(lemma_key_for_surface("running"), "run");
        assert_eq!(lemma_key_for_surface("Running"), "run");
    }

    /// RH-11: Cyrillic / junk → casefold (no EN morph change).
    #[test]
    fn rh11_cyrillic_and_junk_casefold() {
        assert_eq!(lemma_key_for_surface("Привет"), "привет");
        assert_eq!(lemma_key_for_surface("  ПРИВЕТ  "), "привет");
        assert_eq!(lemma_key_for_surface("xyzzy99"), "xyzzy99");
        assert_eq!(lemma_key_for_surface("XyzZy"), "xyzzy");
    }

    /// Whitespace phrase → casefold only (no WordNet).
    #[test]
    fn whitespace_phrase_casefold_no_wordnet() {
        assert_eq!(lemma_key_for_surface("look up"), "look up");
        assert_eq!(lemma_key_for_surface("  Look Up  "), "look up");
        // Would be WordNet'd if single-token; phrase path must not collapse.
        assert_eq!(lemma_key_for_surface("dogs running"), "dogs running");
    }

    #[test]
    fn empty_trim_yields_empty() {
        assert_eq!(lemma_key_for_surface(""), "");
        assert_eq!(lemma_key_for_surface("   "), "");
    }

    #[test]
    fn lemma_keys_for_surfaces_preserves_order() {
        let surfaces = vec![
            "dogs".to_string(),
            "running".to_string(),
            "Привет".to_string(),
            "look up".to_string(),
        ];
        assert_eq!(
            lemma_keys_for_surfaces(&surfaces),
            vec![
                "dog".to_string(),
                "run".to_string(),
                "привет".to_string(),
                "look up".to_string(),
            ]
        );
    }
}
