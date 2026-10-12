//! Thin FRB export for cue tokenization + morph keys (design D2 / D3).
//! Domain logic lives in [`crate::tokenize`] and [`crate::lemmatize`].

use std::collections::HashSet;

use crate::lemmatize;
use crate::tokenize::{self, TokenSpan};

/// Word token for one cue display string (FFI-owned).
pub struct TokenDto {
    pub surface: String,
    /// Inclusive Unicode scalar index in cue text.
    pub char_start: u32,
    /// Exclusive Unicode scalar index.
    pub char_end: u32,
    /// 0-based among word tokens in this cue.
    pub token_index: u32,
    /// Morph lemma key (D3); identity for dictionary membership.
    pub lemma_key: String,
    /// Set by [`mark_vocab_tokens`]; false after [`tokenize_cues`].
    pub is_in_vocab: bool,
}

/// Tokens for one cue in a batch (index matches input order).
pub struct CueTokensDto {
    /// Index into the input `texts` vec (same order as batch args).
    pub cue_index: u32,
    pub tokens: Vec<TokenDto>,
}

impl From<TokenSpan> for TokenDto {
    fn from(t: TokenSpan) -> Self {
        let lemma_key = lemmatize::lemma_key_for_surface(&t.surface);
        Self {
            surface: t.surface,
            char_start: t.char_start,
            char_end: t.char_end,
            token_index: t.token_index,
            lemma_key,
            is_in_vocab: false,
        }
    }
}

/// Batch-tokenize + lemmatize cue display strings. One [`CueTokensDto`] per input.
///
/// `is_in_vocab` is always `false` until [`mark_vocab_tokens`].
/// Infallible for valid Rust `String` (UTF-8): empty input → empty `tokens`.
pub fn tokenize_cues(texts: Vec<String>) -> Vec<CueTokensDto> {
    tokenize::tokenize_cues(&texts)
        .into_iter()
        .enumerate()
        .map(|(i, tokens)| CueTokensDto {
            cue_index: i as u32,
            tokens: tokens.into_iter().map(TokenDto::from).collect(),
        })
        .collect()
}

/// Set `is_in_vocab` from morph lemma set (casefold both sides before equality).
pub fn mark_vocab_tokens(
    cues: Vec<CueTokensDto>,
    vocab_lemmas: Vec<String>,
) -> Vec<CueTokensDto> {
    let vocab: HashSet<String> = vocab_lemmas
        .into_iter()
        .map(|s| lemmatize::casefold(s.trim()))
        .filter(|s| !s.is_empty())
        .collect();
    cues.into_iter()
        .map(|mut cue| {
            for t in &mut cue.tokens {
                let key = lemmatize::casefold(t.lemma_key.trim());
                t.is_in_vocab = !key.is_empty() && vocab.contains(&key);
            }
            cue
        })
        .collect()
}

/// Same D3 algorithm without tokenize — Vocab UI / stub→morph migration.
/// One output per input, same order. Whitespace surfaces → casefold only.
pub fn lemma_keys_for_surfaces(surfaces: Vec<String>) -> Vec<String> {
    lemmatize::lemma_keys_for_surfaces(&surfaces)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cue_with(tokens: Vec<TokenDto>) -> CueTokensDto {
        CueTokensDto {
            cue_index: 0,
            tokens,
        }
    }

    fn tok(index: u32, surface: &str, lemma_key: &str) -> TokenDto {
        TokenDto {
            surface: surface.to_string(),
            char_start: 0,
            char_end: surface.chars().count() as u32,
            token_index: index,
            lemma_key: lemma_key.to_string(),
            is_in_vocab: false,
        }
    }

    /// RH-09: membership from vocab lemma set (casefold).
    #[test]
    fn mark_vocab_tokens_sets_membership_casefold() {
        let cues = vec![cue_with(vec![
            tok(0, "Running", "run"),
            tok(1, "Dogs", "dog"),
            tok(2, "other", "other"),
        ])];
        let marked = mark_vocab_tokens(cues, vec!["RUN".to_string()]);
        assert!(marked[0].tokens[0].is_in_vocab);
        assert!(!marked[0].tokens[1].is_in_vocab);
        assert!(!marked[0].tokens[2].is_in_vocab);
    }

    /// RH-08: multi-word vocab keys do not mark single-token lemma_keys.
    #[test]
    fn mark_vocab_tokens_phrase_keys_do_not_match_tokens() {
        let cues = vec![cue_with(vec![
            tok(0, "hello", "hello"),
            tok(1, "world", "world"),
        ])];
        let marked =
            mark_vocab_tokens(cues, vec!["hello world".to_string()]);
        assert!(!marked[0].tokens[0].is_in_vocab);
        assert!(!marked[0].tokens[1].is_in_vocab);
    }

    #[test]
    fn lemma_keys_for_surfaces_batch_matches_d3() {
        let keys = lemma_keys_for_surfaces(vec![
            "dogs".to_string(),
            "running".to_string(),
            "look up".to_string(),
        ]);
        assert_eq!(keys, vec!["dog", "run", "look up"]);
    }
}
