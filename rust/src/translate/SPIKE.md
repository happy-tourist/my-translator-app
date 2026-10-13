# Spike: native ORT OPUS-MT EN→RU (task 2.0)

**Status:** AC met (a)(b)(c) — 2026-10-13. Promoted into product `translate/` + `api/translate` (task block 3).

## (a) Asset basenames (native + Web)

Required for `init_offline_translate` / Flutter assets (same names both runtimes):

| Basename | Path under `assets/models/opus-mt-en-ru/` |
|----------|-------------------------------------------|
| `tokenizer.json` | `tokenizer.json` |
| `encoder_model_uint8.onnx` | `onnx/encoder_model_uint8.onnx` |
| `decoder_model_uint8.onnx` | `onnx/decoder_model_uint8.onnx` |

Source: HuggingFace `onnx-community/opus-mt-en-ru` (CC-BY 4.0).

**Tokenizer note:** upstream `tokenizer.json` has `"normalizer": {"type":"Precompiled","precompiled_charsmap":null}`, which panics in Rust `tokenizers`. App copy sets `"normalizer": null` (no-op; Marian Metaspace still works). Transformers.js tolerates either.

Optional companion JSON kept next to assets (not required for ORT loop): `config.json`, `generation_config.json`, `tokenizer_config.json`.

Special IDs (from `generation_config.json`): `decoder_start_token_id` / `pad_token_id` = **62517**, `eos_token_id` = **0**.

## (b) How to run spike

From `my_translator_app/rust`:

```bash
cargo test spike_opus_mt_en_ru_hello_offline -- --nocapture
```

Expect printed non-empty RU glosses, e.g. `hello` → `Привет.`, `good morning` → `Доброе утро`.

## (c) Cargo link notes (native only)

In `rust/Cargo.toml` — **not** for `wasm32`:

```toml
[target.'cfg(not(target_arch = "wasm32"))'.dependencies]
ort = "2.0.0-rc.14"          # default features: ndarray + download-binaries
tokenizers = { version = "0.21", default-features = false, features = ["fancy-regex"] }
ndarray = "0.17"             # direct dep for Array2/Array3 in Marian loop
```

- **Windows MSVC:** do not enable tokenizers `onig` / `esaxx_fast` — their static CRT (`/MT`) conflicts with `ort` (`/MD`).
- Create sessions via `let env = ort::init().build()?; Session::builder(&env)?.commit_from_file(...)` (ort 2.0.0-rc.14 requires `&Environment`).
- First `cargo test` / build downloads ONNX Runtime native dylibs via `ort` `download-binaries`.
- Marian loop: encoder once → greedy decoder steps with growing `input_ids` (this `decoder_model_uint8` has no past-KV inputs; KV cache = later optimization via `decoder_with_past_*` / merged).
- Do **not** link `ort` into FRB wasm32 (stubs in later task 3.x).

## Loop sketch

1. `Tokenizer::encode(text)` → `input_ids` + `attention_mask` (post-processor appends `</s>` / EOS=0).
2. Encoder → `last_hidden_state` `[1, enc_len, 512]`.
3. Decoder start with `[62517]`; each step run decoder with full decoder `input_ids` + encoder HS/mask; argmax last logits (mask PAD=62517); stop on EOS=0.
4. `Tokenizer::decode` generated ids (skip start token).
