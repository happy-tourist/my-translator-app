import 'package:drift/drift.dart';

/// Library folder tree (`library/folders`). Root folders have null [parentId].
class Folders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get parentId => integer().nullable().references(Folders, #id)();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Subtitle document in a folder (`library/documents`). Never root-level.
class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get folderId => integer().references(Folders, #id)();
  TextColumn get title => text()();
  /// One of: `srt`, `vtt`, `ass` (`.ssa` maps to `ass`).
  TextColumn get format => text()();
  /// Native sandbox relative path / key; unused on Web when [content] is set.
  TextColumn get storageKey => text().nullable()();
  /// Inline file bytes/text for Web (and optional native fallback).
  TextColumn get content => text().nullable()();
  /// Linked hidden translation document (`reader/split`); set on the original.
  IntColumn get translationDocumentId =>
      integer().nullable().references(Documents, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Personal vocabulary (`dictionary/entries`). [lemma] is normalized unique key.
class DictionaryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get lemma => text().unique()();
  TextColumn get translation => text()();
  TextColumn get context => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
