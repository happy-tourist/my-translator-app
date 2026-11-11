import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'offline_translate.dart';
import 'offline_translate_web_ensure.dart' as ensure;

/// Re-export ensure test hooks / API used by platform facade and tests.
export 'offline_translate_web_ensure.dart'
    show
        debugOfflineTranslateWebWarmupStarts,
        debugResetOfflineTranslateWebEnsure,
        debugWebRunWarmupOverride;

/// Web offline translate via `globalThis.OfflineTranslate` (Transformers.js worker).
///
/// Does **not** call FRB `init_offline_translate` / `translate_text`.
OfflineTranslateFn createOfflineTranslate() => createWebOfflineTranslate();

/// Explicit Web factory (same as [createOfflineTranslate]).
OfflineTranslateFn createWebOfflineTranslate() {
  return ({
    required String text,
    String sourceLang = 'en',
    String targetLang = 'ru',
  }) async {
    try {
      await ensureOfflineTranslateReady();
    } catch (_) {
      // Bridge / warmup failure → same UX as engine down unless translate maps.
    }

    final bridge = offlineTranslateBridge;
    if (bridge == null) {
      return const OfflineTranslateErr(
        kind: OfflineTranslateErrorKind.engineUnavailable,
      );
    }

    try {
      final jsResult = await bridge
          .translate(text, sourceLang, targetLang)
          .toDart;
      return _mapJsResult(jsResult);
    } catch (e, st) {
      assert(() {
        debugPrint('offline translate web unexpected: $e\n$st');
        return true;
      }());
      return const OfflineTranslateErr(
        kind: OfflineTranslateErrorKind.internal,
      );
    }
  };
}

/// Ensures Web Transformers.js pipeline is ready (shared process-wide Future).
Future<void> ensureOfflineTranslateReady() =>
    ensure.ensureOfflineTranslateReady(runWarmup: _runWarmup);

/// Quiet background warm-up (design D2 / D6) — same ensure as Translate.
Future<void> warmUpOfflineTranslate() =>
    ensure.warmUpOfflineTranslate(runWarmup: _runWarmup);

Future<void> _runWarmup() async {
  final bridge = offlineTranslateBridge;
  if (bridge == null) {
    throw StateError('OfflineTranslate bridge unavailable');
  }
  final jsResult = await bridge.warmup().toDart;
  if (jsResult == null) {
    throw StateError('OfflineTranslate warmup returned null');
  }
  final result = jsResult as OfflineTranslateJsResult;
  if (!result.ok) {
    throw StateError(
      'OfflineTranslate warmup failed: ${result.kind ?? 'unknown'}',
    );
  }
}

OfflineTranslateOutcome _mapJsResult(JSAny? jsResult) {
  if (jsResult == null) {
    return const OfflineTranslateErr(
      kind: OfflineTranslateErrorKind.internal,
    );
  }
  final result = jsResult as OfflineTranslateJsResult;
  if (result.ok) {
    final gloss = (result.primaryGloss ?? '').trim();
    if (gloss.isEmpty) {
      return const OfflineTranslateErr(
        kind: OfflineTranslateErrorKind.inferenceFailed,
      );
    }
    return OfflineTranslateOk(primaryGloss: gloss);
  }
  return OfflineTranslateErr(
    kind: offlineTranslateErrorKindFromJs(result.kind),
  );
}

/// Bound to `globalThis.OfflineTranslate` from `web/translate_bridge.js`.
@JS('OfflineTranslate')
external OfflineTranslateBridgeJs? get offlineTranslateBridge;

/// JS facade: `{ translate(...), warmup(): Promise }` — process-wide ensure.
extension type OfflineTranslateBridgeJs._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> translate(
    String text,
    String sourceLang,
    String targetLang,
  );

  /// Loads Transformers.js pipeline once (shared with translate via worker).
  external JSPromise<JSAny?> warmup();
}

/// JS result shape from the worker bridge.
extension type OfflineTranslateJsResult._(JSObject _) implements JSObject {
  external bool get ok;
  external String? get primaryGloss;
  external String? get kind;
}
