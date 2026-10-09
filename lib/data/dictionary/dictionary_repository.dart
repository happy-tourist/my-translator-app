import 'package:drift/drift.dart';

import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/dictionary/dictionary_exceptions.dart';

/// Drift-backed personal vocabulary CRUD (`dictionary/entries`, design D4).
class DictionaryRepository {
  DictionaryRepository(this._db);

  final AppDatabase _db;

  /// `trim` + Unicode case-fold / lowercase — UNIQUE lookup key.
  static String normalizeLemma(String lemma) => lemma.trim().toLowerCase();

  /// Adds or upserts by normalized lemma. Empty lemma/translation → validation.
  Future<DictionaryEntry> add({
    required String lemma,
    required String translation,
    String? context,
  }) async {
    final normalized = normalizeLemma(lemma);
    final trimmedTranslation = translation.trim();
    if (normalized.isEmpty) {
      throw DictionaryValidationException('Lemma must not be empty');
    }
    if (trimmedTranslation.isEmpty) {
      throw DictionaryValidationException('Translation must not be empty');
    }

    final trimmedContext = context?.trim();
    final contextValue =
        (trimmedContext == null || trimmedContext.isEmpty) ? null : trimmedContext;

    final existing = await lookup(normalized);
    final now = DateTime.now();
    if (existing != null) {
      await (_db.update(_db.dictionaryEntries)
            ..where((e) => e.lemma.equals(normalized)))
          .write(
            DictionaryEntriesCompanion(
              translation: Value(trimmedTranslation),
              context: Value(contextValue),
              updatedAt: Value(now),
            ),
          );
      return (await lookup(normalized))!;
    }

    final id = await _db
        .into(_db.dictionaryEntries)
        .insert(
          DictionaryEntriesCompanion.insert(
            lemma: normalized,
            translation: trimmedTranslation,
            context: Value(contextValue),
          ),
        );
    return (_db.select(
      _db.dictionaryEntries,
    )..where((e) => e.id.equals(id))).getSingle();
  }

  Future<List<DictionaryEntry>> list() {
    return (_db.select(_db.dictionaryEntries)
          ..orderBy([(e) => OrderingTerm.asc(e.lemma)]))
        .get();
  }

  Future<void> remove(int id) async {
    final deleted = await (_db.delete(
      _db.dictionaryEntries,
    )..where((e) => e.id.equals(id))).go();
    if (deleted == 0) {
      throw DictionaryValidationException('Dictionary entry not found');
    }
  }

  /// Lookup by lemma (any casing); returns null when absent.
  Future<DictionaryEntry?> lookup(String lemma) {
    final normalized = normalizeLemma(lemma);
    if (normalized.isEmpty) return Future.value(null);
    return (_db.select(
      _db.dictionaryEntries,
    )..where((e) => e.lemma.equals(normalized))).getSingleOrNull();
  }
}
