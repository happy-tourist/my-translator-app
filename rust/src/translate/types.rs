//! Domain offline-translate value types (names distinct from FRB DTOs in `api/`).

/// Successful gloss for one word or phrase query.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct GlossResult {
    /// Non-empty Russian gloss when `Ok`.
    pub primary_gloss: String,
}

/// Named model asset bytes handed in from FRB / tests (no OS paths).
#[derive(Debug, Clone)]
#[cfg_attr(target_arch = "wasm32", allow(dead_code))]
pub(crate) struct NamedAssetBytes {
    /// Basename, e.g. `tokenizer.json` or `encoder_model_uint8.onnx`.
    pub name: String,
    pub bytes: Vec<u8>,
}

/// Required basenames for OPUS-MT EN→RU (see `SPIKE.md` / assets README).
#[cfg_attr(target_arch = "wasm32", allow(dead_code))]
pub(crate) const REQUIRED_ASSET_NAMES: &[&str] = &[
    "tokenizer.json",
    "encoder_model_uint8.onnx",
    "decoder_model_uint8.onnx",
];
