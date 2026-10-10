//! Typed parse failures for the subtitle pipeline (design D4).

/// Hard-failure kinds surfaced to FRB / UI mapping.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    /// Content is not SRT, WebVTT, or ASS/SSA (and hint does not salvage it).
    UnsupportedFormat,
    /// Bytes are not valid UTF-8 under the strict decode policy (D6).
    Encoding,
    /// Format recognized but zero cues after parse (empty = error for Reader).
    Empty,
    /// Format detected, but fasrt reported an unrecoverable hard failure.
    Malformed,
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnsupportedFormat => write!(f, "unsupported or unrecognized subtitle format"),
            Self::Encoding => write!(f, "file encoding is not valid UTF-8"),
            Self::Empty => write!(f, "no subtitle cues found"),
            Self::Malformed => write!(f, "could not parse this subtitle file"),
        }
    }
}

impl std::error::Error for ParseError {}
