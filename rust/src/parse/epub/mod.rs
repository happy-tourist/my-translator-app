//! EPUB bytes → ordered chapters with plain paragraphs (design D1–D3, D9).
//!
//! Domain module; thin FRB export lives in [`crate::api::epub`].

mod error;
mod strip;

pub use error::EpubParseError;
pub use strip::strip_xhtml_to_paragraphs;

use rbook::ebook::errors::EbookError;
use rbook::ebook::toc::TocEntry;
use rbook::Epub;
use std::io::Cursor;

/// One chapter in document order (0-based index).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EpubChapter {
    pub index: u32,
    pub title: String,
    pub paragraphs: Vec<String>,
}

/// Successful EPUB parse result (domain; FRB DTO is [`crate::api::epub::ParsedEpub`]).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EpubDocument {
    pub chapters: Vec<EpubChapter>,
}

/// Parse EPUB bytes into ordered chapters (no filesystem path).
pub fn parse_epub(bytes: &[u8]) -> Result<EpubDocument, EpubParseError> {
    if bytes.is_empty() {
        return Err(EpubParseError::UnsupportedFormat);
    }

    // rbook requires a 'static Read+Seek source (Cursor<&[u8]> will not compile).
    let cursor = Cursor::new(bytes.to_vec());
    let epub = Epub::read(cursor).map_err(map_open_error)?;

    let mut chapters = chapters_from_toc(&epub)?;
    if chapters.is_empty() {
        chapters = chapters_from_spine(&epub)?;
    }

    chapters.retain(|c| !c.paragraphs.is_empty());
    if chapters.is_empty() {
        return Err(EpubParseError::Empty);
    }

    for (i, ch) in chapters.iter_mut().enumerate() {
        ch.index = i as u32;
        if ch.title.trim().is_empty() {
            ch.title = format!("Chapter {}", i + 1);
        }
    }

    Ok(EpubDocument { chapters })
}

fn chapters_from_toc(epub: &Epub) -> Result<Vec<EpubChapter>, EpubParseError> {
    let Some(root) = epub.toc().contents() else {
        return Ok(Vec::new());
    };

    let mut chapters = Vec::new();
    collect_toc_preorder(epub, &root, &mut chapters)?;
    Ok(chapters)
}

fn collect_toc_preorder<'a, E: TocEntry<'a>>(
    epub: &Epub,
    entry: &E,
    out: &mut Vec<EpubChapter>,
) -> Result<(), EpubParseError> {
    // Root is structural; process non-root entries that resolve to text.
    if !entry.is_root() {
        try_push_toc_chapter(epub, entry, out)?;
    }
    for child in entry.iter() {
        collect_toc_preorder(epub, &child, out)?;
    }
    Ok(())
}

fn try_push_toc_chapter<'a, E: TocEntry<'a>>(
    epub: &Epub,
    entry: &E,
    out: &mut Vec<EpubChapter>,
) -> Result<(), EpubParseError> {
    let Some(resource) = entry.resource() else {
        // Structural node without resource — children may still become chapters.
        return Ok(());
    };

    // Fragment (`#…`) ignored: whole XHTML resource is read.
    // `read_resource_str` returns `ArchiveError` on missing/unreadable entries.
    let Ok(xhtml) = epub.read_resource_str(resource) else {
        return Ok(());
    };

    let paragraphs = strip_xhtml_to_paragraphs(&xhtml);
    if paragraphs.is_empty() {
        return Ok(());
    }

    let index = out.len() as u32;
    let label = entry.label().trim();
    let title = if label.is_empty() {
        format!("Chapter {}", index + 1)
    } else {
        label.to_owned()
    };

    out.push(EpubChapter {
        index,
        title,
        paragraphs,
    });
    Ok(())
}

fn chapters_from_spine(epub: &Epub) -> Result<Vec<EpubChapter>, EpubParseError> {
    let mut paragraphs = Vec::new();
    for data_result in epub.reader() {
        let data = data_result.map_err(|_| EpubParseError::Malformed)?;
        let mut paras = strip_xhtml_to_paragraphs(data.content());
        paragraphs.append(&mut paras);
    }

    if paragraphs.is_empty() {
        return Ok(Vec::new());
    }

    Ok(vec![EpubChapter {
        index: 0,
        title: "Chapter 1".to_owned(),
        paragraphs,
    }])
}

fn map_open_error(err: EbookError) -> EpubParseError {
    match err {
        EbookError::Archive(_) | EbookError::Format(_) => EpubParseError::UnsupportedFormat,
        EbookError::Reader(_) => EpubParseError::Malformed,
        _ => EpubParseError::Malformed,
    }
}

#[cfg(test)]
mod tests;
