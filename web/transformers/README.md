# Vendored `@huggingface/transformers` (Web offline translate)

| Item | Value |
|------|--------|
| Package | `@huggingface/transformers` |
| Version | **3.8.1** (see `VERSION`) |
| ORT Web | `onnxruntime-web` `1.22.0-dev.20250409-89f8206ba4` (bundled with transformers 3.8.1) |

Files:

- `transformers.min.js` — browser ESM bundle from the npm package `dist/`
- `ort-wasm-simd-threaded.jsep.mjs` / `.wasm` — ONNX Runtime Web WASM bits
- `ort.bundle.min.mjs` — ORT bundle referenced by the transformers webpack map

Do **not** bump without re-testing `web/translate_worker.js` against local OPUS-MT uint8 assets (`dtype: 'uint8'`).

Model weights stay under Flutter assets (`assets/models/opus-mt-en-ru/`), not here.
