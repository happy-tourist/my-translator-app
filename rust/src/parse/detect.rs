//! Format detection: extension hint + content sniff (design D1).

use super::{Format, ParseError};

/// Normalize a user/extension hint into a [`Format`], if recognized.
pub fn format_from_hint(hint: &str) -> Option<Format> {
    match hint.trim().trim_start_matches('.').to_ascii_lowercase().as_str() {
        "srt" => Some(Format::Srt),
        "vtt" | "webvtt" => Some(Format::Vtt),
        "ass" | "ssa" => Some(Format::Ass),
        _ => None,
    }
}

/// Sniff subtitle format from decoded text (after BOM strip).
///
/// Prefers clear signatures (`WEBVTT`, ASS section markers / `Dialogue:`) over
/// SRT-like `-->` timing blocks.
pub fn sniff_format(text: &str) -> Option<Format> {
    let trimmed = text.trim_start();
    if trimmed.is_empty() {
        return None;
    }

    let head: String = trimmed.chars().take(512).collect();
    let head_upper = head.to_ascii_uppercase();

    if head_upper.starts_with("WEBVTT") {
        return Some(Format::Vtt);
    }

    if head_upper.contains("[SCRIPT INFO]")
        || head_upper.contains("[V4+ STYLES]")
        || head_upper.contains("[V4 STYLES]")
        || head_upper.contains("[EVENTS]")
        || head.lines().any(|l| {
            let t = l.trim_start();
            t.starts_with("Dialogue:") || t.starts_with("Comment:")
        })
    {
        return Some(Format::Ass);
    }

    if looks_like_srt(trimmed) {
        return Some(Format::Srt);
    }

    None
}

/// Resolve format from optional hint and content. Prefer sniff when it disagrees
/// with the hint; fall back to hint when sniff is inconclusive.
pub fn detect_format(text: &str, hint: Option<&str>) -> Result<Format, ParseError> {
    let sniffed = sniff_format(text);
    let hinted = hint.and_then(format_from_hint);

    match (sniffed, hinted) {
        (Some(s), _) => Ok(s),
        (None, Some(h)) => Ok(h),
        (None, None) => Err(ParseError::UnsupportedFormat),
    }
}

fn looks_like_srt(text: &str) -> bool {
    // SRT hallmark: `HH:MM:SS,mmm --> HH:MM:SS,mmm` (comma decimal).
    for line in text.lines().take(64) {
        let line = line.trim();
        if let Some(arrow) = line.find("-->") {
            let start = line[..arrow].trim();
            let end = line[arrow + 3..].trim();
            if is_srt_timestamp(start) && is_srt_timestamp(end.split_whitespace().next().unwrap_or(""))
            {
                return true;
            }
        }
    }
    false
}

fn is_srt_timestamp(s: &str) -> bool {
    // Minimal: digits and colons, then comma, then digits.
    let Some((hms, ms)) = s.split_once(',') else {
        return false;
    };
    if ms.len() != 3 || !ms.chars().all(|c| c.is_ascii_digit()) {
        return false;
    }
    let parts: Vec<&str> = hms.split(':').collect();
    parts.len() == 3 && parts.iter().all(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_digit()))
}
