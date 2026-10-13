import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';
import 'package:my_translator_app/data/translate/offline_translate.dart';
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
    OfflineTranslateFn? offlineTranslate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VocabularyScreen(
          dictionaryRepository: dictionary,
          lemmaKeysForSurfaces: lemmaKeys ?? _identityLemmaKeys,
          offlineTranslate: offlineTranslate,
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

  testWidgets('DE-18: Vocab multi-word input → casefold without WordNet', (
    tester,
  ) async {
    var lemmaKeysCalls = 0;
    await pumpVocab(
      tester,
      lemmaKeys: (surfaces) async {
        lemmaKeysCalls++;
        return _morphLemmaKeys(surfaces);
      },
    );

    await tester.enterText(
      find.byKey(const Key('vocabLemmaField')),
      'Look Up',
    );
    await tester.enterText(
      find.byKey(const Key('vocabTranslationField')),
      'искать',
    );
    await tester.tap(find.byKey(const Key('vocabAddButton')));
    await tester.pumpAndSettle();

    expect(lemmaKeysCalls, 0);
    final list = await dictionary.list();
    expect(list, hasLength(1));
    expect(list.single.lemma, 'look up');
    expect(list.single.surfaceKey, 'look up');
    expect(list.single.translation, 'искать');
  });

  testWidgets('DE-19: Translate fills translation on Vocab form', (tester) async {
    var translateCalls = 0;
    String? lastQuery;
    await pumpVocab(
      tester,
      offlineTranslate: ({
        required String text,
        String sourceLang = 'en',
        String targetLang = 'ru',
      }) async {
        translateCalls++;
        lastQuery = text;
        return const OfflineTranslateOk(primaryGloss: 'привет');
      },
    );

    await tester.enterText(find.byKey(const Key('vocabLemmaField')), 'hello');
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('vocabTranslationField')),
      'old',
    );
    await tester.tap(find.byKey(const Key('vocabTranslateButton')));
    await tester.pumpAndSettle();

    expect(translateCalls, 1);
    expect(lastQuery, 'hello');
    final translation = tester.widget<TextField>(
      find.byKey(const Key('vocabTranslationField')),
    );
    expect(translation.controller!.text, 'привет');
    expect(await dictionary.list(), isEmpty);

    // Add stays enabled during/after Translate (not blocked by Translate).
    final add = tester.widget<ElevatedButton>(
      find.byKey(const Key('vocabAddButton')),
    );
    expect(add.onPressed, isNotNull);

    // Re-enabled after success.
    final translateBtn = tester.widget<OutlinedButton>(
      find.byKey(const Key('vocabTranslateButton')),
    );
    expect(translateBtn.onPressed, isNotNull);
  });

  testWidgets('DE-20: Translate disabled when lemma empty', (tester) async {
    await pumpVocab(
      tester,
      offlineTranslate: ({
        required String text,
        String sourceLang = 'en',
        String targetLang = 'ru',
      }) async =>
          const OfflineTranslateOk(primaryGloss: 'x'),
    );

    var btn = tester.widget<OutlinedButton>(
      find.byKey(const Key('vocabTranslateButton')),
    );
    expect(btn.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('vocabLemmaField')), '   ');
    await tester.pump();
    btn = tester.widget<OutlinedButton>(
      find.byKey(const Key('vocabTranslateButton')),
    );
    expect(btn.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('vocabLemmaField')), 'hi');
    await tester.pump();
    btn = tester.widget<OutlinedButton>(
      find.byKey(const Key('vocabTranslateButton')),
    );
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('DE-21: Translate error on Vocab does not fake gloss', (
    tester,
  ) async {
    await pumpVocab(
      tester,
      offlineTranslate: ({
        required String text,
        String sourceLang = 'en',
        String targetLang = 'ru',
      }) async =>
          const OfflineTranslateErr(
            kind: OfflineTranslateErrorKind.engineUnavailable,
          ),
    );

    await tester.enterText(find.byKey(const Key('vocabLemmaField')), 'hello');
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('vocabTranslationField')),
      'keep-me',
    );
    await tester.tap(find.byKey(const Key('vocabTranslateButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vocabTranslateErrorSnack')), findsOneWidget);
    expect(
      find.text('Translation unavailable. Try again later'),
      findsOneWidget,
    );
    final translation = tester.widget<TextField>(
      find.byKey(const Key('vocabTranslationField')),
    );
    expect(translation.controller!.text, 'keep-me');

    final translateBtn = tester.widget<OutlinedButton>(
      find.byKey(const Key('vocabTranslateButton')),
    );
    expect(translateBtn.onPressed, isNotNull);
  });

  testWidgets('DE-22: Attribution and disclaimer visible on Vocab', (
    tester,
  ) async {
    await pumpVocab(
      tester,
      offlineTranslate: ({
        required String text,
        String sourceLang = 'en',
        String targetLang = 'ru',
      }) async =>
          const OfflineTranslateOk(primaryGloss: 'x'),
    );

    expect(find.byKey(const Key('vocabTranslateAttribution')), findsOneWidget);
    expect(find.text(kOfflineTranslateAttribution), findsOneWidget);
    expect(find.text(kOfflineTranslateDisclaimer), findsOneWidget);
  });

  testWidgets('Vocab Translate shows loading then re-enables', (tester) async {
    final completer = Completer<OfflineTranslateOutcome>();
    await pumpVocab(
      tester,
      offlineTranslate: ({
        required String text,
        String sourceLang = 'en',
        String targetLang = 'ru',
      }) =>
          completer.future,
    );

    await tester.enterText(find.byKey(const Key('vocabLemmaField')), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('vocabTranslateButton')));
    await tester.pump();

    var btn = tester.widget<OutlinedButton>(
      find.byKey(const Key('vocabTranslateButton')),
    );
    expect(btn.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    // Add must not be blocked by Translate loading.
    final add = tester.widget<ElevatedButton>(
      find.byKey(const Key('vocabAddButton')),
    );
    expect(add.onPressed, isNotNull);

    completer.complete(const OfflineTranslateOk(primaryGloss: 'привет'));
    await tester.pumpAndSettle();

    btn = tester.widget<OutlinedButton>(
      find.byKey(const Key('vocabTranslateButton')),
    );
    expect(btn.onPressed, isNotNull);
  });
}
