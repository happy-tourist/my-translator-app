import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/dictionary/dictionary_exceptions.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';

import '../support/test_database.dart';

/// Test morph map: EN wordforms → lemma; phrases/other → casefold identity.
Future<List<String>> _fakeLemmaKeys(List<String> surfaces) async {
  const morph = {
    'running': 'run',
    'ran': 'run',
    'dogs': 'dog',
    'run': 'run',
    'dog': 'dog',
    'cat': 'cat',
  };
  return surfaces.map((s) {
    final lower = s.trim().toLowerCase();
    return morph[lower] ?? lower;
  }).toList();
}

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
      surfaceKey: 'run',
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
    await dictionary.add(
      lemma: 'dog',
      surfaceKey: 'dog',
      translation: 'собака',
      context: 'bark',
    );
    await dictionary.add(lemma: 'cat', surfaceKey: 'cat', translation: 'кот');
    final entry = await dictionary.lookup('cat');
    expect(entry, isNotNull);
    expect(entry!.translation, 'кот');
    expect(entry.context, isNull);
  });

  test('DE-03: Second add of same lemma upserts', () async {
    await dictionary.add(lemma: 'run', surfaceKey: 'run', translation: 'бежать');
    await dictionary.add(
      lemma: 'run',
      surfaceKey: 'run',
      translation: 'бегать',
      context: 'new context',
    );
    final list = await dictionary.list();
    expect(list, hasLength(1));
    expect(list.single.translation, 'бегать');
    expect(list.single.context, 'new context');
  });

  test('DE-04: List after several adds', () async {
    await dictionary.add(lemma: 'run', surfaceKey: 'run', translation: 'бежать');
    await dictionary.add(lemma: 'cat', surfaceKey: 'cat', translation: 'кот');
    final list = await dictionary.list();
    expect(list.map((e) => e.lemma).toList(), ['cat', 'run']);
  });

  test('DE-05: Remove entry', () async {
    final added = await dictionary.add(
      lemma: 'run',
      surfaceKey: 'run',
      translation: 'бежать',
    );
    await dictionary.remove(added.id);
    expect(await dictionary.list(), isEmpty);
    expect(await dictionary.lookup('run'), isNull);
  });

  test('DE-06: Lookup hit (case-insensitive)', () async {
    await dictionary.add(lemma: 'run', surfaceKey: 'run', translation: 'бежать');
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
      () => dictionary.add(lemma: '   ', surfaceKey: '', translation: 'кот'),
      throwsA(isA<DictionaryValidationException>()),
    );
    expect(
      () => dictionary.add(lemma: 'cat', surfaceKey: 'cat', translation: '  '),
      throwsA(isA<DictionaryValidationException>()),
    );
    expect(await dictionary.list(), isEmpty);
  });

  test('DE-10: Case-insensitive lemma identity', () async {
    await dictionary.add(lemma: 'run', surfaceKey: 'run', translation: 'бежать');
    await dictionary.add(lemma: 'Run', surfaceKey: 'run', translation: 'бегать');
    final list = await dictionary.list();
    expect(list, hasLength(1));
    expect(list.single.lemma, 'run');
    expect(list.single.translation, 'бегать');
  });

  test('DE-14: Surface key stored for token', () async {
    await dictionary.add(
      lemma: 'run',
      surfaceKey: 'Running',
      translation: 'бежать',
    );
    final entry = await dictionary.lookup('run');
    expect(entry, isNotNull);
    expect(entry!.lemma, 'run');
    expect(entry.surfaceKey, 'running');
  });

  test('DE-15: Schema migration merges collisions', () async {
    final older = DateTime.utc(2024, 1, 1);
    final newer = DateTime.utc(2024, 6, 1);
    await db.into(db.dictionaryEntries).insert(
          DictionaryEntriesCompanion.insert(
            lemma: 'running',
            translation: 'бежал',
            context: const Value('older context'),
            createdAt: Value(older),
            updatedAt: Value(older),
          ),
        );
    await db.into(db.dictionaryEntries).insert(
          DictionaryEntriesCompanion.insert(
            lemma: 'ran',
            translation: 'побежал',
            context: const Value('newer context'),
            createdAt: Value(newer),
            updatedAt: Value(newer),
          ),
        );

    await dictionary.migrateStubKeysIfNeeded(
      lemmaKeysForSurfaces: _fakeLemmaKeys,
    );

    final list = await dictionary.list();
    expect(list, hasLength(1));
    expect(list.single.lemma, 'run');
    expect(list.single.translation, 'побежал');
    expect(list.single.context, 'newer context');
    expect(list.single.surfaceKey, 'ran');

    // Idempotent: second call is a no-op.
    await dictionary.migrateStubKeysIfNeeded(
      lemmaKeysForSurfaces: _fakeLemmaKeys,
    );
    expect(await dictionary.list(), hasLength(1));
  });

  test('DE-16: Phrase rows survive migration', () async {
    await db.into(db.dictionaryEntries).insert(
          DictionaryEntriesCompanion.insert(
            lemma: 'hello world',
            translation: 'привет мир',
          ),
        );

    await dictionary.migrateStubKeysIfNeeded(
      lemmaKeysForSurfaces: _fakeLemmaKeys,
    );

    final list = await dictionary.list();
    expect(list, hasLength(1));
    expect(list.single.lemma, 'hello world');
    expect(list.single.surfaceKey, 'hello world');
    expect(list.single.translation, 'привет мир');
  });

  test('DE-17: Morph-fail key is casefold surface', () async {
    await dictionary.add(
      lemma: 'привет',
      surfaceKey: 'Привет',
      translation: 'hello',
    );
    final entry = await dictionary.lookup('привет');
    expect(entry, isNotNull);
    expect(entry!.lemma, 'привет');
    expect(entry.surfaceKey, 'привет');
  });
}
