//! Cue display-string tokenization (panko wrapper → owned word tokens + char spans).
//!
//! Input must match Flutter Reader paint: `text_lines.join('\n')`.
//! Only Word tokens are exported; Symbol/Newline advance the cursor (design D2).

use panko::Token;

/// Word token for one cue display string (owned; FFI-ready).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TokenSpan {
    pub surface: String,
    /// Inclusive Unicode scalar index in the cue display string.
    pub char_start: u32,
    /// Exclusive Unicode scalar index.
    pub char_end: u32,
    /// 0-based among word tokens in this cue.
    pub token_index: u32,
}

/// Tokenize one cue display string into word tokens with char spans.
///
/// Infallible for valid UTF-8 `&str`. Empty / whitespace-only → empty vec.
pub fn tokenize_cue(text: &str) -> Vec<TokenSpan> {
    let text_ptr = text.as_ptr() as usize;
    let mut out = Vec::new();
    let mut token_index: u32 = 0;
    // Cursor tracks consumption past Symbol/Newline for sequential integrity
    // with panko's Newline (no slice); Word/Symbol spans use pointer offsets.
    let mut cursor_byte: usize = 0;

    for token in panko::tokenize(text) {
        match token {
            Token::Word(w) => {
                let byte_start = (w.as_ptr() as usize).saturating_sub(text_ptr);
                debug_assert!(
                    byte_start <= text.len() && byte_start + w.len() <= text.len(),
                    "word slice must lie within cue text"
                );
                // Skip any interstitial (symbols / newlines) before this word.
                cursor_byte = byte_start + w.len();
                let char_start = text[..byte_start].chars().count() as u32;
                let char_end = char_start + (w.chars().count() as u32);
                out.push(TokenSpan {
                    surface: w.to_string(),
                    char_start,
                    char_end,
                    token_index,
                });
                token_index += 1;
            }
            Token::Symbol(s) => {
                let byte_start = (s.as_ptr() as usize).saturating_sub(text_ptr);
                cursor_byte = byte_start + s.len();
            }
            Token::Newline => {
                // Advance past the line separator `str::lines()` removed (`\n` or `\r\n`).
                let rest = &text[cursor_byte..];
                if rest.starts_with("\r\n") {
                    cursor_byte += 2;
                } else if rest.starts_with('\n') || rest.starts_with('\r') {
                    cursor_byte += 1;
                }
            }
        }
    }

    out
}

/// Batch-tokenize cue display strings. One result vec per input, same order.
pub fn tokenize_cues(texts: &[String]) -> Vec<Vec<TokenSpan>> {
    texts.iter().map(|t| tokenize_cue(t)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn char_slice(text: &str, start: u32, end: u32) -> String {
        text.chars()
            .skip(start as usize)
            .take((end - start) as usize)
            .collect()
    }

    fn assert_span_invariant(text: &str, tokens: &[TokenSpan]) {
        for t in tokens {
            assert_eq!(
                char_slice(text, t.char_start, t.char_end),
                t.surface,
                "surface must equal cue[char_start..char_end] for {:?}",
                t
            );
            assert!(t.char_start <= t.char_end);
        }
    }

    /// RT-11: Cyrillic words + `don't` as a single word token.
    #[test]
    fn rt11_cyrillic_and_apostrophe() {
        // Same join Flutter uses: text_lines.join('\n')
        let text = ["Привет мир", "I don't know"].join("\n");
        let tokens = tokenize_cue(&text);

        let surfaces: Vec<&str> = tokens.iter().map(|t| t.surface.as_str()).collect();
        assert!(
            surfaces.contains(&"Привет"),
            "expected Cyrillic word Привет, got {surfaces:?}"
        );
        assert!(
            surfaces.contains(&"мир"),
            "expected Cyrillic word мир, got {surfaces:?}"
        );
        assert!(
            surfaces.contains(&"don't"),
            "expected don't as one word, got {surfaces:?}"
        );
        assert!(
            !surfaces.iter().any(|s| *s == "don" || *s == "t"),
            "don't must not split on apostrophe, got {surfaces:?}"
        );

        assert_span_invariant(&text, &tokens);
    }

    /// RT-12: each word surface equals cue[char_start..char_end].
    #[test]
    fn rt12_span_surface_invariant() {
        let cases = [
            "Hello, world!",
            "Привет, мир!",
            "I don't know\nещё строка",
            "well-known e-mail",
            "",
            "   ",
            "one",
        ];
        for text in cases {
            let tokens = tokenize_cue(text);
            assert_span_invariant(text, &tokens);
        }
    }

    #[test]
    fn empty_and_whitespace_yield_no_words() {
        assert!(tokenize_cue("").is_empty());
        assert!(tokenize_cue("   \n  ").is_empty());
    }

    #[test]
    fn tokenize_cues_preserves_order_and_indices() {
        let texts = vec![
            "Hello world".to_string(),
            "don't".to_string(),
            "".to_string(),
        ];
        let batch = tokenize_cues(&texts);
        assert_eq!(batch.len(), 3);
        assert_eq!(batch[0].len(), 2);
        assert_eq!(batch[0][0].token_index, 0);
        assert_eq!(batch[0][1].token_index, 1);
        assert_eq!(batch[0][0].surface, "Hello");
        assert_eq!(batch[0][1].surface, "world");
        assert_eq!(batch[1].len(), 1);
        assert_eq!(batch[1][0].surface, "don't");
        assert!(batch[2].is_empty());
        for (i, text) in texts.iter().enumerate() {
            assert_span_invariant(text, &batch[i]);
        }
    }

    #[test]
    fn multiline_join_matches_display_string() {
        let lines = vec!["первая".to_string(), "вторая".to_string()];
        let text = lines.join("\n");
        let tokens = tokenize_cue(&text);
        assert_eq!(tokens.len(), 2);
        assert_eq!(tokens[0].surface, "первая");
        assert_eq!(tokens[1].surface, "вторая");
        // Second word starts after "первая\n"
        assert_eq!(tokens[1].char_start, "первая\n".chars().count() as u32);
        assert_span_invariant(&text, &tokens);
    }
}
