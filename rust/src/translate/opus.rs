//! Native OPUS-MT EN→RU ONNX engine (ort + tokenizers). Not linked on wasm32.

use std::collections::HashMap;
use std::path::Path;
use std::sync::{Mutex, OnceLock};

use ndarray::{Array2, Array3, Axis};
use ort::environment::Environment;
use ort::session::Session;
use ort::value::TensorRef;
use tokenizers::Tokenizer;

use super::error::TranslateError;
use super::types::{NamedAssetBytes, GlossResult, REQUIRED_ASSET_NAMES};
use super::OfflineTranslator;

const DECODER_START: i64 = 62_517;
const EOS: i64 = 0;
const PAD: i64 = 62_517;
const MAX_NEW_TOKENS: usize = 32;

/// ORT allows only one [`Environment`] per process; keep it for the crate lifetime.
fn ort_environment() -> Result<&'static Environment, TranslateError> {
    static ENV: OnceLock<Environment> = OnceLock::new();
    if let Some(env) = ENV.get() {
        return Ok(env);
    }
    let env = ort::init()
        .with_name("opus-mt-en-ru")
        .build()
        .map_err(|_| TranslateError::EngineUnavailable)?;
    let _ = ENV.set(env);
    ENV.get().ok_or(TranslateError::EngineUnavailable)
}

/// Live Marian encoder/decoder sessions + tokenizer.
pub struct OpusMtEnRu {
    tokenizer: Tokenizer,
    encoder: Mutex<Session>,
    decoder: Mutex<Session>,
}

impl OpusMtEnRu {
    /// Build from named asset bytes (Flutter AssetBundle → FRB).
    pub fn from_assets(assets: Vec<NamedAssetBytes>) -> Result<Self, TranslateError> {
        let mut map = collect_assets(assets)?;
        let tokenizer_bytes = map
            .remove("tokenizer.json")
            .ok_or(TranslateError::EngineUnavailable)?;
        let encoder_bytes = map
            .remove("encoder_model_uint8.onnx")
            .ok_or(TranslateError::EngineUnavailable)?;
        let decoder_bytes = map
            .remove("decoder_model_uint8.onnx")
            .ok_or(TranslateError::EngineUnavailable)?;

        let tokenizer = Tokenizer::from_bytes(tokenizer_bytes.as_slice())
            .map_err(|_| TranslateError::EngineUnavailable)?;

        let env = ort_environment()?;

        let encoder = Session::builder(env)
            .map_err(|_| TranslateError::EngineUnavailable)?
            .commit_from_memory(encoder_bytes.as_slice())
            .map_err(|_| TranslateError::EngineUnavailable)?;

        let decoder = Session::builder(env)
            .map_err(|_| TranslateError::EngineUnavailable)?
            .commit_from_memory(decoder_bytes.as_slice())
            .map_err(|_| TranslateError::EngineUnavailable)?;

        // `commit_from_memory` copies into ORT; local Vecs can drop.
        drop(tokenizer_bytes);
        drop(encoder_bytes);
        drop(decoder_bytes);

        Ok(Self {
            tokenizer,
            encoder: Mutex::new(encoder),
            decoder: Mutex::new(decoder),
        })
    }

    fn greedy_translate(&self, text: &str) -> Result<String, TranslateError> {
        let encoding = self
            .tokenizer
            .encode(text, true)
            .map_err(|_| TranslateError::InferenceFailed)?;
        let mut ids: Vec<i64> = encoding.get_ids().iter().map(|&id| id as i64).collect();
        if ids.last().copied() != Some(EOS) {
            ids.push(EOS);
        }
        let seq_len = ids.len();
        let input_ids = Array2::from_shape_vec((1, seq_len), ids)
            .map_err(|_| TranslateError::Internal)?;
        let attention_mask = Array2::<i64>::ones((1, seq_len));

        let input_ids_tensor = TensorRef::from_array_view(input_ids.view())
            .map_err(|_| TranslateError::InferenceFailed)?;
        let attention_tensor = TensorRef::from_array_view(attention_mask.view())
            .map_err(|_| TranslateError::InferenceFailed)?;

        let (enc_len, hidden) = {
            let mut encoder = self
                .encoder
                .lock()
                .map_err(|_| TranslateError::Internal)?;
            let encoder_outputs = encoder
                .run(ort::inputs! {
                    "input_ids" => input_ids_tensor,
                    "attention_mask" => attention_tensor,
                })
                .map_err(|_| TranslateError::InferenceFailed)?;
            let encoder_hs = encoder_outputs["last_hidden_state"]
                .try_extract_array::<f32>()
                .map_err(|_| TranslateError::InferenceFailed)?
                .into_owned();
            let enc_len = encoder_hs.shape()[1];
            let hidden = encoder_hs
                .into_dimensionality::<ndarray::Ix3>()
                .map_err(|_| TranslateError::InferenceFailed)?;
            (enc_len, hidden)
        };

        let mut decoder = self
            .decoder
            .lock()
            .map_err(|_| TranslateError::Internal)?;
        let mut decoder_ids: Vec<i64> = vec![DECODER_START];
        for _ in 0..MAX_NEW_TOKENS {
            let dec_len = decoder_ids.len();
            let dec_input = Array2::from_shape_vec((1, dec_len), decoder_ids.clone())
                .map_err(|_| TranslateError::Internal)?;
            let enc_mask = Array2::<i64>::ones((1, enc_len));

            let enc_mask_tensor = TensorRef::from_array_view(enc_mask.view())
                .map_err(|_| TranslateError::InferenceFailed)?;
            let dec_input_tensor = TensorRef::from_array_view(dec_input.view())
                .map_err(|_| TranslateError::InferenceFailed)?;
            let hidden_tensor = TensorRef::from_array_view(hidden.view())
                .map_err(|_| TranslateError::InferenceFailed)?;

            let decoder_outputs = decoder
                .run(ort::inputs! {
                    "encoder_attention_mask" => enc_mask_tensor,
                    "input_ids" => dec_input_tensor,
                    "encoder_hidden_states" => hidden_tensor,
                })
                .map_err(|_| TranslateError::InferenceFailed)?;

            let logits = decoder_outputs["logits"]
                .try_extract_array::<f32>()
                .map_err(|_| TranslateError::InferenceFailed)?
                .into_owned();
            let logits3: Array3<f32> = logits
                .into_dimensionality::<ndarray::Ix3>()
                .map_err(|_| TranslateError::InferenceFailed)?;
            let last = logits3.index_axis(Axis(1), dec_len - 1);
            let mut best_id = 0i64;
            let mut best_score = f32::NEG_INFINITY;
            for (vocab_id, score) in last.iter().enumerate() {
                if vocab_id as i64 == PAD {
                    continue;
                }
                if *score > best_score {
                    best_score = *score;
                    best_id = vocab_id as i64;
                }
            }
            if best_id == EOS {
                break;
            }
            decoder_ids.push(best_id);
        }

        let gen: Vec<u32> = decoder_ids
            .into_iter()
            .skip(1)
            .map(|id| id as u32)
            .collect();
        let gloss = self
            .tokenizer
            .decode(&gen, true)
            .map_err(|_| TranslateError::InferenceFailed)?;
        let gloss = gloss.trim().to_owned();
        if gloss.is_empty() {
            return Err(TranslateError::InferenceFailed);
        }
        Ok(gloss)
    }
}

impl OfflineTranslator for OpusMtEnRu {
    fn translate(
        &self,
        text: &str,
        _source_lang: &str,
        _target_lang: &str,
    ) -> Result<GlossResult, TranslateError> {
        let primary_gloss = self.greedy_translate(text)?;
        Ok(GlossResult { primary_gloss })
    }
}

fn collect_assets(
    assets: Vec<NamedAssetBytes>,
) -> Result<HashMap<String, Vec<u8>>, TranslateError> {
    let mut map = HashMap::new();
    for asset in assets {
        if asset.bytes.is_empty() {
            return Err(TranslateError::EngineUnavailable);
        }
        let key = basename(&asset.name).to_owned();
        map.insert(key, asset.bytes);
    }
    for required in REQUIRED_ASSET_NAMES {
        if !map.contains_key(*required) {
            return Err(TranslateError::EngineUnavailable);
        }
    }
    Ok(map)
}

fn basename(name: &str) -> &str {
    Path::new(name)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(name)
}
