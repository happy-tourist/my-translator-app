import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';
import 'package:my_translator_app/features/vocab/vocabulary_screen.dart';

import '../support/test_database.dart';

/// Identity morph for widget tests (no RustLib): casefold only.
Future<List<String>> _identityLemmaKeys(List<String> surfaces) async =>
    surfaces.map((s) => s.trim().toLowerCase()).toList();

/// Fake morph: running → run (covers Vocab FRB seam wiring).
Future<List<String>> _morphLemmaKeys(List<String> surfaces) async {
  return surfaces.map((s) {
    final lower = s.trim().toLowerCase();
    if (lower == 'running') return 'run';
    return lower;
  }).toList();
}

void main() {
  late final db = createTestDatabase();
  late DictionaryRepository dictionary;

  setUp(() {
    dictionary = DictionaryRepository(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  tearDown(() async {
    await db.delete(db.dictionaryEntries).go();
  });

  Future<void> pumpVocab(
    WidgetTester tester, {
    Future<List<String>> Function(List<String>)? lemmaKeys,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VocabularyScreen(
          dictionaryRepository: dictionary,
          lemmaKeysForSurfaces: lemmaKeys ?? _identityLemmaKeys,
        ),
      ),
    );
    expect(find.byKey(const Key('vocabLoading')), findsOneWidget);
    await tester.pumpAndSettle();
  }

  testWidgets('DE-11: Empty vocabulary shows add form CTA', (tester) async {
    await pumpVocab(tester);
    expect(find.byKey(const Key('vocabEmpty')), findsOneWidget);
    expect(find.byKey(const Key('vocabAddForm')), findsOneWidget);
    expect(find.byKey(const Key('vocabLemmaField')), findsOneWidget);
    expect(find.byKey(const Key('vocabTranslationField')), findsOneWidget);
    expect(find.byKey(const Key('vocabAddButton')), findsOneWidget);
    // Empty state does not require Reader.
    expect(find.textContaining('Reader'), findsNothing);
  });

  testWidgets('DE-04: List after several adds', (tester) async {
    await dictionary.add(lemma: 'run', surfaceKey: 'run', translation: 'бежать');
    await dictionary.add(lemma: 'cat', surfaceKey: 'cat', translation: 'кот');

    await pumpVocab(tester);

    expect(find.byKey(const Key('vocabList')), findsOneWidget);
    expect(find.text('run'), findsOneWidget);
    expect(find.text('cat'), findsOneWidget);
    expect(find.textContaining('бежать'), findsOneWidget);
    expect(find.textContaining('кот'), findsOneWidget);
  });

  testWidgets('DE-05: Remove entry from UI', (tester) async {
    final added = await dictionary.add(
      lemma: 'run',
      surfaceKey: 'run',
      translation: 'бежать',
    );

    await pumpVocab(tester);
    expect(find.text('run'), findsOneWidget);

    await tester.tap(find.byKey(Key('vocabDelete_${added.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vocabDeleteDialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('vocabDeleteConfirm')));
    await tester.pumpAndSettle();

    expect(find.text('run'), findsNothing);
    expect(find.byKey(const Key('vocabEmpty')), findsOneWidget);
    expect(await dictionary.lookup('run'), isNull);
  });

  testWidgets('DE-09: Reject empty lemma or translation in UI', (tester) async {
    await pumpVocab(tester);

    await tester.enterText(find.byKey(const Key('vocabLemmaField')), '   ');
    await tester.enterText(find.byKey(const Key('vocabTranslationField')), 'кот');
    await tester.tap(find.byKey(const Key('vocabAddButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vocabFormError')), findsOneWidget);
    expect(find.textContaining('must not be empty'), findsOneWidget);
    expect(await dictionary.list(), isEmpty);

    await tester.enterText(find.byKey(const Key('vocabLemmaField')), 'cat');
    await tester.enterText(find.byKey(const Key('vocabTranslationField')), '  ');
    await tester.tap(find.byKey(const Key('vocabAddButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vocabFormError')), findsOneWidget);
    expect(await dictionary.list(), isEmpty);
  });

  testWidgets('Vocab add runs input through LemmaKeysForSurfacesFn',
      (tester) async {
    await pumpVocab(tester, lemmaKeys: _morphLemmaKeys);

    await tester.enterText(find.byKey(const Key('vocabLemmaField')), 'Running');
    await tester.enterText(
      find.byKey(const Key('vocabTranslationField')),
      'бежать',
    );
    await tester.tap(find.byKey(const Key('vocabAddButton')));
    await tester.pumpAndSettle();

    final list = await dictionary.list();
    expect(list, hasLength(1));
    expect(list.single.lemma, 'run');
    expect(list.single.surfaceKey, 'running');
    expect(list.single.translation, 'бежать');
  });
}
