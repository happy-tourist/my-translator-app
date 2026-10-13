/**
 * Main-thread bridge for Dart `dart:js_interop` (design D1 / D4.1).
 * Classic script (not module) so it runs before Flutter bootstrap and defines
 * `globalThis.OfflineTranslate` early. Spawns module worker `translate_worker.js`.
 *
 * OfflineTranslate.translate(text, sourceLang, targetLang) → Promise<
 *   { ok: true, primaryGloss: string } |
 *   { ok: false, kind: string }
 * >
 */
(function (global) {
  'use strict';

  var ERROR_INTERNAL = 'internal';
  var ERROR_UNAVAILABLE = 'engineUnavailable';

  var worker = null;
  var nextId = 1;
  var pending = new Map();

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
    };
    return worker;
  }

  function translate(text, sourceLang, targetLang) {
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
        w.postMessage({
          id: id,
          op: 'translate',
          text: text || '',
          sourceLang: sourceLang || 'en',
          targetLang: targetLang || 'ru',
        });
      } catch (err) {
        pending.delete(id);
        console.error('[OfflineTranslate] postMessage failed', err);
        resolve({ ok: false, kind: ERROR_INTERNAL });
      }
    });
  }

  global.OfflineTranslate = Object.freeze({
    translate: translate,
  });
})(typeof globalThis !== 'undefined' ? globalThis : window);
