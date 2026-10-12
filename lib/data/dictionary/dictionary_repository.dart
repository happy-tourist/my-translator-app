import 'package:drift/drift.dart';

import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/dictionary/dictionary_exceptions.dart';
import 'package:my_translator_app/data/dictionary/lemma_keys_for_surfaces_fn.dart';

/// Drift-backed personal vocabulary CRUD (`dictionary/entries`, design D4 / D5.1).
///
/// Call site supplies morph [lemma] (Reader token / FRB `lemmaKeysForSurfaces`).
/// Repository does **not** call WordNet / FRB itself.
class DictionaryRepository {
  DictionaryRepository(this._db);

  final AppDatabase _db;

  /// `trim` + Unicode lowercase; collapse internal whitespace to single spaces
  /// so phrase keys match Rust `casefold(join(surfaces, " "))` (D2 / DE-18).
  static String normalizeSurface(String surface) {
    final trimmed = surface.trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    return trimmed
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');
  }

  /// Adds or upserts by morph [lemma]. Empty lemma/translation → validation.
  Future<DictionaryEntry> add({
    required String lemma,
    required String surfaceKey,
    required String translation,
    String? context,
  }) async {
    final normalizedLemma = normalizeSurface(lemma);
    final normalizedSurface = normalizeSurface(surfaceKey);
    final trimmedTranslation = translation.trim();
    if (normalizedLemma.isEmpty) {
      throw DictionaryValidationException('Lemma must not be empty');
    }
    if (trimmedTranslation.isEmpty) {
      throw DictionaryValidationException('Translation must not be empty');
    }

    final trimmedContext = context?.trim();
    final contextValue =
        (trimmedContext == null || trimmedContext.isEmpty) ? null : trimmedContext;

    final existing = await lookup(normalizedLemma);
    final now = DateTime.now();
    if (existing != null) {
      await (_db.update(_db.dictionaryEntries)
            ..where((e) => e.lemma.equals(normalizedLemma)))
          .write(
            DictionaryEntriesCompanion(
              surfaceKey: Value(normalizedSurface),
              translation: Value(trimmedTranslation),
              context: Value(contextValue),
              updatedAt: Value(now),
            ),
          );
      return (await lookup(normalizedLemma))!;
    }

    final id = await _db
        .into(_db.dictionaryEntries)
        .insert(
          DictionaryEntriesCompanion.insert(
            lemma: normalizedLemma,
            translation: trimmedTranslation,
            surfaceKey: Value(normalizedSurface),
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

  /// Lookup by morph lemma (any casing); returns null when absent.
  ///
  /// Exact match on [normalizeSurface] first; for multi-word keys, also accepts
  /// legacy rows whose stored `lemma` only differs by irregular whitespace.
  Future<DictionaryEntry?> lookup(String lemma) async {
    final normalized = normalizeSurface(lemma);
    if (normalized.isEmpty) return null;
    final exact = await (_db.select(
      _db.dictionaryEntries,
    )..where((e) => e.lemma.equals(normalized))).getSingleOrNull();
    if (exact != null) return exact;
    if (!normalized.contains(RegExp(r'\s'))) return null;
    final rows = await list();
    for (final e in rows) {
      if (normalizeSurface(e.lemma) == normalized) return e;
    }
    return null;
  }

  /// One-shot stub→morph rewrite (DE-15 / DE-16). Idempotent: skips when every
  /// row already has [DictionaryEntry.surfaceKey]. Does not embed WordNet —
  /// call site injects [lemmaKeysForSurfaces] (FRB or test fake).
  Future<void> migrateStubKeysIfNeeded({
    required LemmaKeysForSurfacesFn lemmaKeysForSurfaces,
  }) async {
    final pending = await (_db.select(
      _db.dictionaryEntries,
    )..where((e) => e.surfaceKey.isNull())).get();
    if (pending.isEmpty) return;

    final oldLemmas = pending.map((e) => e.lemma).toList();
    final morphKeys = await lemmaKeysForSurfaces(oldLemmas);
    if (morphKeys.length != oldLemmas.length) {
      throw StateError(
        'lemmaKeysForSurfaces length mismatch: '
        '${morphKeys.length} != ${oldLemmas.length}',
      );
    }

    final byMorph = <String, List<DictionaryEntry>>{};
    for (var i = 0; i < pending.length; i++) {
      final rawMorph = morphKeys[i];
      final morph = normalizeSurface(rawMorph).isEmpty
          ? normalizeSurface(oldLemmas[i])
          : normalizeSurface(rawMorph);
      byMorph.putIfAbsent(morph, () => []).add(pending[i]);
    }

    await _db.transaction(() async {
      for (final entry in byMorph.entries) {
        final morph = entry.key;
        final rows = List<DictionaryEntry>.from(entry.value)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        final winner = rows.first;
        for (final loser in rows.skip(1)) {
          await (_db.delete(
            _db.dictionaryEntries,
          )..where((e) => e.id.equals(loser.id))).go();
        }
        await (_db.update(_db.dictionaryEntries)
              ..where((e) => e.id.equals(winner.id)))
            .write(
              DictionaryEntriesCompanion(
                lemma: Value(morph),
                // Winner's legacy stub / casefold surface (design D4).
                surfaceKey: Value(winner.lemma),
              ),
            );
      }
    });
  }
}
