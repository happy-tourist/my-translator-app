/**
 * Offline OPUS-MT en→ru worker (Transformers.js 3.8.1).
 * Loads local Flutter asset files — no Hugging Face Hub download at runtime.
 *
 * Message protocol (request / response share `id`):
 *   { id, op: 'translate', text, sourceLang, targetLang }
 *   → { id, ok: true, primaryGloss }
 *   → { id, ok: false, kind: 'emptyQuery'|'unsupportedLanguagePair'|
 *                        'engineUnavailable'|'inferenceFailed'|'internal' }
 */
import { pipeline, env } from './transformers/transformers.min.js';

const ERROR = Object.freeze({
  emptyQuery: 'emptyQuery',
  unsupportedLanguagePair: 'unsupportedLanguagePair',
  engineUnavailable: 'engineUnavailable',
  inferenceFailed: 'inferenceFailed',
  internal: 'internal',
});

/** Flutter web serves pubspec assets under /assets/<asset-key>. */
const MODEL_ID = 'opus-mt-en-ru';
const localModelPath = new URL('assets/assets/models/', self.location.href).href;

env.allowLocalModels = true;
env.allowRemoteModels = false;
env.useBrowserCache = false;
env.localModelPath = localModelPath;

// Point ORT WASM at vendored bits next to this worker.
if (env.backends?.onnx?.wasm) {
  env.backends.onnx.wasm.wasmPaths = new URL(
    'transformers/',
    self.location.href,
  ).href;
}

let translatorPromise = null;

function normalizeLang(code) {
  return String(code ?? '')
    .trim()
    .toLowerCase();
}

function classifyInitError(err) {
  const msg = String(err?.message ?? err ?? '');
  if (/fetch|404|not found|failed to fetch|network/i.test(msg)) {
    return ERROR.engineUnavailable;
  }
  return ERROR.engineUnavailable;
}

async function getTranslator() {
  if (!translatorPromise) {
    translatorPromise = (async () => {
      try {
        // dtype uint8 → encoder/decoder *_uint8.onnx (same basenames as native).
        // Seq2Seq needs decoder_model_merged_uint8.onnx (Web-only extra asset).
        return await pipeline('translation', MODEL_ID, {
          dtype: 'uint8',
          device: 'wasm',
          // Avoid ORT QDQ fusion bugs on some Marian uint8 graphs.
          session_options: { graphOptimizationLevel: 'basic' },
        });
      } catch (err) {
        translatorPromise = null;
        const kind = classifyInitError(err);
        const e = new Error(String(err?.message ?? err));
        e.kind = kind;
        throw e;
      }
    })();
  }
  return translatorPromise;
}

function reply(id, payload) {
  self.postMessage({ id, ...payload });
}

self.onmessage = async (event) => {
  const data = event.data ?? {};
  const id = data.id;
  const op = data.op;

  if (op !== 'translate') {
    reply(id, { ok: false, kind: ERROR.internal });
    return;
  }

  const text = data.text ?? '';
  const sourceLang = normalizeLang(data.sourceLang ?? 'en');
  const targetLang = normalizeLang(data.targetLang ?? 'ru');

  if (!String(text).trim()) {
    reply(id, { ok: false, kind: ERROR.emptyQuery });
    return;
  }

  if (sourceLang !== 'en' || targetLang !== 'ru') {
    reply(id, { ok: false, kind: ERROR.unsupportedLanguagePair });
    return;
  }

  let translator;
  try {
    translator = await getTranslator();
  } catch (err) {
    reply(id, {
      ok: false,
      kind: err?.kind ?? ERROR.engineUnavailable,
    });
    return;
  }

  try {
    const raw = await translator(text);
    const gloss =
      (Array.isArray(raw) ? raw[0]?.translation_text : raw?.translation_text) ??
      '';
    const primaryGloss = String(gloss).trim();
    if (!primaryGloss) {
      reply(id, { ok: false, kind: ERROR.inferenceFailed });
      return;
    }
    reply(id, { ok: true, primaryGloss });
  } catch (err) {
    console.error('[translate_worker] inference failed', err);
    reply(id, { ok: false, kind: ERROR.inferenceFailed });
  }
};
