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
  /// Last reading position on the original (`library/documents` LD-17): cue start ms.
  IntColumn get lastReadStartMs => integer().nullable()();
  /// Viewport alignment of the anchor row (`itemLeadingEdge`, 0.0…1.0).
  RealColumn get lastReadAlignment => real().nullable()();
  /// Durable platform ref / bookmark for attached video (`reader/video-frames`).
  TextColumn get videoUri => text().nullable()();
  /// Optional sandbox filesystem path for extract (native content:// copy).
  TextColumn get videoSandboxPath => text().nullable()();
  /// Probed duration in whole seconds (pagination); null when no video.
  IntColumn get videoDurationSec => integer().nullable()();
  /// Optional last viewed frame-strip page (1-based).
  IntColumn get videoLastFramePage => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// JPEG frame cache for visited video seconds (`library/documents` LD-20).
///
/// Drift BLOB on all platforms (native + Web); keyed by document + second.
class DocumentVideoFrames extends Table {
  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  /// Whole-second index (0-based) within the attached video.
  IntColumn get second => integer()();
  BlobColumn get jpegBytes => blob()();

  @override
  Set<Column> get primaryKey => {documentId, second};
}

/// Full video file bytes for durable reopen (esp. Web — blob URLs die on reload).
///
/// Native MAY also store a sandbox file path on [Documents.videoSandboxPath];
/// Web restores a session object URL from these bytes.
class DocumentVideoMedia extends Table {
  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  BlobColumn get bytes => blob()();
  TextColumn get fileName => text()();

  @override
  Set<Column> get primaryKey => {documentId};
}

/// Personal vocabulary (`dictionary/entries`).
/// [lemma] = morph identity (UNIQUE); [surfaceKey] = casefold surface / legacy stub.
class DictionaryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get lemma => text().unique()();
  /// Casefold surface / legacy stub key (not unique). Null until stub→morph migrate.
  TextColumn get surfaceKey => text().nullable()();
  TextColumn get translation => text()();
  TextColumn get context => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
