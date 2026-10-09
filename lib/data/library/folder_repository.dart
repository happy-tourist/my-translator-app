import 'package:drift/drift.dart';

import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/library_exceptions.dart';

/// Drift-backed folder tree CRUD (`library/folders`).
class FolderRepository {
  FolderRepository(this._db, {this.contentStore});

  final AppDatabase _db;
  final DocumentContentStore? contentStore;

  /// Creates a folder at [parentId] (null = library root). Name is trimmed.
  Future<Folder> createFolder({required String name, int? parentId}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw LibraryValidationException('Folder name must not be empty');
    }
    if (parentId != null) {
      final parent = await (_db.select(
        _db.folders,
      )..where((f) => f.id.equals(parentId))).getSingleOrNull();
      if (parent == null) {
        throw LibraryValidationException('Parent folder not found');
      }
    }
    final id = await _db
        .into(_db.folders)
        .insert(
          FoldersCompanion.insert(name: trimmed, parentId: Value(parentId)),
        );
    return (_db.select(_db.folders)..where((f) => f.id.equals(id))).getSingle();
  }

  /// Immediate child folders of [parentId] (null = root).
  Future<List<Folder>> listChildren(int? parentId) async {
    final query = _db.select(_db.folders);
    if (parentId == null) {
      query.where((f) => f.parentId.isNull());
    } else {
      query.where((f) => f.parentId.equals(parentId));
    }
    query.orderBy([(f) => OrderingTerm.asc(f.name)]);
    return query.get();
  }

  Future<Folder?> getById(int id) {
    return (_db.select(
      _db.folders,
    )..where((f) => f.id.equals(id))).getSingleOrNull();
  }

  /// Cascade-deletes [folderId] subtree, documents, and sandbox files (D5).
  Future<void> deleteFolderCascade(int folderId) async {
    final folder = await getById(folderId);
    if (folder == null) {
      throw LibraryValidationException('Folder not found');
    }

    final subtreeIds = await _collectSubtreeIds(folderId);
    final docs =
        await (_db.select(_db.documents)
              ..where((d) => d.folderId.isIn(subtreeIds)))
            .get();
    final storageKeys = docs
        .map((d) => d.storageKey)
        .whereType<String>()
        .toList();

    await _db.transaction(() async {
      await (_db.delete(
        _db.documents,
      )..where((d) => d.folderId.isIn(subtreeIds))).go();
      // Delete deepest folders first to satisfy FK parent references.
      final ordered = subtreeIds.reversed.toList();
      for (final id in ordered) {
        await (_db.delete(_db.folders)..where((f) => f.id.equals(id))).go();
      }
    });

    final store = contentStore;
    if (store != null) {
      for (final key in storageKeys) {
        await store.delete(key);
      }
    }
  }

  Future<List<int>> _collectSubtreeIds(int rootId) async {
    final ids = <int>[rootId];
    final queue = <int>[rootId];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final children = await listChildren(current);
      for (final child in children) {
        ids.add(child.id);
        queue.add(child.id);
      }
    }
    return ids;
  }
}
