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
        // Phrase identity = casefold(join with single spaces), not raw multi-space.
        return lower.split_whitespace().collect::<Vec<_>>().join(" ");
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

/// Design D2: morph singles **and** phrase windows → per-token `is_in_vocab`.
///
/// Each cue is `(surface, lemma_key)` pairs. Phrase keys (whitespace) match
/// consecutive `casefold(join(surfaces, " "))` windows; singles match
/// casefolded `lemma_key`. Overlaps OR to true.
pub fn mark_vocab_flags(
    cues: &[Vec<(String, String)>],
    vocab_lemmas: impl IntoIterator<Item = String>,
) -> Vec<Vec<bool>> {
    use std::collections::HashSet;

    let mut singles: HashSet<String> = HashSet::new();
    let mut phrases: Vec<(String, usize)> = Vec::new();
    for raw in vocab_lemmas {
        let key = casefold(raw.trim());
        if key.is_empty() {
            continue;
        }
        if key.chars().any(|c| c.is_whitespace()) {
            let parts: Vec<&str> = key.split_whitespace().collect();
            let word_count = parts.len();
            if word_count >= 2 {
                phrases.push((parts.join(" "), word_count));
            }
        } else {
            singles.insert(key);
        }
    }

    cues.iter()
        .map(|tokens| {
            let n = tokens.len();
            let mut flags: Vec<bool> = tokens
                .iter()
                .map(|(_, lemma_key)| {
                    let key = casefold(lemma_key.trim());
                    !key.is_empty() && singles.contains(&key)
                })
                .collect();
            for (phrase_key, word_count) in &phrases {
                if *word_count > n {
                    continue;
                }
                let last_start = n - word_count;
                for start in 0..=last_start {
                    let joined: String = tokens[start..start + word_count]
                        .iter()
                        .map(|(surface, _)| casefold(surface.trim()))
                        .collect::<Vec<_>>()
                        .join(" ");
                    if joined == *phrase_key {
                        for f in &mut flags[start..start + word_count] {
                            *f = true;
                        }
                    }
                }
            }
            flags
        })
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

    /// Whitespace phrase → casefold + single-space join (no WordNet).
    #[test]
    fn whitespace_phrase_casefold_no_wordnet() {
        assert_eq!(lemma_key_for_surface("look up"), "look up");
        assert_eq!(lemma_key_for_surface("  Look Up  "), "look up");
        assert_eq!(lemma_key_for_surface("look  up"), "look up");
        // Would be WordNet'd if single-token; phrase path must not morph-join.
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
