import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'offline_translate.dart';

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

/// JS facade shape: `{ translate(text, sourceLang, targetLang): Promise }`.
extension type OfflineTranslateBridgeJs._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> translate(
    String text,
    String sourceLang,
    String targetLang,
  );
}

/// JS result shape from the worker bridge.
extension type OfflineTranslateJsResult._(JSObject _) implements JSObject {
  external bool get ok;
  external String? get primaryGloss;
  external String? get kind;
}
