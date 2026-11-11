/**
 * Main-thread bridge for Dart `dart:js_interop` (design D1 / D4.1 / D2).
 * Classic script (not module) so it runs before Flutter bootstrap and defines
 * `globalThis.OfflineTranslate` early. Spawns module worker `translate_worker.js`.
 *
 * OfflineTranslate.translate(text, sourceLang, targetLang) → Promise<
 *   { ok: true, primaryGloss: string } |
 *   { ok: false, kind: string }
 * >
 * OfflineTranslate.warmup() → Promise<{ ok: true } | { ok: false, kind }>
 *   Process-wide shared Promise; worker uses one translatorPromise with translate.
 */
(function (global) {
  'use strict';

  var ERROR_INTERNAL = 'internal';
  var ERROR_UNAVAILABLE = 'engineUnavailable';

  var worker = null;
  var nextId = 1;
  var pending = new Map();
  /** Process-wide in-flight / completed warmup (design D2). */
  var warmupPromise = null;

  function workerUrl() {
    // Same directory as this script / app root (Flutter copies web/* to build/web/).
    try {
      var scripts = document.getElementsByTagName('script');
      for (var i = scripts.length - 1; i >= 0; i--) {
        var src = scripts[i].src || '';
        if (src.indexOf('translate_bridge.js') !== -1) {
          return src.replace(/translate_bridge\.js(?:\?.*)?$/, 'translate_worker.js');
        }
      }
    } catch (_) {}
    return 'translate_worker.js';
  }

  function ensureWorker() {
    if (worker) return worker;
    worker = new Worker(workerUrl(), { type: 'module' });
    worker.onmessage = function (event) {
      var data = event.data || {};
      var entry = pending.get(data.id);
      if (!entry) return;
      pending.delete(data.id);
      entry.resolve(data);
    };
    worker.onerror = function (event) {
      console.error('[OfflineTranslate] worker error', event);
      pending.forEach(function (entry) {
        entry.resolve({ ok: false, kind: ERROR_UNAVAILABLE });
      });
      pending.clear();
      worker = null;
      // Allow a later warmup after worker death.
      warmupPromise = null;
    };
    return worker;
  }

  function postOp(payload) {
    var w;
    try {
      w = ensureWorker();
    } catch (err) {
      console.error('[OfflineTranslate] failed to create worker', err);
      return Promise.resolve({ ok: false, kind: ERROR_UNAVAILABLE });
    }
    var id = nextId++;
    return new Promise(function (resolve) {
      pending.set(id, { resolve: resolve });
      try {
        w.postMessage(Object.assign({ id: id }, payload));
      } catch (err) {
        pending.delete(id);
        console.error('[OfflineTranslate] postMessage failed', err);
        resolve({ ok: false, kind: ERROR_INTERNAL });
      }
    });
  }

  /**
   * One shared warmup Future for all callers (shell + Translate race).
   * Worker also dedupes pipeline create via translatorPromise.
   */
  function warmup() {
    if (warmupPromise) return warmupPromise;
    warmupPromise = postOp({ op: 'warmup' }).then(function (result) {
      if (!result || !result.ok) {
        // Clear so a later Translate / warm-up can retry.
        warmupPromise = null;
        return result || { ok: false, kind: ERROR_UNAVAILABLE };
      }
      // Keep resolved Promise — subsequent warmup() is a no-op join.
      return result;
    });
    return warmupPromise;
  }

  function translate(text, sourceLang, targetLang) {
    // Join in-flight warmup first so warmup∥translate share one pipeline load
    // message path; translate still posts its own op (gloss) after.
    var ready = warmupPromise || warmup();
    return ready.then(function (warmResult) {
      // If warmup failed and cleared, still attempt translate — worker may
      // recover / report the same engine kind on getTranslator.
      if (warmResult && warmResult.ok === false && !warmupPromise) {
        // Fall through to translate op (lazy path / retry).
      }
      return postOp({
        op: 'translate',
        text: text || '',
        sourceLang: sourceLang || 'en',
        targetLang: targetLang || 'ru',
      });
    });
  }

  global.OfflineTranslate = Object.freeze({
    translate: translate,
    warmup: warmup,
  });
})(typeof globalThis !== 'undefined' ? globalThis : window);
