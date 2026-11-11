import 'package:flutter/foundation.dart';

/// Process-wide Web ensure slot (design D2) — shared by warm-up and Translate.
///
/// Kept free of `dart:js_interop` so VM unit tests can cover race / no-op
/// behaviour without a browser. Production runner lives in
/// [offline_translate_web.dart] (`_runWarmup` → bridge `warmup`).
Future<void>? _sharedEnsureFuture;

/// Test hook: replace bridge warmup runner.
@visibleForTesting
Future<void> Function()? debugWebRunWarmupOverride;

/// Test hook: count warmups started via the shared ensure path.
@visibleForTesting
int debugOfflineTranslateWebWarmupStarts = 0;

/// Clears process-wide ensure state and test hooks.
@visibleForTesting
void debugResetOfflineTranslateWebEnsure() {
  _sharedEnsureFuture = null;
  debugWebRunWarmupOverride = null;
  debugOfflineTranslateWebWarmupStarts = 0;
}

/// Ensures Web Transformers.js pipeline is ready (shared process-wide Future).
///
/// [runWarmup] posts bridge `warmup` once in production; concurrent Translate /
/// warm-up callers await the same Future (bridge + worker `translatorPromise`
/// also dedupe pipeline create).
Future<void> ensureOfflineTranslateReady({
  required Future<void> Function() runWarmup,
}) async {
  final inFlight = _sharedEnsureFuture;
  if (inFlight != null) {
    await inFlight;
    return;
  }

  final future = _sharedEnsureFuture ??= _startWarmup(runWarmup);
  try {
    await future;
  } catch (_) {
    if (identical(_sharedEnsureFuture, future)) {
      _sharedEnsureFuture = null;
    }
    rethrow;
  }
  // Leave completed Future in place for subsequent ensures in this process.
}

/// Quiet background warm-up (design D2 / D6) — same ensure as Translate.
Future<void> warmUpOfflineTranslate({
  required Future<void> Function() runWarmup,
}) async {
  try {
    await ensureOfflineTranslateReady(runWarmup: runWarmup);
  } catch (_) {
    // Quiet: SnackBar only on later Translate (design D6).
  }
}

Future<void> _startWarmup(Future<void> Function() runWarmup) {
  debugOfflineTranslateWebWarmupStarts++;
  final override = debugWebRunWarmupOverride;
  if (override != null) {
    return override();
  }
  return runWarmup();
}
