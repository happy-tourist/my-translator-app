import 'offline_translate.dart';
import 'offline_translate_native.dart'
    if (dart.library.html) 'offline_translate_web.dart'
    as impl;

/// Production facade: native FRB ORT vs Web Transformers.js (design D4.1).
OfflineTranslateFn createPlatformOfflineTranslate() =>
    impl.createOfflineTranslate();
