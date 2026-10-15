//! Plain-text strip for EPUB XHTML (design D9) — wasm-safe, no C HTML parser.

/// Split XHTML/HTML body into non-empty plain paragraphs.
///
/// Block boundaries: `p`, `div`, `h1`–`h6`, `li`, `blockquote`, `br`.
/// Tags are removed; whitespace collapsed; empty segments dropped.
/// `script` / `style` / `img` content is omitted.
pub fn strip_xhtml_to_paragraphs(xhtml: &str) -> Vec<String> {
    let body = extract_body(xhtml);
    let without_skipped = remove_skipped_elements(&body);
    let with_breaks = insert_block_breaks(&without_skipped);
    let plain = strip_remaining_tags(&with_breaks);
    split_paragraphs(&plain)
}

fn extract_body(xhtml: &str) -> String {
    let lower = xhtml.to_ascii_lowercase();
    if let Some(start) = lower.find("<body") {
        let after = &xhtml[start..];
        if let Some(gt) = after.find('>') {
            let content_start = start + gt + 1;
            let rest_lower = xhtml[content_start..].to_ascii_lowercase();
            if let Some(end) = rest_lower.find("</body>") {
                return xhtml[content_start..content_start + end].to_owned();
            }
            return xhtml[content_start..].to_owned();
        }
    }
    xhtml.to_owned()
}

fn remove_skipped_elements(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut rest = input;
    while !rest.is_empty() {
        if let Some(rel) = rest.find('<') {
            out.push_str(&rest[..rel]);
            let tag_slice = &rest[rel..];
            if let Some((tag_inner, consumed)) = parse_tag(tag_slice) {
                let name = tag_name(&tag_inner);
                if is_skip_element(name) {
                    let closing = tag_inner.starts_with('/');
                    let self_closing = tag_inner.ends_with('/') || is_void_like(name);
                    rest = &tag_slice[consumed..];
                    if !closing && !self_closing {
                        let close = format!("</{name}");
                        let lower = rest.to_ascii_lowercase();
                        if let Some(cend) = lower.find(&close) {
                            let after = &rest[cend + close.len()..];
                            if let Some(gt) = after.find('>') {
                                rest = &after[gt + 1..];
                            } else {
                                rest = "";
                            }
                        } else {
                            // Unclosed skip element — drop remainder.
                            rest = "";
                        }
                    }
                    continue;
                }
                // Keep non-skip tags for later block/tag processing.
                out.push_str(&tag_slice[..consumed]);
                rest = &tag_slice[consumed..];
            } else {
                out.push('<');
                rest = &tag_slice[1..];
            }
        } else {
            out.push_str(rest);
            break;
        }
    }
    out
}

fn insert_block_breaks(input: &str) -> String {
    let mut out = String::with_capacity(input.len() + 32);
    let mut rest = input;
    while !rest.is_empty() {
        if let Some(rel) = rest.find('<') {
            out.push_str(&rest[..rel]);
            let tag_slice = &rest[rel..];
            if let Some((tag_inner, consumed)) = parse_tag(tag_slice) {
                let name = tag_name(&tag_inner);
                let closing = tag_inner.starts_with('/');
                if is_block_boundary(name) {
                    out.push('\n');
                    if name.eq_ignore_ascii_case("br") || closing {
                        out.push('\n');
                    }
                }
                // Drop tag markup (block and inline).
                rest = &tag_slice[consumed..];
            } else {
                out.push('<');
                rest = &tag_slice[1..];
            }
        } else {
            out.push_str(rest);
            break;
        }
    }
    out
}

fn strip_remaining_tags(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut rest = input;
    while !rest.is_empty() {
        if let Some(rel) = rest.find('<') {
            decode_text_chunk(&rest[..rel], &mut out);
            let tag_slice = &rest[rel..];
            if let Some((_, consumed)) = parse_tag(tag_slice) {
                rest = &tag_slice[consumed..];
            } else {
                out.push('<');
                rest = &tag_slice[1..];
            }
        } else {
            decode_text_chunk(rest, &mut out);
            break;
        }
    }
    out
}

fn decode_text_chunk(s: &str, out: &mut String) {
    let mut rest = s;
    while !rest.is_empty() {
        if let Some(rel) = rest.find('&') {
            out.push_str(&rest[..rel]);
            let ent = &rest[rel..];
            if let Some((ch, n)) = decode_entity(ent) {
                out.push(ch);
                rest = &ent[n..];
            } else {
                out.push('&');
                rest = &ent[1..];
            }
        } else {
            out.push_str(rest);
            break;
        }
    }
}

fn split_paragraphs(plain: &str) -> Vec<String> {
    plain
        .split('\n')
        .map(collapse_ws)
        .filter(|s| !s.is_empty())
        .collect()
}

fn collapse_ws(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut prev_space = false;
    for ch in s.chars() {
        if ch.is_whitespace() {
            if !prev_space && !out.is_empty() {
                out.push(' ');
                prev_space = true;
            }
        } else {
            out.push(ch);
            prev_space = false;
        }
    }
    out.trim().to_owned()
}

/// Returns `(inner without < >, byte length of full `<...>` including brackets)`.
fn parse_tag(tag_slice: &str) -> Option<(String, usize)> {
    if !tag_slice.starts_with('<') {
        return None;
    }
    let bytes = tag_slice.as_bytes();
    let mut i = 1;
    if i < bytes.len() && (bytes[i] == b'!' || bytes[i] == b'?') {
        while i < bytes.len() && bytes[i] != b'>' {
            i += 1;
        }
        if i >= bytes.len() {
            return None;
        }
        return Some((String::new(), i + 1));
    }
    while i < bytes.len() && bytes[i] != b'>' {
        i += 1;
    }
    if i >= bytes.len() {
        return None;
    }
    let inner = tag_slice[1..i].trim().to_owned();
    Some((inner, i + 1))
}

fn tag_name(tag: &str) -> &str {
    let t = tag.trim().trim_start_matches('/').trim_end_matches('/');
    let name = t.split_whitespace().next().unwrap_or("");
    name.rsplit(':').next().unwrap_or(name)
}

fn is_block_boundary(name: &str) -> bool {
    matches!(
        name.to_ascii_lowercase().as_str(),
        "p" | "div"
            | "h1"
            | "h2"
            | "h3"
            | "h4"
            | "h5"
            | "h6"
            | "li"
            | "blockquote"
            | "br"
            | "tr"
            | "section"
            | "article"
            | "header"
            | "footer"
            | "nav"
    )
}

fn is_skip_element(name: &str) -> bool {
    matches!(
        name.to_ascii_lowercase().as_str(),
        "script" | "style" | "img" | "svg" | "video" | "audio" | "object" | "iframe"
    )
}

fn is_void_like(name: &str) -> bool {
    matches!(
        name.to_ascii_lowercase().as_str(),
        "br" | "hr" | "img" | "meta" | "link" | "input" | "source" | "track" | "wbr"
    )
}

fn decode_entity(s: &str) -> Option<(char, usize)> {
    if s.starts_with("&amp;") {
        return Some(('&', 5));
    }
    if s.starts_with("&lt;") {
        return Some(('<', 4));
    }
    if s.starts_with("&gt;") {
        return Some(('>', 4));
    }
    if s.starts_with("&quot;") {
        return Some(('"', 6));
    }
    if s.starts_with("&apos;") {
        return Some(('\'', 6));
    }
    if s.starts_with("&nbsp;") {
        return Some((' ', 6));
    }
    if let Some(rest) = s.strip_prefix("&#x").or_else(|| s.strip_prefix("&#X")) {
        let end = rest.find(';')?;
        let code = u32::from_str_radix(&rest[..end], 16).ok()?;
        let ch = char::from_u32(code)?;
        return Some((ch, 3 + end + 1));
    }
    if let Some(rest) = s.strip_prefix("&#") {
        let end = rest.find(';')?;
        let code: u32 = rest[..end].parse().ok()?;
        let ch = char::from_u32(code)?;
        return Some((ch, 2 + end + 1));
    }
    None
}

#[cfg(test)]
mod unit_tests {
    use super::*;

    #[test]
    fn strips_tags_and_splits_blocks() {
        let xhtml = r#"<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><body>
<p>A <b>bold</b> line.</p>
<div>Div text</div>
<li>Item</li>
</body></html>"#;
        let paras = strip_xhtml_to_paragraphs(xhtml);
        assert_eq!(paras, vec!["A bold line.", "Div text", "Item"]);
        assert!(paras.iter().all(|p| !p.contains('<')));
    }

    #[test]
    fn omits_img_and_empty() {
        let xhtml = r#"<html><body><p>  </p><img src="x.png"/><p>Keep</p></body></html>"#;
        let paras = strip_xhtml_to_paragraphs(xhtml);
        assert_eq!(paras, vec!["Keep"]);
    }
}
