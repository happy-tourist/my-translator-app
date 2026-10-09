import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/dictionary/dictionary_exceptions.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';

import '../support/test_database.dart';

void main() {
  late final db = createTestDatabase();
  late final dictionary = DictionaryRepository(db);

  tearDownAll(() async {
    await db.close();
  });

  tearDown(() async {
    await db.delete(db.dictionaryEntries).go();
  });

  test('DE-01: Add entry with context', () async {
    await dictionary.add(
      lemma: 'run',
      translation: 'бежать',
      context: 'He was running',
    );
    final list = await dictionary.list();
    expect(list, hasLength(1));
    expect(list.single.lemma, 'run');
    expect(list.single.translation, 'бежать');
    expect(list.single.context, 'He was running');
  });

  test('DE-02: Add entry without context', () async {
    await dictionary.add(lemma: 'dog', translation: 'собака', context: 'bark');
    await dictionary.add(lemma: 'cat', translation: 'кот');
    final entry = await dictionary.lookup('cat');
    expect(entry, isNotNull);
    expect(entry!.translation, 'кот');
    expect(entry.context, isNull);
  });

  test('DE-03: Second add of same lemma upserts', () async {
    await dictionary.add(lemma: 'run', translation: 'бежать');
    await dictionary.add(
      lemma: 'run',
      translation: 'бегать',
      context: 'new context',
    );
    final list = await dictionary.list();
    expect(list, hasLength(1));
    expect(list.single.translation, 'бегать');
    expect(list.single.context, 'new context');
  });

  test('DE-04: List after several adds', () async {
    await dictionary.add(lemma: 'run', translation: 'бежать');
    await dictionary.add(lemma: 'cat', translation: 'кот');
    final list = await dictionary.list();
    expect(list.map((e) => e.lemma).toList(), ['cat', 'run']);
  });

  test('DE-05: Remove entry', () async {
    final added = await dictionary.add(lemma: 'run', translation: 'бежать');
    await dictionary.remove(added.id);
    expect(await dictionary.list(), isEmpty);
    expect(await dictionary.lookup('run'), isNull);
  });

  test('DE-06: Lookup hit (case-insensitive)', () async {
    await dictionary.add(lemma: 'run', translation: 'бежать');
    final byLower = await dictionary.lookup('run');
    final byTitle = await dictionary.lookup('Run');
    expect(byLower, isNotNull);
    expect(byLower!.translation, 'бежать');
    expect(byTitle, isNotNull);
    expect(byTitle!.id, byLower.id);
  });

  test('DE-07: Lookup miss', () async {
    expect(await dictionary.lookup('xyz'), isNull);
  });

  test('DE-09: Reject empty lemma or translation', () async {
    expect(
      () => dictionary.add(lemma: '   ', translation: 'кот'),
      throwsA(isA<DictionaryValidationException>()),
    );
    expect(
      () => dictionary.add(lemma: 'cat', translation: '  '),
      throwsA(isA<DictionaryValidationException>()),
    );
    expect(await dictionary.list(), isEmpty);
  });

  test('DE-10: Case-insensitive lemma identity', () async {
    await dictionary.add(lemma: 'run', translation: 'бежать');
    await dictionary.add(lemma: 'Run', translation: 'бегать');
    final list = await dictionary.list();
    expect(list, hasLength(1));
    expect(list.single.lemma, 'run');
    expect(list.single.translation, 'бегать');
  });
}
