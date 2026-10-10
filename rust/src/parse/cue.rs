//! FFI-flat cue model (design D3).

use super::Format;

/// One ordered subtitle cue for Reader display.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Cue {
    /// 0-based order in the document.
    pub index: u32,
    /// Cue start time in milliseconds.
    pub start_ms: u64,
    /// Cue end time in milliseconds.
    pub end_ms: u64,
    /// Visual text lines (plain text; style markup stripped where applicable).
    pub text_lines: Vec<String>,
}

/// Successful parse result: detected format plus ordered cues.
/// Named differently from FRB DTO [`crate::api::parse::ParsedSubtitles`] to avoid
/// codegen merge ambiguity on the same type name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedDocument {
    pub format: Format,
    pub cues: Vec<Cue>,
}

/// Split cue body text into visual lines (keeps blank interior lines).
pub(crate) fn split_text_lines(text: &str) -> Vec<String> {
    let lines: Vec<String> = text.lines().map(str::to_owned).collect();
    if lines.is_empty() {
        vec![String::new()]
    } else {
        lines
    }
}

/// Map `Timestamp::to_duration()` → ms as `u64`.
pub(crate) fn duration_ms(duration: std::time::Duration) -> u64 {
    duration.as_millis() as u64
}
