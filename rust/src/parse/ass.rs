//! ASS/SSA via `fasrt::ass::Parser::lossy` + Dialogue filter (design D1).

use super::cue::{duration_ms, split_text_lines, Cue};
use super::ParseError;
use fasrt::ass::{Block, EventKind};

/// Parse ASS/SSA text; only `EventKind::Dialogue` becomes cues.
pub fn parse_ass(text: &str) -> Result<Vec<Cue>, ParseError> {
    let mut cues = Vec::new();
    let mut saw_hard_error = false;

    for item in fasrt::ass::Parser::lossy(text) {
        match item {
            Ok(Block::Event(event)) if event.kind() == EventKind::Dialogue => {
                let (Some(start), Some(end)) = (event.start(), event.end()) else {
                    // Incomplete timing — skip in lossy policy.
                    continue;
                };
                let start_ms = duration_ms(start.to_duration());
                let end_ms = duration_ms(end.to_duration());
                // Strip `{…}` / `\N` → plain visual lines.
                let plain = event.plain_text();
                let text_lines = split_text_lines(plain.normalize());
                let index = cues.len() as u32;
                cues.push(Cue {
                    index,
                    start_ms,
                    end_ms,
                    text_lines,
                });
            }
            Ok(_) => {}
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
