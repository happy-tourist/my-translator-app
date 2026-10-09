import 'document_content_store.dart';
import 'document_content_store_io.dart'
    if (dart.library.html) 'document_content_store_web.dart'
    as impl;

/// Production store: native sandbox path vs Web Drift content (D6).
DocumentContentStore createPlatformDocumentContentStore() => impl.createStore();
