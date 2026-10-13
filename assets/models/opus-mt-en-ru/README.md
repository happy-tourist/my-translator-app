# OPUS-MT en→ru ONNX assets

Offline translate model from HuggingFace [`onnx-community/opus-mt-en-ru`](https://huggingface.co/onnx-community/opus-mt-en-ru) (CC-BY 4.0; Helsinki-NLP OPUS-MT).

Native (Rust `ort`) and Web (Transformers.js) share the basenames below. Web also needs the merged decoder for Transformers.js Seq2Seq sessions.

## Required basenames

| Basename | Relative path | Role | Used by |
|----------|---------------|------|---------|
| `tokenizer.json` | `tokenizer.json` | Encode/decode | Native + Web |
| `encoder_model_uint8.onnx` | `onnx/encoder_model_uint8.onnx` | Marian encoder | Native + Web |
| `decoder_model_uint8.onnx` | `onnx/decoder_model_uint8.onnx` | Marian decoder (full-seq; no past-KV) | Native |
| `decoder_model_merged_uint8.onnx` | `onnx/decoder_model_merged_uint8.onnx` | Marian decoder (merged + past-KV) | Web Transformers.js |

Also present for Transformers.js local load: `config.json`, `generation_config.json`, `tokenizer_config.json`.

Special IDs: decoder start / pad = `62517`, EOS = `0`.

**Rust tokenizer patch:** upstream HF `tokenizer.json` has `normalizer.precompiled_charsmap: null`, which panics in Rust `tokenizers`. This tree’s `tokenizer.json` uses `"normalizer": null` instead (same encode/decode behavior for this model).

## Cargo (native)

See `my_translator_app/rust/src/translate/SPIKE.md`:

- `ort = "2.0.0-rc.14"`
- `tokenizers = { version = "0.21", default-features = false, features = ["fancy-regex"] }` (avoid `onig`/`esaxx_fast` CRT clash with ort on Windows MSVC)
- `ndarray = "0.17"`
- under `[target.'cfg(not(target_arch = "wasm32"))'.dependencies]`

## Web (Transformers.js)

- Pinned library: `@huggingface/transformers@3.8.1` vendored under `web/transformers/` (see that README).
- Worker: `web/translate_worker.js`; Dart bridge: `web/translate_bridge.js` + `lib/data/translate/offline_translate_web.dart`.
- Pipeline loads model id `opus-mt-en-ru` from Flutter assets URL `/assets/assets/models/` with `dtype: 'uint8'` (no HF Hub download).

## Spike verify

```bash
cd rust && cargo test spike_opus_mt_en_ru_hello_offline -- --nocapture
```

`onnx/` is gitignored (decoder weights ~178 MB each exceed GitHub’s 100 MB limit). Keep weights local; download from the HF repo above into `onnx/` after clone. Small configs + `tokenizer.json` stay in git.

Do not commit these ~230MB+ binaries into `my_translator_meta` either.
