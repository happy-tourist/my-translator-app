import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show AnyhowException, PanicException;

import 'package:my_translator_app/src/rust/api/translate.dart' as rust_translate;

import 'offline_translate.dart';

/// Asset paths under pubspec `assets/models/opus-mt-en-ru/` (basename → load key).
const Map<String, String> kOfflineTranslateNativeAssetPaths = {
  'tokenizer.json': 'assets/models/opus-mt-en-ru/tokenizer.json',
  'encoder_model_uint8.onnx':
      'assets/models/opus-mt-en-ru/onnx/encoder_model_uint8.onnx',
  'decoder_model_uint8.onnx':
      'assets/models/opus-mt-en-ru/onnx/decoder_model_uint8.onnx',
};

/// Own large AssetBundle views with chunked copy + yields (design D3 / TO-11).
///
/// Avoid `Isolate.run` on AssetBundle views: external/Immutable buffers are often
/// not isolate-sendable, and sending ~100MB+ still blocks the UI isolate.
const int _kLargeAssetCopyBytes = 64 * 1024;
const int _kAssetCopyChunkBytes = 512 * 1024;

/// Process-wide in-flight ensure (design D2) — shared by warm-up and Translate.
Future<void>? _sharedInitFuture;

/// Test hook: replace readiness probe (avoids FRB in unit/widget tests).
@visibleForTesting
Future<bool> Function()? debugIsOfflineTranslateReadyOverride;

/// Test hook: replace `_loadAndInit` (fake slow init for TO-11 / ready no-op).
@visibleForTesting
Future<void> Function(AssetBundle bundle)? debugLoadAndInitOverride;

/// Test hook: count real/fake inits started via the shared ensure path.
@visibleForTesting
int debugOfflineTranslateInitStarts = 0;

/// Clears process-wide ensure state and test hooks.
@visibleForTesting
void debugResetOfflineTranslateNativeEnsure() {
  _sharedInitFuture = null;
  debugIsOfflineTranslateReadyOverride = null;
  debugLoadAndInitOverride = null;
  debugOfflineTranslateInitStarts = 0;
}

/// Native offline translate: AssetBundle bytes → lazy FRB init → translate_text.
OfflineTranslateFn createOfflineTranslate({AssetBundle? bundle}) {
  final impl = _NativeOfflineTranslate(bundle: bundle ?? rootBundle);
  return impl.translate;
}

/// Ensures native ORT session is ready (shared process-wide Future; design D2).
///
/// Reuses [isOfflineTranslateReady] / one in-flight `_loadAndInit` across all
/// `createOfflineTranslate()` instances and [warmUpOfflineTranslate].
/// When already ready — no-op (no second `initOfflineTranslate`).
Future<void> ensureOfflineTranslateReady({AssetBundle? bundle}) async {
  // Prefer joining an in-flight load before probing ready (design D2).
  final inFlight = _sharedInitFuture;
  if (inFlight != null) {
    await inFlight;
    return;
  }
  if (await _isReady()) {
    return;
  }
  // Share one in-flight load; clear when done so a later miss (engine cleared)
  // can start a fresh init instead of reusing a stale completed future.
  final future = _sharedInitFuture ??= _startLoadAndInit(bundle ?? rootBundle);
  try {
    await future;
  } catch (_) {
    if (identical(_sharedInitFuture, future)) {
      _sharedInitFuture = null;
    }
    rethrow;
  }
  if (identical(_sharedInitFuture, future)) {
    _sharedInitFuture = null;
  }
}

/// Quiet background warm-up (design D2 / D6) — same ensure as Translate.
Future<void> warmUpOfflineTranslate({AssetBundle? bundle}) async {
  try {
    await ensureOfflineTranslateReady(bundle: bundle);
  } catch (_) {
    // Quiet: SnackBar only on later Translate (design D6).
  }
}

Future<bool> _isReady() async {
  final override = debugIsOfflineTranslateReadyOverride;
  if (override != null) {
    return override();
  }
  return rust_translate.isOfflineTranslateReady();
}

Future<void> _startLoadAndInit(AssetBundle bundle) {
  debugOfflineTranslateInitStarts++;
  final override = debugLoadAndInitOverride;
  if (override != null) {
    return override(bundle);
  }
  return _loadAndInit(bundle);
}

/// Cold path (design D3): yield frame → sequential AssetBundle awaits →
/// chunked own-copy with yields → async FRB init.
Future<void> _loadAndInit(AssetBundle bundle) async {
  // D3.1: yield so spinner / shell can paint before heavy work.
  await Future<void>.delayed(Duration.zero);

  final assets = <rust_translate.OfflineModelAsset>[];
  for (final entry in kOfflineTranslateNativeAssetPaths.entries) {
    // D3.2: sequential async loads (one asset at a time).
    final data = await bundle.load(entry.value);
    final view = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    // D3.2: own large buffers without a single multi‑100MB sync stall.
    final bytes = await _ownAssetBytes(view);
    if (bytes.isEmpty) {
      throw FlutterError('Offline translate asset empty: ${entry.value}');
    }
    assets.add(
      rust_translate.OfflineModelAsset(
        name: entry.key,
        bytes: bytes,
      ),
    );
  }
  // D3.3: FRB init stays Normal async (worker pool) — not sync on UI isolate.
  await rust_translate.initOfflineTranslate(assets: assets);
}

Future<Uint8List> _ownAssetBytes(Uint8List view) async {
  final length = view.lengthInBytes;
  if (length < _kLargeAssetCopyBytes) {
    return Uint8List.fromList(view);
  }
  final owned = Uint8List(length);
  var offset = 0;
  while (offset < length) {
    final end = offset + _kAssetCopyChunkBytes;
    final chunkEnd = end < length ? end : length;
    owned.setRange(offset, chunkEnd, view, offset);
    offset = chunkEnd;
    if (offset < length) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  return owned;
}

/// Test hook: chunked own-copy used on the native cold path (design D3 / TO-11).
@visibleForTesting
Future<Uint8List> debugOwnOfflineTranslateAssetBytes(Uint8List view) =>
    _ownAssetBytes(view);

class _NativeOfflineTranslate {
  _NativeOfflineTranslate({required this._bundle});

  final AssetBundle _bundle;

  Future<OfflineTranslateOutcome> translate({
    required String text,
    String sourceLang = 'en',
    String targetLang = 'ru',
  }) async {
    try {
      await ensureOfflineTranslateReady(bundle: _bundle);
      final result = await rust_translate.translateText(
        text: text,
        sourceLang: sourceLang,
        targetLang: targetLang,
      );
      final gloss = result.primaryGloss.trim();
      if (gloss.isEmpty) {
        return const OfflineTranslateErr(
          kind: OfflineTranslateErrorKind.inferenceFailed,
        );
      }
      return OfflineTranslateOk(primaryGloss: gloss);
    } on rust_translate.TranslateErrorKind catch (kind) {
      return OfflineTranslateErr(kind: _mapFrbKind(kind));
    } on FlutterError catch (e, st) {
      // Missing / unreadable AssetBundle entries → same UX as engine down (TO-04).
      assert(() {
        debugPrint('offline translate asset: $e\n$st');
        return true;
      }());
      return const OfflineTranslateErr(
        kind: OfflineTranslateErrorKind.engineUnavailable,
      );
    } on AnyhowException catch (e, st) {
      assert(() {
        debugPrint('offline translate Anyhow: ${e.message}\n$st');
        return true;
      }());
      return const OfflineTranslateErr(
        kind: OfflineTranslateErrorKind.internal,
      );
    } on PanicException catch (e, st) {
      assert(() {
        debugPrint('offline translate panic: ${e.message}\n$st');
        return true;
      }());
      return const OfflineTranslateErr(
        kind: OfflineTranslateErrorKind.internal,
      );
    } catch (e, st) {
      assert(() {
        debugPrint('offline translate unexpected: $e\n$st');
        return true;
      }());
      return const OfflineTranslateErr(
        kind: OfflineTranslateErrorKind.internal,
      );
    }
  }
}

OfflineTranslateErrorKind _mapFrbKind(rust_translate.TranslateErrorKind kind) {
  switch (kind) {
    case rust_translate.TranslateErrorKind.emptyQuery:
      return OfflineTranslateErrorKind.emptyQuery;
    case rust_translate.TranslateErrorKind.unsupportedLanguagePair:
      return OfflineTranslateErrorKind.unsupportedLanguagePair;
    case rust_translate.TranslateErrorKind.engineUnavailable:
      return OfflineTranslateErrorKind.engineUnavailable;
    case rust_translate.TranslateErrorKind.inferenceFailed:
      return OfflineTranslateErrorKind.inferenceFailed;
    case rust_translate.TranslateErrorKind.internal:
      return OfflineTranslateErrorKind.internal;
  }
}
