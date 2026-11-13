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

  // TO-09: fullscreen gate blocks product shell until warm-up ready (design D1).
  testWidgets(
      'TO-09: fullscreen gate blocks shell until ensure/warm-up resolves',
      (tester) async {
    final gate = Completer<void>();
    var ready = false;
    debugIsOfflineTranslateReadyOverride = () async => ready;
    debugLoadAndInitOverride = (bundle) async {
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
          // Production default: fullscreen gate ON; fake ensure via debug overrides.
        ),
      ),
    );
    // pumpWidget draws the first frame; gate still in-flight → shell must not
    // be built/interactive yet (TO-09).
    expect(find.byType(LibraryScreen), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(debugOfflineTranslateInitStarts, 1);
    expect(find.byType(SnackBar), findsNothing);

    gate.complete();
    await tester.pump();
    await tester.pump();

    // Gate dismissed on success → product shell visible.
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    // TO-12 in-process: further warm-up/ensure after ready is a no-op.
    await warmUpOfflineTranslate(bundle: _EmptyBundle());
    expect(debugOfflineTranslateInitStarts, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  // TO-13: ensure/warm-up failure still dismisses the fullscreen gate.
  testWidgets(
      'TO-13: warm-up failure dismisses the fullscreen gate without SnackBar',
      (tester) async {
    debugIsOfflineTranslateReadyOverride = () async => false;
    debugLoadAndInitOverride = (bundle) async {
      throw FlutterError('offline translate asset empty: fake');
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
          // Production default: fullscreen gate ON; fake failing ensure.
        ),
      ),
    );
    expect(find.byType(LibraryScreen), findsNothing);

    // Let the failing ensure/warm-up settle (caught quietly by warmUp).
    await tester.pump();
    await tester.pump();

    // Fail → gate dismissed, product shell available, no mandatory SnackBar.
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
      'TO-09 escape hatch: disabled warm-up skips the gate entirely',
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
    // Escape hatch: gate skipped → shell interactive immediately, no ensure.
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(debugOfflineTranslateInitStarts, 0);
  });
}

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData(0);
}
