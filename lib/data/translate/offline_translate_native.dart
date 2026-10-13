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

/// Native offline translate: AssetBundle bytes → lazy FRB init → translate_text.
OfflineTranslateFn createOfflineTranslate({AssetBundle? bundle}) {
  final impl = _NativeOfflineTranslate(bundle: bundle ?? rootBundle);
  return impl.translate;
}

class _NativeOfflineTranslate {
  _NativeOfflineTranslate({required this._bundle});

  final AssetBundle _bundle;
  Future<void>? _initFuture;

  Future<OfflineTranslateOutcome> translate({
    required String text,
    String sourceLang = 'en',
    String targetLang = 'ru',
  }) async {
    try {
      await _ensureInit();
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

  Future<void> _ensureInit() async {
    if (await rust_translate.isOfflineTranslateReady()) {
      return;
    }
    // Share one in-flight load; clear when done so a later miss (engine cleared)
    // can start a fresh init instead of reusing a stale completed future.
    final future = _initFuture ??= _loadAndInit();
    try {
      await future;
    } catch (_) {
      if (identical(_initFuture, future)) {
        _initFuture = null;
      }
      rethrow;
    }
    if (identical(_initFuture, future)) {
      _initFuture = null;
    }
  }

  Future<void> _loadAndInit() async {
    final assets = <rust_translate.OfflineModelAsset>[];
    for (final entry in kOfflineTranslateNativeAssetPaths.entries) {
      final data = await _bundle.load(entry.value);
      // Own the bytes (AssetBundle may return a view into a larger buffer).
      final bytes = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
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
    await rust_translate.initOfflineTranslate(assets: assets);
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
