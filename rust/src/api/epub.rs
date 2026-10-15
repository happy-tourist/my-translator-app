//! Thin FRB export for EPUB parse (design D2).
//! Domain logic lives in [`crate::parse::epub`]; this module only maps DTOs.

use crate::parse::{self, EpubChapter, EpubDocument, EpubParseError};

/// One ordered EPUB chapter for Reader book-mode (FFI-flat).
pub struct EpubChapterDto {
    /// 0-based document order.
    pub index: u32,
    /// TOC label or stable fallback `"Chapter {n}"`.
    pub title: String,
    /// Non-empty plain paragraphs.
    pub paragraphs: Vec<String>,
}

/// Successful EPUB parse result for Flutter.
pub struct ParsedEpub {
    pub chapters: Vec<EpubChapterDto>,
}

/// Hard-failure kinds Flutter can switch on (design D2 / PE-05).
/// Separate from subtitle [`super::parse::ParseErrorKind`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EpubParseErrorKind {
    UnsupportedFormat,
    Malformed,
    Empty,
}

impl From<EpubParseError> for EpubParseErrorKind {
    fn from(value: EpubParseError) -> Self {
        match value {
            EpubParseError::UnsupportedFormat => Self::UnsupportedFormat,
            EpubParseError::Malformed => Self::Malformed,
            EpubParseError::Empty => Self::Empty,
        }
    }
}

impl From<EpubChapter> for EpubChapterDto {
    fn from(chapter: EpubChapter) -> Self {
        Self {
            index: chapter.index,
            title: chapter.title,
            paragraphs: chapter.paragraphs,
        }
    }
}

impl std::fmt::Display for EpubParseErrorKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnsupportedFormat => write!(f, "unsupported or unreadable EPUB format"),
            Self::Malformed => write!(f, "could not parse this EPUB file"),
            Self::Empty => write!(f, "no extractable text in EPUB"),
        }
    }
}

impl std::error::Error for EpubParseErrorKind {}

/// Parse EPUB bytes into ordered chapters. Maps domain errors to [`EpubParseErrorKind`].
pub fn parse_epub(bytes: Vec<u8>) -> Result<ParsedEpub, EpubParseErrorKind> {
    let doc: EpubDocument = parse::parse_epub(&bytes)?;
    Ok(ParsedEpub {
        chapters: doc.chapters.into_iter().map(EpubChapterDto::from).collect(),
    })
}
