import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/app/shell.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/features/upload/library_screen.dart';
import 'package:my_translator_app/features/vocab/vocabulary_screen.dart';

import '../support/test_database.dart';

void main() {
  late final db = createTestDatabase();

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
}
