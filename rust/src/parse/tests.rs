//! Unit tests mapped to parse/subtitles SC-IDs (PS-01…PS-07).

use super::{parse_subtitles, parse_text, Format, ParseError};

// --- PS-01: Parse SRT into cues ---

#[test]
fn ps01_parse_srt_into_cues() {
    let bytes = include_bytes!("fixtures/ps01_basic.srt");
    let parsed = parse_subtitles(bytes, Some("srt")).expect("PS-01 SRT should parse");
    assert_eq!(parsed.format, Format::Srt);
    assert_eq!(parsed.cues.len(), 2);
    assert_eq!(parsed.cues[0].index, 0);
    assert_eq!(parsed.cues[0].start_ms, 1_000);
    assert_eq!(parsed.cues[0].end_ms, 4_000);
    assert_eq!(parsed.cues[0].text_lines, vec!["Hello world!".to_string()]);
    assert_eq!(parsed.cues[1].index, 1);
    assert_eq!(parsed.cues[1].start_ms, 5_500);
    assert_eq!(parsed.cues[1].end_ms, 8_000);
    assert_eq!(
        parsed.cues[1].text_lines,
        vec!["Second".to_string(), "line".to_string()]
    );
}

// --- PS-02: Parse WebVTT into cues ---

#[test]
fn ps02_parse_webvtt_into_cues() {
    let bytes = include_bytes!("fixtures/ps02_basic.vtt");
    let parsed = parse_subtitles(bytes, Some("vtt")).expect("PS-02 VTT should parse");
    assert_eq!(parsed.format, Format::Vtt);
    assert_eq!(parsed.cues.len(), 2);
    assert_eq!(parsed.cues[0].start_ms, 1_000);
    assert_eq!(parsed.cues[0].end_ms, 4_000);
    assert_eq!(parsed.cues[0].text_lines, vec!["Hello WebVTT".to_string()]);
    assert_eq!(parsed.cues[1].start_ms, 5_000);
    assert_eq!(parsed.cues[1].end_ms, 7_500);
    assert_eq!(parsed.cues[1].text_lines, vec!["Second cue".to_string()]);
}

// --- PS-03: Parse ASS/SSA into cues ---

#[test]
fn ps03_parse_ass_into_cues() {
    let bytes = include_bytes!("fixtures/ps03_basic.ass");
    let parsed = parse_subtitles(bytes, Some("ass")).expect("PS-03 ASS should parse");
    assert_eq!(parsed.format, Format::Ass);
    assert_eq!(parsed.cues.len(), 2, "Comment events must be filtered out");
    assert_eq!(parsed.cues[0].start_ms, 1_000);
    assert_eq!(parsed.cues[0].end_ms, 4_000);
    assert_eq!(
        parsed.cues[0].text_lines,
        vec!["Hello".to_string(), "World".to_string()],
        "ASS plain_text().normalize() should strip overrides and expand \\N"
    );
    assert_eq!(parsed.cues[1].text_lines, vec!["Second line".to_string()]);
}

// --- PS-04: Reject unsupported / unrecognizable content ---

#[test]
fn ps04_reject_unsupported_content() {
    let garbage = b"this is not a subtitle file\njust random prose\n";
    let err = parse_subtitles(garbage, None).expect_err("PS-04 should fail");
    assert_eq!(err, ParseError::UnsupportedFormat);
}

#[test]
fn ps04_reject_unknown_hint_without_sniff() {
    let err = parse_subtitles(b"hello", Some("xyz")).expect_err("PS-04 unknown");
    assert_eq!(err, ParseError::UnsupportedFormat);
}

// --- PS-05: Reject non-UTF-8 under encoding policy ---

#[test]
fn ps05_reject_non_utf8_encoding() {
    // Invalid UTF-8 continuation bytes (raw invalid bytes, not lossy-decoded).
    let raw = b"1\n00:00:01,000 --> 00:00:02,000\n\xff\xfe bad\n";
    let err = parse_subtitles(raw, Some("srt")).expect_err("PS-05 encoding");
    assert_eq!(err, ParseError::Encoding);
}

#[test]
fn ps05_accept_utf8_bom() {
    let mut bytes = vec![0xEF, 0xBB, 0xBF];
    bytes.extend_from_slice(include_bytes!("fixtures/ps01_basic.srt"));
    let parsed = parse_subtitles(&bytes, Some("srt")).expect("PS-05 BOM OK");
    assert!(!parsed.cues.is_empty());
}

// --- PS-06: Reject empty cue list ---

#[test]
fn ps06_reject_empty_cue_list() {
    let bytes = include_bytes!("fixtures/ps06_empty.vtt");
    let err = parse_subtitles(bytes, Some("vtt")).expect_err("PS-06 empty");
    assert_eq!(err, ParseError::Empty);
}

#[test]
fn ps06_reject_empty_bytes_as_unsupported_or_empty() {
    // Completely empty: no sniff → UnsupportedFormat (not a successful empty list).
    let err = parse_subtitles(b"", None).expect_err("PS-06 empty bytes");
    assert!(
        matches!(err, ParseError::UnsupportedFormat | ParseError::Empty),
        "empty must not succeed: {err:?}"
    );
}

// --- PS-07: Lossy tolerates recoverable cue defects ---

#[test]
fn ps07_lossy_srt_skips_broken_block() {
    let bytes = include_bytes!("fixtures/ps07_lossy.srt");
    let parsed = parse_subtitles(bytes, Some("srt")).expect("PS-07 SRT lossy");
    assert_eq!(parsed.cues.len(), 2);
    assert_eq!(parsed.cues[0].text_lines, vec!["Good first cue".to_string()]);
    assert_eq!(parsed.cues[1].text_lines, vec!["Good third cue".to_string()]);
    assert_eq!(parsed.cues[0].start_ms, 1_000);
    assert_eq!(parsed.cues[1].start_ms, 5_000);
}

#[test]
fn ps07_lossy_vtt_recovers_malformed_timing() {
    let bytes = include_bytes!("fixtures/ps07_lossy.vtt");
    let parsed = parse_subtitles(bytes, Some("vtt")).expect("PS-07 VTT recovery");
    assert!(
        parsed.cues.len() >= 2,
        "valid cues around broken timing must remain: got {:?}",
        parsed.cues
    );
    assert_eq!(parsed.cues[0].text_lines, vec!["Valid first".to_string()]);
    let last = parsed.cues.last().unwrap();
    assert_eq!(last.text_lines, vec!["Valid second".to_string()]);
    assert_eq!(last.start_ms, 5_000);
}

#[test]
fn ps07_hint_srt_when_content_ambiguous_but_hinted() {
    // Minimal SRT-like with hint only path coverage via parse_text.
    let text = "1\n00:00:00,000 --> 00:00:01,000\nHi\n";
    let parsed = parse_text(text, Some("srt")).expect("hinted SRT");
    assert_eq!(parsed.format, Format::Srt);
    assert_eq!(parsed.cues.len(), 1);
}
