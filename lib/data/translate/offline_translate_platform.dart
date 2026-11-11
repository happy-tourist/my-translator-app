import 'offline_translate.dart';
import 'offline_translate_native.dart'
    if (dart.library.html) 'offline_translate_web.dart'
    as impl;

/// Production facade: native FRB ORT vs Web Transformers.js (design D4.1).
OfflineTranslateFn createPlatformOfflineTranslate() =>
    impl.createOfflineTranslate();

/// Process-wide ensure shared by warm-up and Translate (design D2 / TO-09).
Future<void> ensureOfflineTranslateReady() =>
    impl.ensureOfflineTranslateReady();

/// Quiet background warm-up — same in-flight Future as Translate (design D2).
Future<void> warmUpOfflineTranslate() => impl.warmUpOfflineTranslate();
