//! WebVTT via `fasrt::vtt::Parser::new` (built-in recovery; design D1).

use super::cue::{duration_ms, split_text_lines, Cue};
use super::ParseError;
use fasrt::vtt::Block;

/// Parse WebVTT text; malformed timing is recovered by fasrt.
pub fn parse_vtt(text: &str) -> Result<Vec<Cue>, ParseError> {
    let mut cues = Vec::new();
    let mut saw_hard_error = false;

    for item in fasrt::vtt::Parser::new(text) {
        match item {
            Ok(Block::Cue(cue)) => {
                let header = cue.header_ref();
                let start_ms = duration_ms(header.start().to_duration());
                let end_ms = duration_ms(header.end().to_duration());
                let text_lines = split_text_lines(cue.body_ref());
                let index = cues.len() as u32;
                cues.push(Cue {
                    index,
                    start_ms,
                    end_ms,
                    text_lines,
                });
            }
            Ok(_) => {
                // NOTE / STYLE / REGION — ignore for Reader v1.
            }
            Err(_) => {
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
