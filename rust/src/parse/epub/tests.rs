//! Unit tests mapped to parse/epub SC-IDs (PE-01…PE-06).

use super::{parse_epub, EpubParseError};

// --- PE-01: Parse EPUB with TOC into chapters ---

#[test]
fn pe01_parse_epub_with_toc_into_chapters() {
    let bytes = include_bytes!("fixtures/pe01_toc.epub");
    let parsed = parse_epub(bytes).expect("PE-01 TOC EPUB should parse");
    assert_eq!(parsed.chapters.len(), 2);
    assert_eq!(parsed.chapters[0].index, 0);
    assert_eq!(parsed.chapters[0].title, "First Chapter");
    assert!(
        parsed.chapters[0].paragraphs.len() >= 1,
        "chapter one should have paragraphs: {:?}",
        parsed.chapters[0].paragraphs
    );
    assert!(parsed.chapters[0]
        .paragraphs
        .iter()
        .any(|p| p.contains("chapter one")));
    assert_eq!(parsed.chapters[1].index, 1);
    assert_eq!(parsed.chapters[1].title, "Second Chapter");
    assert!(parsed.chapters[1]
        .paragraphs
        .iter()
        .any(|p| p.contains("chapter two")));
}

// --- PE-02: Nested TOC entries become chapters ---

#[test]
fn pe02_nested_toc_entries_become_chapters() {
    let bytes = include_bytes!("fixtures/pe02_nested.epub");
    let parsed = parse_epub(bytes).expect("PE-02 nested TOC should parse");
    let titles: Vec<&str> = parsed.chapters.iter().map(|c| c.title.as_str()).collect();
    assert_eq!(titles, vec!["Part One", "Section A", "Section B"]);
    assert!(parsed.chapters[0]
        .paragraphs
        .iter()
        .any(|p| p.contains("Part introduction")));
    assert!(parsed.chapters[1]
        .paragraphs
        .iter()
        .any(|p| p.contains("Nested section A")));
    assert!(parsed.chapters[2]
        .paragraphs
        .iter()
        .any(|p| p.contains("Nested section B")));
}

// --- PE-03: Missing TOC yields single chapter ---

#[test]
fn pe03_missing_toc_yields_single_chapter() {
    let bytes = include_bytes!("fixtures/pe03_no_toc.epub");
    let parsed = parse_epub(bytes).expect("PE-03 no-TOC EPUB should parse");
    assert_eq!(parsed.chapters.len(), 1);
    assert_eq!(parsed.chapters[0].index, 0);
    assert_eq!(parsed.chapters[0].title, "Chapter 1");
    let joined = parsed.chapters[0].paragraphs.join(" ");
    assert!(joined.contains("paragraph one"));
    assert!(joined.contains("paragraph two"));
}

// --- PE-04: Strip markup to plain paragraphs ---

#[test]
fn pe04_strip_markup_to_plain_paragraphs() {
    let bytes = include_bytes!("fixtures/pe04_markup.epub");
    let parsed = parse_epub(bytes).expect("PE-04 markup EPUB should parse");
    assert_eq!(parsed.chapters.len(), 1);
    let paras = &parsed.chapters[0].paragraphs;
    assert!(paras.len() >= 2, "expected multiple paragraphs: {paras:?}");
    for p in paras {
        assert!(
            !p.contains('<') && !p.contains('>'),
            "paragraph must be plain text without tags: {p:?}"
        );
    }
    let joined = paras.join(" | ");
    assert!(joined.contains("bold"));
    assert!(joined.contains("Div block text"));
    assert!(joined.contains("List item one"));
    assert!(joined.contains("Final paragraph"));
}

// --- PE-05: Reject empty or unreadable EPUB ---

#[test]
fn pe05_reject_empty_bytes() {
    let err = parse_epub(&[]).expect_err("PE-05 empty bytes");
    assert_eq!(err, EpubParseError::UnsupportedFormat);
}

#[test]
fn pe05_reject_garbage_bytes() {
    let err = parse_epub(b"this is not an epub zip").expect_err("PE-05 garbage");
    assert!(
        matches!(
            err,
            EpubParseError::UnsupportedFormat | EpubParseError::Malformed
        ),
        "unexpected kind: {err:?}"
    );
}

#[test]
fn pe05_reject_empty_text_epub() {
    let bytes = include_bytes!("fixtures/pe05_empty_text.epub");
    let err = parse_epub(bytes).expect_err("PE-05 empty text");
    assert_eq!(err, EpubParseError::Empty);
}

// --- PE-06: Accept bytes without path ---

#[test]
fn pe06_accept_bytes_without_path() {
    let bytes = include_bytes!("fixtures/pe01_toc.epub");
    // Owned buffer — no filesystem path involved.
    let owned = bytes.to_vec();
    let parsed = parse_epub(&owned).expect("PE-06 bytes buffer should parse");
    assert!(parsed.chapters.len() >= 1);
    assert!(parsed.chapters.iter().all(|c| !c.paragraphs.is_empty()));
}

#[test]
fn fragment_href_reads_whole_resource() {
    let bytes = include_bytes!("fixtures/pe_fragment.epub");
    let parsed = parse_epub(bytes).expect("fragment fixture should parse");
    assert_eq!(parsed.chapters.len(), 2);
    // Both TOC points share one file; v1 ignores fragment → same full body.
    assert_eq!(
        parsed.chapters[0].paragraphs, parsed.chapters[1].paragraphs,
        "fragment ignore: both chapters get full resource body"
    );
    assert!(parsed.chapters[0]
        .paragraphs
        .iter()
        .any(|p| p.contains("Section one")));
    assert!(parsed.chapters[0]
        .paragraphs
        .iter()
        .any(|p| p.contains("Section two")));
}
