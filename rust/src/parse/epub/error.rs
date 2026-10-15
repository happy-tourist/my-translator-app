//! Typed EPUB parse failures (design D2 / PE-05).

/// Hard-failure kinds for EPUB parse (separate from subtitle [`crate::parse::ParseError`]).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EpubParseError {
    /// Bytes are not a readable EPUB / wrong container.
    UnsupportedFormat,
    /// EPUB opened but structure/content is unusable mid-parse.
    Malformed,
    /// No chapter with at least one non-empty paragraph.
    Empty,
}

impl std::fmt::Display for EpubParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnsupportedFormat => write!(f, "unsupported or unreadable EPUB format"),
            Self::Malformed => write!(f, "could not parse this EPUB file"),
            Self::Empty => write!(f, "no extractable text in EPUB"),
        }
    }
}

impl std::error::Error for EpubParseError {}
