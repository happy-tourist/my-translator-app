import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/app/shell.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/data/translate/offline_translate_native.dart';
import 'package:my_translator_app/features/upload/library_screen.dart';
import 'package:my_translator_app/features/vocab/vocabulary_screen.dart';

import '../support/test_database.dart';

void main() {
  late final db = createTestDatabase();

  tearDown(debugResetOfflineTranslateNativeEnsure);

  tearDownAll(() async {
    await db.close();
  });

  testWidgets('shell home is Library + Vocab; no scaffold Rust demo',
      (tester) async {
    final store = MemoryDocumentContentStore();
    await tester.pumpWidget(
      MaterialApp(
        title: 'Translation Reader',
        home: AppShell(
          database: db,
          contentStore: store,
          folderRepository: FolderRepository(db, contentStore: store),
          documentRepository: DocumentRepository(db, contentStore: store),
          dictionaryRepository: DictionaryRepository(db),
          lemmaKeysForSurfaces: (surfaces) async =>
              surfaces.map((s) => s.trim().toLowerCase()).toList(),
          // Escape hatch (D1): do not load offline model / FRB in widget tests.
          enableOfflineTranslateWarmUp: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(VocabularyScreen), findsNothing);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Vocab'), findsOneWidget);
    expect(find.text('Вызвать Rust'), findsNothing);
    expect(find.textContaining('Result:'), findsNothing);

    await tester.tap(find.text('Vocab'));
    await tester.pumpAndSettle();
    expect(find.byType(VocabularyScreen), findsOneWidget);
    expect(find.byType(LibraryScreen), findsNothing);
  });

  // TO-09: quiet warm-up after first AppShell post-frame (design D1).
  testWidgets('TO-09: AppShell post-frame seam starts offline translate warm-up',
      (tester) async {
    final gate = Completer<void>();
    var ready = false;
    var warmUpSawProductShell = false;
    debugIsOfflineTranslateReadyOverride = () async => ready;
    debugLoadAndInitOverride = (bundle) async {
      // Warm-up runs after shell paint: Library is already mounted.
      warmUpSawProductShell = find.byType(LibraryScreen).evaluate().isNotEmpty;
      await gate.future;
      ready = true;
    };

    final store = MemoryDocumentContentStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          database: db,
          contentStore: store,
          folderRepository: FolderRepository(db, contentStore: store),
          documentRepository: DocumentRepository(db, contentStore: store),
          dictionaryRepository: DictionaryRepository(db),
          lemmaKeysForSurfaces: (surfaces) async =>
              surfaces.map((s) => s.trim().toLowerCase()).toList(),
          // Production default: warm-up ON; fake ensure via debug overrides.
        ),
      ),
    );
    // pumpWidget draws the first frame and runs post-frame callbacks.
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(debugOfflineTranslateInitStarts, 1);
    expect(warmUpSawProductShell, isTrue);
    expect(find.byType(SnackBar), findsNothing);

    gate.complete();
    await tester.pump();

    // TO-12 in-process: further warm-up/ensure after ready is a no-op.
    await warmUpOfflineTranslate(bundle: _EmptyBundle());
    expect(debugOfflineTranslateInitStarts, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('TO-09 escape hatch: disabled warm-up does not start ensure',
      (tester) async {
    debugIsOfflineTranslateReadyOverride = () async => false;
    debugLoadAndInitOverride = (bundle) async {};

    final store = MemoryDocumentContentStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          database: db,
          contentStore: store,
          folderRepository: FolderRepository(db, contentStore: store),
          documentRepository: DocumentRepository(db, contentStore: store),
          dictionaryRepository: DictionaryRepository(db),
          lemmaKeysForSurfaces: (surfaces) async =>
              surfaces.map((s) => s.trim().toLowerCase()).toList(),
          enableOfflineTranslateWarmUp: false,
        ),
      ),
    );
    await tester.pump();
    expect(debugOfflineTranslateInitStarts, 0);
  });
}

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData(0);
}
