//! Thin FRB export for cue tokenization (design D3).
//! Domain logic lives in [`crate::tokenize`]; this module only maps DTOs.

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
}

/// Tokens for one cue in a batch (index matches input order).
pub struct CueTokensDto {
    /// Index into the input `texts` vec (same order as batch args).
    pub cue_index: u32,
    pub tokens: Vec<TokenDto>,
}

impl From<TokenSpan> for TokenDto {
    fn from(t: TokenSpan) -> Self {
        Self {
            surface: t.surface,
            char_start: t.char_start,
            char_end: t.char_end,
            token_index: t.token_index,
        }
    }
}

/// Batch-tokenize cue display strings. One [`CueTokensDto`] per input, same order.
///
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
