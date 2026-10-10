//! Thin FRB export for subtitle parse (design D2).
//! Domain logic lives in [`crate::parse`]; this module only maps DTOs.

use crate::parse::{self, Cue, ParseError};

/// One ordered subtitle cue for Reader display (FFI-flat).
pub struct CueDto {
    pub index: u32,
    pub start_ms: u64,
    pub end_ms: u64,
    pub text_lines: Vec<String>,
}

/// Successful parse result for Flutter.
pub struct ParsedSubtitles {
    /// Detected format: `"srt"` | `"vtt"` | `"ass"`.
    pub format: String,
    pub cues: Vec<CueDto>,
}

/// Hard-failure kinds Flutter can switch on (design D4).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseErrorKind {
    UnsupportedFormat,
    Encoding,
    Empty,
    Malformed,
}

impl From<ParseError> for ParseErrorKind {
    fn from(value: ParseError) -> Self {
        match value {
            ParseError::UnsupportedFormat => Self::UnsupportedFormat,
            ParseError::Encoding => Self::Encoding,
            ParseError::Empty => Self::Empty,
            ParseError::Malformed => Self::Malformed,
        }
    }
}

impl From<Cue> for CueDto {
    fn from(cue: Cue) -> Self {
        Self {
            index: cue.index,
            start_ms: cue.start_ms,
            end_ms: cue.end_ms,
            text_lines: cue.text_lines,
        }
    }
}

impl std::fmt::Display for ParseErrorKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnsupportedFormat => write!(f, "unsupported or unrecognized subtitle format"),
            Self::Encoding => write!(f, "file encoding is not valid UTF-8"),
            Self::Empty => write!(f, "no subtitle cues found"),
            Self::Malformed => write!(f, "could not parse this subtitle file"),
        }
    }
}

impl std::error::Error for ParseErrorKind {}

/// Parse subtitle bytes into ordered cues. Maps domain errors to [`ParseErrorKind`].
pub fn parse_subtitles(
    bytes: Vec<u8>,
    format_hint: Option<String>,
) -> Result<ParsedSubtitles, ParseErrorKind> {
    let doc = parse::parse_subtitles(&bytes, format_hint.as_deref())?;
    Ok(ParsedSubtitles {
        format: doc.format.as_str().into(),
        cues: doc.cues.into_iter().map(CueDto::from).collect(),
    })
}
