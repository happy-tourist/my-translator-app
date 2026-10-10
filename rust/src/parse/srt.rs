//! SRT via `fasrt::srt::Parser::lossy` (design D1).

use super::cue::{duration_ms, split_text_lines, Cue};
use super::ParseError;

/// Parse SRT text with fasrt lossy mode; skip broken blocks.
pub fn parse_srt(text: &str) -> Result<Vec<Cue>, ParseError> {
    let mut cues = Vec::new();
    let mut saw_hard_error = false;

    for item in fasrt::srt::Parser::lossy(text) {
        match item {
            Ok(entry) => {
                let header = entry.header_ref();
                let start_ms = duration_ms(header.start().to_duration());
                let end_ms = duration_ms(header.end().to_duration());
                let text_lines = split_text_lines(entry.body_ref());
                let index = cues.len() as u32;
                cues.push(Cue {
                    index,
                    start_ms,
                    end_ms,
                    text_lines,
                });
            }
            Err(_) => {
                // Lossy iterators may still surface a terminal hard error.
                saw_hard_error = true;
                break;
            }
        }
    }

    if cues.is_empty() {
        if saw_hard_error {
            Err(ParseError::Malformed)
        } else {
            Err(ParseError::Empty)
        }
    } else {
        Ok(cues)
    }
}
