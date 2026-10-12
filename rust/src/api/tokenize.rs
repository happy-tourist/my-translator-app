//! Thin FRB export for cue tokenization + morph keys (design D2 / D3).
//! Domain logic lives in [`crate::tokenize`] and [`crate::lemmatize`].

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

/// Set `is_in_vocab` from morph singles **and** phrase windows (design D2).
///
/// Thin FRB wrapper over [`lemmatize::mark_vocab_flags`].
pub fn mark_vocab_tokens(
    cues: Vec<CueTokensDto>,
    vocab_lemmas: Vec<String>,
) -> Vec<CueTokensDto> {
    let pairs: Vec<Vec<(String, String)>> = cues
        .iter()
        .map(|cue| {
            cue.tokens
                .iter()
                .map(|t| (t.surface.clone(), t.lemma_key.clone()))
                .collect()
        })
        .collect();
    let flags = lemmatize::mark_vocab_flags(&pairs, vocab_lemmas);
    cues.into_iter()
        .zip(flags)
        .map(|(mut cue, cue_flags)| {
            for (t, flag) in cue.tokens.iter_mut().zip(cue_flags) {
                t.is_in_vocab = flag;
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

    /// RH-08: phrase key marks every token in the matched consecutive span.
    #[test]
    fn mark_vocab_tokens_phrase_marks_all_span_tokens() {
        let cues = vec![cue_with(vec![
            tok(0, "hello", "hello"),
            tok(1, "world", "world"),
            tok(2, "other", "other"),
        ])];
        let marked =
            mark_vocab_tokens(cues, vec!["hello world".to_string()]);
        assert!(marked[0].tokens[0].is_in_vocab);
        assert!(marked[0].tokens[1].is_in_vocab);
        assert!(!marked[0].tokens[2].is_in_vocab);
    }

    /// RH-13: overlapping phrase keys both paint (OR membership).
    #[test]
    fn mark_vocab_tokens_overlapping_phrases_both_paint() {
        let cues = vec![cue_with(vec![
            tok(0, "a", "a"),
            tok(1, "b", "b"),
            tok(2, "c", "c"),
        ])];
        let marked = mark_vocab_tokens(
            cues,
            vec!["a b".to_string(), "b c".to_string()],
        );
        assert!(marked[0].tokens[0].is_in_vocab);
        assert!(marked[0].tokens[1].is_in_vocab);
        assert!(marked[0].tokens[2].is_in_vocab);
    }

    /// RH-14: phrase match is token-join, not cue substring (punct ignored).
    #[test]
    fn mark_vocab_tokens_phrase_is_token_join_not_substring() {
        // Surfaces "hello" / "world" with punct between in raw cue — join still hits.
        let cues = vec![cue_with(vec![
            tok(0, "Hello", "hello"),
            tok(1, "World", "world"),
        ])];
        let marked =
            mark_vocab_tokens(cues, vec!["hello world".to_string()]);
        assert!(marked[0].tokens[0].is_in_vocab);
        assert!(marked[0].tokens[1].is_in_vocab);
    }

    /// Irregular whitespace in phrase dict keys still matches single-space join.
    #[test]
    fn mark_vocab_tokens_phrase_collapses_dict_whitespace() {
        let cues = vec![cue_with(vec![
            tok(0, "hello", "hello"),
            tok(1, "world", "world"),
        ])];
        let marked =
            mark_vocab_tokens(cues, vec!["hello  world".to_string()]);
        assert!(marked[0].tokens[0].is_in_vocab);
        assert!(marked[0].tokens[1].is_in_vocab);
    }

    /// Morph singles still mark when phrase keys are also present (RH-01/09).
    #[test]
    fn mark_vocab_tokens_morph_or_phrase() {
        let cues = vec![cue_with(vec![
            tok(0, "Running", "run"),
            tok(1, "hello", "hello"),
            tok(2, "world", "world"),
        ])];
        let marked = mark_vocab_tokens(
            cues,
            vec!["run".to_string(), "hello world".to_string()],
        );
        assert!(marked[0].tokens[0].is_in_vocab);
        assert!(marked[0].tokens[1].is_in_vocab);
        assert!(marked[0].tokens[2].is_in_vocab);
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
