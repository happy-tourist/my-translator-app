import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show AnyhowException, PanicException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// Chunked disk write size (design D13 / TO-11) — yield between chunks.
const int _kAssetWriteChunkBytes = 512 * 1024;

/// Subdir under application support for extracted OPUS-MT files.
const String _kModelCacheSubdir = 'opus-mt-en-ru';

/// Process-wide in-flight ensure (design D2) — shared by warm-up and Translate.
Future<void>? _sharedInitFuture;

/// Test hook: replace readiness probe (avoids FRB in unit/widget tests).
@visibleForTesting
Future<bool> Function()? debugIsOfflineTranslateReadyOverride;

/// Test hook: replace `_loadAndInit` (fake slow init for TO-11 / ready no-op).
@visibleForTesting
Future<void> Function(AssetBundle bundle)? debugLoadAndInitOverride;

/// Test hook: replace model cache directory (avoids path_provider in unit tests).
@visibleForTesting
Future<Directory> Function()? debugModelDirOverride;

/// Test hook: replace path/dir FRB init (avoids ORT in unit tests).
@visibleForTesting
Future<void> Function(String modelDir)? debugInitFromDirOverride;

/// Test hook: count real/fake inits started via the shared ensure path.
@visibleForTesting
int debugOfflineTranslateInitStarts = 0;

/// Test hook: count extract passes that actually copy at least one asset file.
@visibleForTesting
int debugOfflineTranslateExtractPasses = 0;

/// Test hook: count path/dir FRB inits (product path — never full bytes→FRB).
@visibleForTesting
int debugOfflineTranslatePathInitStarts = 0;

/// Clears process-wide ensure state and test hooks.
@visibleForTesting
void debugResetOfflineTranslateNativeEnsure() {
  _sharedInitFuture = null;
  debugIsOfflineTranslateReadyOverride = null;
  debugLoadAndInitOverride = null;
  debugModelDirOverride = null;
  debugInitFromDirOverride = null;
  debugOfflineTranslateInitStarts = 0;
  debugOfflineTranslateExtractPasses = 0;
  debugOfflineTranslatePathInitStarts = 0;
}

/// Native offline translate: AssetBundle → app-local dir → path FRB init.
OfflineTranslateFn createOfflineTranslate({AssetBundle? bundle}) {
  final impl = _NativeOfflineTranslate(bundle: bundle ?? rootBundle);
  return impl.translate;
}

/// Ensures native ORT session is ready (shared process-wide Future; design D2).
///
/// Reuses [isOfflineTranslateReady] / one in-flight `_loadAndInit` across all
/// `createOfflineTranslate()` instances and [warmUpOfflineTranslate].
/// When already ready — no-op (no second extract / path init).
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

/// Cold path (design D13): yield → extract/reuse assets on disk → path FRB init.
///
/// Product ensure MUST NOT pass full ONNX through Dart→FRB `Vec<u8>` (TO-11/14).
Future<void> _loadAndInit(AssetBundle bundle) async {
  // Yield so spinner / shell can paint before heavy work.
  await Future<void>.delayed(Duration.zero);

  final modelDir = await _resolveModelDir();
  await modelDir.create(recursive: true);

  final didExtract = await _extractModelAssetsIfNeeded(bundle, modelDir);
  if (didExtract) {
    debugOfflineTranslateExtractPasses++;
  }

  debugOfflineTranslatePathInitStarts++;
  final initOverride = debugInitFromDirOverride;
  if (initOverride != null) {
    await initOverride(modelDir.path);
  } else {
    await rust_translate.initOfflineTranslateFromDir(modelDir: modelDir.path);
  }
}

Future<Directory> _resolveModelDir() async {
  final override = debugModelDirOverride;
  if (override != null) {
    return override();
  }
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, _kModelCacheSubdir));
}

/// Returns true when at least one file was written (not a pure reuse).
Future<bool> _extractModelAssetsIfNeeded(
  AssetBundle bundle,
  Directory modelDir,
) async {
  // Fast reuse: skip AssetBundle loads when all required files look present.
  if (await _modelFilesLookReady(modelDir)) {
    return false;
  }

  var wroteAny = false;
  for (final entry in kOfflineTranslateNativeAssetPaths.entries) {
    // Yield between assets so gate/Translate spinners can paint (TO-11).
    await Future<void>.delayed(Duration.zero);
    final dest = File(p.join(modelDir.path, entry.key));
    final data = await bundle.load(entry.value);
    final length = data.lengthInBytes;
    if (length == 0) {
      throw FlutterError('Offline translate asset empty: ${entry.value}');
    }
    if (await dest.exists() && await dest.length() == length) {
      // Reuse this file; still may need to write others.
      continue;
    }
    wroteAny = true;
    final view = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await _writeAssetFileChunked(dest, view);
  }
  return wroteAny;
}

/// Heuristic disk reuse (design D13): required basenames present with plausible sizes.
Future<bool> _modelFilesLookReady(Directory modelDir) async {
  for (final name in kOfflineTranslateNativeAssetPaths.keys) {
    final file = File(p.join(modelDir.path, name));
    if (!await file.exists()) {
      return false;
    }
    final length = await file.length();
    final minBytes = name.endsWith('.onnx') ? (1024 * 1024) : 1024;
    if (length < minBytes) {
      return false;
    }
  }
  return true;
}

/// Chunked write with yields so the UI isolate can paint (TO-11).
Future<void> _writeAssetFileChunked(File dest, Uint8List view) async {
  final tmp = File('${dest.path}.tmp');
  final sink = tmp.openWrite();
  try {
    var offset = 0;
    final length = view.lengthInBytes;
    while (offset < length) {
      final end = offset + _kAssetWriteChunkBytes;
      final chunkEnd = end < length ? end : length;
      sink.add(Uint8List.sublistView(view, offset, chunkEnd));
      offset = chunkEnd;
      if (offset < length) {
        await sink.flush();
        await Future<void>.delayed(Duration.zero);
      }
    }
    await sink.flush();
  } finally {
    await sink.close();
  }
  if (await dest.exists()) {
    await dest.delete();
  }
  await tmp.rename(dest.path);
}

/// Test hook: chunked disk write used on the native cold path (design D13 / TO-11).
@visibleForTesting
Future<void> debugWriteOfflineTranslateAssetFileChunked(
  File dest,
  Uint8List view,
) =>
    _writeAssetFileChunked(dest, view);

/// Test hook: extract/reuse pass used by product `_loadAndInit`.
@visibleForTesting
Future<bool> debugExtractOfflineTranslateModelAssets(
  AssetBundle bundle,
  Directory modelDir,
) =>
    _extractModelAssetsIfNeeded(bundle, modelDir);

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
    } on FileSystemException catch (e, st) {
      // Extract / support-dir I/O fail → engine down (TO-04 / D13), not Internal.
      assert(() {
        debugPrint('offline translate filesystem: $e\n$st');
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
