//! Subtitle parse core: detect, decode UTF-8, map fasrt → owned cues.
//!
//! Fasrt entrypoints (design D1):
//! - SRT: [`fasrt::srt::Parser::lossy`]
//! - WebVTT: [`fasrt::vtt::Parser::new`] (built-in recovery; no separate lossy)
//! - ASS/SSA: [`fasrt::ass::Parser::lossy`] + `EventKind::Dialogue` only
//!
//! Map: `Timestamp::to_duration()` → `as_millis() as u64`; ASS text via
//! `Event::plain_text().normalize()`.

mod ass;
mod cue;
mod detect;
mod error;
mod srt;
mod vtt;

pub use cue::{Cue, ParsedSubtitles};
pub use error::ParseError;

/// Detected / requested subtitle format.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    Srt,
    Vtt,
    Ass,
}

impl Format {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Srt => "srt",
            Self::Vtt => "vtt",
            Self::Ass => "ass",
        }
    }
}

/// Parse subtitle bytes: strict UTF-8 (+ BOM strip), detect format, lossy map.
pub fn parse_subtitles(
    bytes: &[u8],
    format_hint: Option<&str>,
) -> Result<ParsedSubtitles, ParseError> {
    let text = decode_utf8(bytes)?;
    parse_text(&text, format_hint)
}

/// Parse already-decoded subtitle text (BOM already stripped by caller or here).
pub fn parse_text(text: &str, format_hint: Option<&str>) -> Result<ParsedSubtitles, ParseError> {
    let text = strip_bom(text);
    let format = detect::detect_format(text, format_hint)?;
    let cues = match format {
        Format::Srt => srt::parse_srt(text)?,
        Format::Vtt => vtt::parse_vtt(text)?,
        Format::Ass => ass::parse_ass(text)?,
    };
    Ok(ParsedSubtitles { format, cues })
}

fn decode_utf8(bytes: &[u8]) -> Result<String, ParseError> {
    let bytes = strip_bom_bytes(bytes);
    std::str::from_utf8(bytes)
        .map(|s| s.to_owned())
        .map_err(|_| ParseError::Encoding)
}

fn strip_bom_bytes(bytes: &[u8]) -> &[u8] {
    if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        &bytes[3..]
    } else {
        bytes
    }
}

fn strip_bom(text: &str) -> &str {
    text.strip_prefix('\u{feff}').unwrap_or(text)
}

#[cfg(test)]
mod tests;
