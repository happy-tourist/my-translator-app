import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/translate/offline_translate_web_ensure.dart';

/// Facade ensure races without a browser (design D2 / task 3.1).
///
/// JS bridge + worker share one `translatorPromise`; this covers the Dart
/// process-wide Future that wraps bridge `warmup`.
void main() {
  tearDown(debugResetOfflineTranslateWebEnsure);

  Future<void> noopWarmup() async {}

  test('3.1 shared in-flight: parallel ensure starts one warmup', () async {
    final gate = Completer<void>();
    debugWebRunWarmupOverride = () => gate.future;

    final a = ensureOfflineTranslateReady(runWarmup: noopWarmup);
    final b = ensureOfflineTranslateReady(runWarmup: noopWarmup);
    await Future<void>.delayed(Duration.zero);
    expect(debugOfflineTranslateWebWarmupStarts, 1);

    gate.complete();
    await Future.wait([a, b]);
    expect(debugOfflineTranslateWebWarmupStarts, 1);
  });

  test('3.1 successful warmup is process-wide no-op', () async {
    debugWebRunWarmupOverride = () async {};

    await ensureOfflineTranslateReady(runWarmup: noopWarmup);
    await warmUpOfflineTranslate(runWarmup: noopWarmup);
    await ensureOfflineTranslateReady(runWarmup: noopWarmup);
    expect(debugOfflineTranslateWebWarmupStarts, 1);
  });

  test('3.1 warmup∥translate-style race: shell + mid-tap share one ensure',
      () async {
    final gate = Completer<void>();
    var ensureJoins = 0;
    debugWebRunWarmupOverride = () async {
      ensureJoins++;
      await gate.future;
    };

    // Simulate shell warm-up + Translate ensure while pipeline still loading.
    final warm = warmUpOfflineTranslate(runWarmup: noopWarmup);
    final midEnsure = ensureOfflineTranslateReady(runWarmup: noopWarmup);
    await Future<void>.delayed(Duration.zero);
    expect(debugOfflineTranslateWebWarmupStarts, 1);

    gate.complete();
    await Future.wait([warm, midEnsure]);
    expect(debugOfflineTranslateWebWarmupStarts, 1);
    expect(ensureJoins, 1);
  });

  test('3.1 failed warmup clears slot so retry can start again', () async {
    var shouldFail = true;
    debugWebRunWarmupOverride = () async {
      if (shouldFail) {
        throw StateError('fake warmup fail');
      }
    };

    await expectLater(
      ensureOfflineTranslateReady(runWarmup: noopWarmup),
      throwsStateError,
    );
    expect(debugOfflineTranslateWebWarmupStarts, 1);

    shouldFail = false;
    await ensureOfflineTranslateReady(runWarmup: noopWarmup);
    expect(debugOfflineTranslateWebWarmupStarts, 2);
  });
}
