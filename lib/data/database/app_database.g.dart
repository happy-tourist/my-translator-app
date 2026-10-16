// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $FoldersTable extends Folders with TableInfo<$FoldersTable, Folder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<int> parentId = GeneratedColumn<int>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES folders (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    parentId,
    name,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<Folder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Folder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Folder(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parent_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class Folder extends DataClass implements Insertable<Folder> {
  final int id;
  final int? parentId;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Folder({
    required this.id,
    this.parentId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<int>(parentId);
    }
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Folder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Folder(
      id: serializer.fromJson<int>(json['id']),
      parentId: serializer.fromJson<int?>(json['parentId']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'parentId': serializer.toJson<int?>(parentId),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Folder copyWith({
    int? id,
    Value<int?> parentId = const Value.absent(),
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Folder(
    id: id ?? this.id,
    parentId: parentId.present ? parentId.value : this.parentId,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Folder copyWithCompanion(FoldersCompanion data) {
    return Folder(
      id: data.id.present ? data.id.value : this.id,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Folder(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, parentId, name, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Folder &&
          other.id == this.id &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class FoldersCompanion extends UpdateCompanion<Folder> {
  final Value<int> id;
  final Value<int?> parentId;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  FoldersCompanion.insert({
    this.id = const Value.absent(),
    this.parentId = const Value.absent(),
    required String name,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Folder> custom({
    Expression<int>? id,
    Expression<int>? parentId,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  FoldersCompanion copyWith({
    Value<int>? id,
    Value<int?>? parentId,
    Value<String>? name,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<int>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $DocumentsTable extends Documents
    with TableInfo<$DocumentsTable, Document> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<int> folderId = GeneratedColumn<int>(
    'folder_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES folders (id)',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storageKeyMeta = const VerificationMeta(
    'storageKey',
  );
  @override
  late final GeneratedColumn<String> storageKey = GeneratedColumn<String>(
    'storage_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _translationDocumentIdMeta =
      const VerificationMeta('translationDocumentId');
  @override
  late final GeneratedColumn<int> translationDocumentId = GeneratedColumn<int>(
    'translation_document_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES documents (id)',
    ),
  );
  static const VerificationMeta _lastReadStartMsMeta = const VerificationMeta(
    'lastReadStartMs',
  );
  @override
  late final GeneratedColumn<int> lastReadStartMs = GeneratedColumn<int>(
    'last_read_start_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastReadAlignmentMeta = const VerificationMeta(
    'lastReadAlignment',
  );
  @override
  late final GeneratedColumn<double> lastReadAlignment =
      GeneratedColumn<double>(
        'last_read_alignment',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _videoUriMeta = const VerificationMeta(
    'videoUri',
  );
  @override
  late final GeneratedColumn<String> videoUri = GeneratedColumn<String>(
    'video_uri',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _videoSandboxPathMeta = const VerificationMeta(
    'videoSandboxPath',
  );
  @override
  late final GeneratedColumn<String> videoSandboxPath = GeneratedColumn<String>(
    'video_sandbox_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _videoDurationSecMeta = const VerificationMeta(
    'videoDurationSec',
  );
  @override
  late final GeneratedColumn<int> videoDurationSec = GeneratedColumn<int>(
    'video_duration_sec',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _videoLastFramePageMeta =
      const VerificationMeta('videoLastFramePage');
  @override
  late final GeneratedColumn<int> videoLastFramePage = GeneratedColumn<int>(
    'video_last_frame_page',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    folderId,
    title,
    format,
    storageKey,
    content,
    translationDocumentId,
    lastReadStartMs,
    lastReadAlignment,
    videoUri,
    videoSandboxPath,
    videoDurationSec,
    videoLastFramePage,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<Document> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('storage_key')) {
      context.handle(
        _storageKeyMeta,
        storageKey.isAcceptableOrUnknown(data['storage_key']!, _storageKeyMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('translation_document_id')) {
      context.handle(
        _translationDocumentIdMeta,
        translationDocumentId.isAcceptableOrUnknown(
          data['translation_document_id']!,
          _translationDocumentIdMeta,
        ),
      );
    }
    if (data.containsKey('last_read_start_ms')) {
      context.handle(
        _lastReadStartMsMeta,
        lastReadStartMs.isAcceptableOrUnknown(
          data['last_read_start_ms']!,
          _lastReadStartMsMeta,
        ),
      );
    }
    if (data.containsKey('last_read_alignment')) {
      context.handle(
        _lastReadAlignmentMeta,
        lastReadAlignment.isAcceptableOrUnknown(
          data['last_read_alignment']!,
          _lastReadAlignmentMeta,
        ),
      );
    }
    if (data.containsKey('video_uri')) {
      context.handle(
        _videoUriMeta,
        videoUri.isAcceptableOrUnknown(data['video_uri']!, _videoUriMeta),
      );
    }
    if (data.containsKey('video_sandbox_path')) {
      context.handle(
        _videoSandboxPathMeta,
        videoSandboxPath.isAcceptableOrUnknown(
          data['video_sandbox_path']!,
          _videoSandboxPathMeta,
        ),
      );
    }
    if (data.containsKey('video_duration_sec')) {
      context.handle(
        _videoDurationSecMeta,
        videoDurationSec.isAcceptableOrUnknown(
          data['video_duration_sec']!,
          _videoDurationSecMeta,
        ),
      );
    }
    if (data.containsKey('video_last_frame_page')) {
      context.handle(
        _videoLastFramePageMeta,
        videoLastFramePage.isAcceptableOrUnknown(
          data['video_last_frame_page']!,
          _videoLastFramePageMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Document map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Document(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}folder_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
      storageKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_key'],
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      ),
      translationDocumentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}translation_document_id'],
      ),
      lastReadStartMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_read_start_ms'],
      ),
      lastReadAlignment: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}last_read_alignment'],
      ),
      videoUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_uri'],
      ),
      videoSandboxPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}video_sandbox_path'],
      ),
      videoDurationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}video_duration_sec'],
      ),
      videoLastFramePage: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}video_last_frame_page'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DocumentsTable createAlias(String alias) {
    return $DocumentsTable(attachedDatabase, alias);
  }
}

class Document extends DataClass implements Insertable<Document> {
  final int id;
  final int? folderId;
  final String title;

  /// One of: `srt`, `vtt`, `ass` (`.ssa` maps to `ass`).
  final String format;

  /// Native sandbox relative path / key; unused on Web when [content] is set.
  final String? storageKey;

  /// Inline file bytes/text for Web (and optional native fallback).
  final String? content;

  /// Linked hidden translation document (`reader/split`); set on the original.
  final int? translationDocumentId;

  /// Last reading position on the original (`library/documents` LD-17): cue start ms.
  final int? lastReadStartMs;

  /// Viewport alignment of the anchor row (`itemLeadingEdge`, 0.0…1.0).
  final double? lastReadAlignment;

  /// Durable platform ref / bookmark for attached video (`reader/video-frames`).
  final String? videoUri;

  /// Optional sandbox filesystem path for extract (native content:// copy).
  final String? videoSandboxPath;

  /// Probed duration in whole seconds (pagination); null when no video.
  final int? videoDurationSec;

  /// Optional last viewed frame-strip page (1-based).
  final int? videoLastFramePage;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Document({
    required this.id,
    this.folderId,
    required this.title,
    required this.format,
    this.storageKey,
    this.content,
    this.translationDocumentId,
    this.lastReadStartMs,
    this.lastReadAlignment,
    this.videoUri,
    this.videoSandboxPath,
    this.videoDurationSec,
    this.videoLastFramePage,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<int>(folderId);
    }
    map['title'] = Variable<String>(title);
    map['format'] = Variable<String>(format);
    if (!nullToAbsent || storageKey != null) {
      map['storage_key'] = Variable<String>(storageKey);
    }
    if (!nullToAbsent || content != null) {
      map['content'] = Variable<String>(content);
    }
    if (!nullToAbsent || translationDocumentId != null) {
      map['translation_document_id'] = Variable<int>(translationDocumentId);
    }
    if (!nullToAbsent || lastReadStartMs != null) {
      map['last_read_start_ms'] = Variable<int>(lastReadStartMs);
    }
    if (!nullToAbsent || lastReadAlignment != null) {
      map['last_read_alignment'] = Variable<double>(lastReadAlignment);
    }
    if (!nullToAbsent || videoUri != null) {
      map['video_uri'] = Variable<String>(videoUri);
    }
    if (!nullToAbsent || videoSandboxPath != null) {
      map['video_sandbox_path'] = Variable<String>(videoSandboxPath);
    }
    if (!nullToAbsent || videoDurationSec != null) {
      map['video_duration_sec'] = Variable<int>(videoDurationSec);
    }
    if (!nullToAbsent || videoLastFramePage != null) {
      map['video_last_frame_page'] = Variable<int>(videoLastFramePage);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DocumentsCompanion toCompanion(bool nullToAbsent) {
    return DocumentsCompanion(
      id: Value(id),
      folderId: folderId == null && nullToAbsent
          ? const Value.absent()
          : Value(folderId),
      title: Value(title),
      format: Value(format),
      storageKey: storageKey == null && nullToAbsent
          ? const Value.absent()
          : Value(storageKey),
      content: content == null && nullToAbsent
          ? const Value.absent()
          : Value(content),
      translationDocumentId: translationDocumentId == null && nullToAbsent
          ? const Value.absent()
          : Value(translationDocumentId),
      lastReadStartMs: lastReadStartMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadStartMs),
      lastReadAlignment: lastReadAlignment == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAlignment),
      videoUri: videoUri == null && nullToAbsent
          ? const Value.absent()
          : Value(videoUri),
      videoSandboxPath: videoSandboxPath == null && nullToAbsent
          ? const Value.absent()
          : Value(videoSandboxPath),
      videoDurationSec: videoDurationSec == null && nullToAbsent
          ? const Value.absent()
          : Value(videoDurationSec),
      videoLastFramePage: videoLastFramePage == null && nullToAbsent
          ? const Value.absent()
          : Value(videoLastFramePage),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Document.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Document(
      id: serializer.fromJson<int>(json['id']),
      folderId: serializer.fromJson<int?>(json['folderId']),
      title: serializer.fromJson<String>(json['title']),
      format: serializer.fromJson<String>(json['format']),
      storageKey: serializer.fromJson<String?>(json['storageKey']),
      content: serializer.fromJson<String?>(json['content']),
      translationDocumentId: serializer.fromJson<int?>(
        json['translationDocumentId'],
      ),
      lastReadStartMs: serializer.fromJson<int?>(json['lastReadStartMs']),
      lastReadAlignment: serializer.fromJson<double?>(
        json['lastReadAlignment'],
      ),
      videoUri: serializer.fromJson<String?>(json['videoUri']),
      videoSandboxPath: serializer.fromJson<String?>(json['videoSandboxPath']),
      videoDurationSec: serializer.fromJson<int?>(json['videoDurationSec']),
      videoLastFramePage: serializer.fromJson<int?>(json['videoLastFramePage']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'folderId': serializer.toJson<int?>(folderId),
      'title': serializer.toJson<String>(title),
      'format': serializer.toJson<String>(format),
      'storageKey': serializer.toJson<String?>(storageKey),
      'content': serializer.toJson<String?>(content),
      'translationDocumentId': serializer.toJson<int?>(translationDocumentId),
      'lastReadStartMs': serializer.toJson<int?>(lastReadStartMs),
      'lastReadAlignment': serializer.toJson<double?>(lastReadAlignment),
      'videoUri': serializer.toJson<String?>(videoUri),
      'videoSandboxPath': serializer.toJson<String?>(videoSandboxPath),
      'videoDurationSec': serializer.toJson<int?>(videoDurationSec),
      'videoLastFramePage': serializer.toJson<int?>(videoLastFramePage),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Document copyWith({
    int? id,
    Value<int?> folderId = const Value.absent(),
    String? title,
    String? format,
    Value<String?> storageKey = const Value.absent(),
    Value<String?> content = const Value.absent(),
    Value<int?> translationDocumentId = const Value.absent(),
    Value<int?> lastReadStartMs = const Value.absent(),
    Value<double?> lastReadAlignment = const Value.absent(),
    Value<String?> videoUri = const Value.absent(),
    Value<String?> videoSandboxPath = const Value.absent(),
    Value<int?> videoDurationSec = const Value.absent(),
    Value<int?> videoLastFramePage = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Document(
    id: id ?? this.id,
    folderId: folderId.present ? folderId.value : this.folderId,
    title: title ?? this.title,
    format: format ?? this.format,
    storageKey: storageKey.present ? storageKey.value : this.storageKey,
    content: content.present ? content.value : this.content,
    translationDocumentId: translationDocumentId.present
        ? translationDocumentId.value
        : this.translationDocumentId,
    lastReadStartMs: lastReadStartMs.present
        ? lastReadStartMs.value
        : this.lastReadStartMs,
    lastReadAlignment: lastReadAlignment.present
        ? lastReadAlignment.value
        : this.lastReadAlignment,
    videoUri: videoUri.present ? videoUri.value : this.videoUri,
    videoSandboxPath: videoSandboxPath.present
        ? videoSandboxPath.value
        : this.videoSandboxPath,
    videoDurationSec: videoDurationSec.present
        ? videoDurationSec.value
        : this.videoDurationSec,
    videoLastFramePage: videoLastFramePage.present
        ? videoLastFramePage.value
        : this.videoLastFramePage,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Document copyWithCompanion(DocumentsCompanion data) {
    return Document(
      id: data.id.present ? data.id.value : this.id,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      title: data.title.present ? data.title.value : this.title,
      format: data.format.present ? data.format.value : this.format,
      storageKey: data.storageKey.present
          ? data.storageKey.value
          : this.storageKey,
      content: data.content.present ? data.content.value : this.content,
      translationDocumentId: data.translationDocumentId.present
          ? data.translationDocumentId.value
          : this.translationDocumentId,
      lastReadStartMs: data.lastReadStartMs.present
          ? data.lastReadStartMs.value
          : this.lastReadStartMs,
      lastReadAlignment: data.lastReadAlignment.present
          ? data.lastReadAlignment.value
          : this.lastReadAlignment,
      videoUri: data.videoUri.present ? data.videoUri.value : this.videoUri,
      videoSandboxPath: data.videoSandboxPath.present
          ? data.videoSandboxPath.value
          : this.videoSandboxPath,
      videoDurationSec: data.videoDurationSec.present
          ? data.videoDurationSec.value
          : this.videoDurationSec,
      videoLastFramePage: data.videoLastFramePage.present
          ? data.videoLastFramePage.value
          : this.videoLastFramePage,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Document(')
          ..write('id: $id, ')
          ..write('folderId: $folderId, ')
          ..write('title: $title, ')
          ..write('format: $format, ')
          ..write('storageKey: $storageKey, ')
          ..write('content: $content, ')
          ..write('translationDocumentId: $translationDocumentId, ')
          ..write('lastReadStartMs: $lastReadStartMs, ')
          ..write('lastReadAlignment: $lastReadAlignment, ')
          ..write('videoUri: $videoUri, ')
          ..write('videoSandboxPath: $videoSandboxPath, ')
          ..write('videoDurationSec: $videoDurationSec, ')
          ..write('videoLastFramePage: $videoLastFramePage, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    folderId,
    title,
    format,
    storageKey,
    content,
    translationDocumentId,
    lastReadStartMs,
    lastReadAlignment,
    videoUri,
    videoSandboxPath,
    videoDurationSec,
    videoLastFramePage,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Document &&
          other.id == this.id &&
          other.folderId == this.folderId &&
          other.title == this.title &&
          other.format == this.format &&
          other.storageKey == this.storageKey &&
          other.content == this.content &&
          other.translationDocumentId == this.translationDocumentId &&
          other.lastReadStartMs == this.lastReadStartMs &&
          other.lastReadAlignment == this.lastReadAlignment &&
          other.videoUri == this.videoUri &&
          other.videoSandboxPath == this.videoSandboxPath &&
          other.videoDurationSec == this.videoDurationSec &&
          other.videoLastFramePage == this.videoLastFramePage &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DocumentsCompanion extends UpdateCompanion<Document> {
  final Value<int> id;
  final Value<int?> folderId;
  final Value<String> title;
  final Value<String> format;
  final Value<String?> storageKey;
  final Value<String?> content;
  final Value<int?> translationDocumentId;
  final Value<int?> lastReadStartMs;
  final Value<double?> lastReadAlignment;
  final Value<String?> videoUri;
  final Value<String?> videoSandboxPath;
  final Value<int?> videoDurationSec;
  final Value<int?> videoLastFramePage;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const DocumentsCompanion({
    this.id = const Value.absent(),
    this.folderId = const Value.absent(),
    this.title = const Value.absent(),
    this.format = const Value.absent(),
    this.storageKey = const Value.absent(),
    this.content = const Value.absent(),
    this.translationDocumentId = const Value.absent(),
    this.lastReadStartMs = const Value.absent(),
    this.lastReadAlignment = const Value.absent(),
    this.videoUri = const Value.absent(),
    this.videoSandboxPath = const Value.absent(),
    this.videoDurationSec = const Value.absent(),
    this.videoLastFramePage = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  DocumentsCompanion.insert({
    this.id = const Value.absent(),
    this.folderId = const Value.absent(),
    required String title,
    required String format,
    this.storageKey = const Value.absent(),
    this.content = const Value.absent(),
    this.translationDocumentId = const Value.absent(),
    this.lastReadStartMs = const Value.absent(),
    this.lastReadAlignment = const Value.absent(),
    this.videoUri = const Value.absent(),
    this.videoSandboxPath = const Value.absent(),
    this.videoDurationSec = const Value.absent(),
    this.videoLastFramePage = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : title = Value(title),
       format = Value(format);
  static Insertable<Document> custom({
    Expression<int>? id,
    Expression<int>? folderId,
    Expression<String>? title,
    Expression<String>? format,
    Expression<String>? storageKey,
    Expression<String>? content,
    Expression<int>? translationDocumentId,
    Expression<int>? lastReadStartMs,
    Expression<double>? lastReadAlignment,
    Expression<String>? videoUri,
    Expression<String>? videoSandboxPath,
    Expression<int>? videoDurationSec,
    Expression<int>? videoLastFramePage,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (folderId != null) 'folder_id': folderId,
      if (title != null) 'title': title,
      if (format != null) 'format': format,
      if (storageKey != null) 'storage_key': storageKey,
      if (content != null) 'content': content,
      if (translationDocumentId != null)
        'translation_document_id': translationDocumentId,
      if (lastReadStartMs != null) 'last_read_start_ms': lastReadStartMs,
      if (lastReadAlignment != null) 'last_read_alignment': lastReadAlignment,
      if (videoUri != null) 'video_uri': videoUri,
      if (videoSandboxPath != null) 'video_sandbox_path': videoSandboxPath,
      if (videoDurationSec != null) 'video_duration_sec': videoDurationSec,
      if (videoLastFramePage != null)
        'video_last_frame_page': videoLastFramePage,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  DocumentsCompanion copyWith({
    Value<int>? id,
    Value<int?>? folderId,
    Value<String>? title,
    Value<String>? format,
    Value<String?>? storageKey,
    Value<String?>? content,
    Value<int?>? translationDocumentId,
    Value<int?>? lastReadStartMs,
    Value<double?>? lastReadAlignment,
    Value<String?>? videoUri,
    Value<String?>? videoSandboxPath,
    Value<int?>? videoDurationSec,
    Value<int?>? videoLastFramePage,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return DocumentsCompanion(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      format: format ?? this.format,
      storageKey: storageKey ?? this.storageKey,
      content: content ?? this.content,
      translationDocumentId:
          translationDocumentId ?? this.translationDocumentId,
      lastReadStartMs: lastReadStartMs ?? this.lastReadStartMs,
      lastReadAlignment: lastReadAlignment ?? this.lastReadAlignment,
      videoUri: videoUri ?? this.videoUri,
      videoSandboxPath: videoSandboxPath ?? this.videoSandboxPath,
      videoDurationSec: videoDurationSec ?? this.videoDurationSec,
      videoLastFramePage: videoLastFramePage ?? this.videoLastFramePage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<int>(folderId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (storageKey.present) {
      map['storage_key'] = Variable<String>(storageKey.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (translationDocumentId.present) {
      map['translation_document_id'] = Variable<int>(
        translationDocumentId.value,
      );
    }
    if (lastReadStartMs.present) {
      map['last_read_start_ms'] = Variable<int>(lastReadStartMs.value);
    }
    if (lastReadAlignment.present) {
      map['last_read_alignment'] = Variable<double>(lastReadAlignment.value);
    }
    if (videoUri.present) {
      map['video_uri'] = Variable<String>(videoUri.value);
    }
    if (videoSandboxPath.present) {
      map['video_sandbox_path'] = Variable<String>(videoSandboxPath.value);
    }
    if (videoDurationSec.present) {
      map['video_duration_sec'] = Variable<int>(videoDurationSec.value);
    }
    if (videoLastFramePage.present) {
      map['video_last_frame_page'] = Variable<int>(videoLastFramePage.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentsCompanion(')
          ..write('id: $id, ')
          ..write('folderId: $folderId, ')
          ..write('title: $title, ')
          ..write('format: $format, ')
          ..write('storageKey: $storageKey, ')
          ..write('content: $content, ')
          ..write('translationDocumentId: $translationDocumentId, ')
          ..write('lastReadStartMs: $lastReadStartMs, ')
          ..write('lastReadAlignment: $lastReadAlignment, ')
          ..write('videoUri: $videoUri, ')
          ..write('videoSandboxPath: $videoSandboxPath, ')
          ..write('videoDurationSec: $videoDurationSec, ')
          ..write('videoLastFramePage: $videoLastFramePage, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $DictionaryEntriesTable extends DictionaryEntries
    with TableInfo<$DictionaryEntriesTable, DictionaryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DictionaryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _lemmaMeta = const VerificationMeta('lemma');
  @override
  late final GeneratedColumn<String> lemma = GeneratedColumn<String>(
    'lemma',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _surfaceKeyMeta = const VerificationMeta(
    'surfaceKey',
  );
  @override
  late final GeneratedColumn<String> surfaceKey = GeneratedColumn<String>(
    'surface_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _translationMeta = const VerificationMeta(
    'translation',
  );
  @override
  late final GeneratedColumn<String> translation = GeneratedColumn<String>(
    'translation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contextMeta = const VerificationMeta(
    'context',
  );
  @override
  late final GeneratedColumn<String> context = GeneratedColumn<String>(
    'context',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    lemma,
    surfaceKey,
    translation,
    context,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dictionary_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<DictionaryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('lemma')) {
      context.handle(
        _lemmaMeta,
        lemma.isAcceptableOrUnknown(data['lemma']!, _lemmaMeta),
      );
    } else if (isInserting) {
      context.missing(_lemmaMeta);
    }
    if (data.containsKey('surface_key')) {
      context.handle(
        _surfaceKeyMeta,
        surfaceKey.isAcceptableOrUnknown(data['surface_key']!, _surfaceKeyMeta),
      );
    }
    if (data.containsKey('translation')) {
      context.handle(
        _translationMeta,
        translation.isAcceptableOrUnknown(
          data['translation']!,
          _translationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_translationMeta);
    }
    if (data.containsKey('context')) {
      context.handle(
        _contextMeta,
        this.context.isAcceptableOrUnknown(data['context']!, _contextMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DictionaryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DictionaryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      lemma: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lemma'],
      )!,
      surfaceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}surface_key'],
      ),
      translation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}translation'],
      )!,
      context: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DictionaryEntriesTable createAlias(String alias) {
    return $DictionaryEntriesTable(attachedDatabase, alias);
  }
}

class DictionaryEntry extends DataClass implements Insertable<DictionaryEntry> {
  final int id;
  final String lemma;

  /// Casefold surface / legacy stub key (not unique). Null until stub→morph migrate.
  final String? surfaceKey;
  final String translation;
  final String? context;
  final DateTime createdAt;
  final DateTime updatedAt;
  const DictionaryEntry({
    required this.id,
    required this.lemma,
    this.surfaceKey,
    required this.translation,
    this.context,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['lemma'] = Variable<String>(lemma);
    if (!nullToAbsent || surfaceKey != null) {
      map['surface_key'] = Variable<String>(surfaceKey);
    }
    map['translation'] = Variable<String>(translation);
    if (!nullToAbsent || context != null) {
      map['context'] = Variable<String>(context);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DictionaryEntriesCompanion toCompanion(bool nullToAbsent) {
    return DictionaryEntriesCompanion(
      id: Value(id),
      lemma: Value(lemma),
      surfaceKey: surfaceKey == null && nullToAbsent
          ? const Value.absent()
          : Value(surfaceKey),
      translation: Value(translation),
      context: context == null && nullToAbsent
          ? const Value.absent()
          : Value(context),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DictionaryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DictionaryEntry(
      id: serializer.fromJson<int>(json['id']),
      lemma: serializer.fromJson<String>(json['lemma']),
      surfaceKey: serializer.fromJson<String?>(json['surfaceKey']),
      translation: serializer.fromJson<String>(json['translation']),
      context: serializer.fromJson<String?>(json['context']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'lemma': serializer.toJson<String>(lemma),
      'surfaceKey': serializer.toJson<String?>(surfaceKey),
      'translation': serializer.toJson<String>(translation),
      'context': serializer.toJson<String?>(context),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DictionaryEntry copyWith({
    int? id,
    String? lemma,
    Value<String?> surfaceKey = const Value.absent(),
    String? translation,
    Value<String?> context = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => DictionaryEntry(
    id: id ?? this.id,
    lemma: lemma ?? this.lemma,
    surfaceKey: surfaceKey.present ? surfaceKey.value : this.surfaceKey,
    translation: translation ?? this.translation,
    context: context.present ? context.value : this.context,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DictionaryEntry copyWithCompanion(DictionaryEntriesCompanion data) {
    return DictionaryEntry(
      id: data.id.present ? data.id.value : this.id,
      lemma: data.lemma.present ? data.lemma.value : this.lemma,
      surfaceKey: data.surfaceKey.present
          ? data.surfaceKey.value
          : this.surfaceKey,
      translation: data.translation.present
          ? data.translation.value
          : this.translation,
      context: data.context.present ? data.context.value : this.context,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DictionaryEntry(')
          ..write('id: $id, ')
          ..write('lemma: $lemma, ')
          ..write('surfaceKey: $surfaceKey, ')
          ..write('translation: $translation, ')
          ..write('context: $context, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    lemma,
    surfaceKey,
    translation,
    context,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DictionaryEntry &&
          other.id == this.id &&
          other.lemma == this.lemma &&
          other.surfaceKey == this.surfaceKey &&
          other.translation == this.translation &&
          other.context == this.context &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DictionaryEntriesCompanion extends UpdateCompanion<DictionaryEntry> {
  final Value<int> id;
  final Value<String> lemma;
  final Value<String?> surfaceKey;
  final Value<String> translation;
  final Value<String?> context;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const DictionaryEntriesCompanion({
    this.id = const Value.absent(),
    this.lemma = const Value.absent(),
    this.surfaceKey = const Value.absent(),
    this.translation = const Value.absent(),
    this.context = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  DictionaryEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String lemma,
    this.surfaceKey = const Value.absent(),
    required String translation,
    this.context = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : lemma = Value(lemma),
       translation = Value(translation);
  static Insertable<DictionaryEntry> custom({
    Expression<int>? id,
    Expression<String>? lemma,
    Expression<String>? surfaceKey,
    Expression<String>? translation,
    Expression<String>? context,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lemma != null) 'lemma': lemma,
      if (surfaceKey != null) 'surface_key': surfaceKey,
      if (translation != null) 'translation': translation,
      if (context != null) 'context': context,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  DictionaryEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? lemma,
    Value<String?>? surfaceKey,
    Value<String>? translation,
    Value<String?>? context,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return DictionaryEntriesCompanion(
      id: id ?? this.id,
      lemma: lemma ?? this.lemma,
      surfaceKey: surfaceKey ?? this.surfaceKey,
      translation: translation ?? this.translation,
      context: context ?? this.context,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (lemma.present) {
      map['lemma'] = Variable<String>(lemma.value);
    }
    if (surfaceKey.present) {
      map['surface_key'] = Variable<String>(surfaceKey.value);
    }
    if (translation.present) {
      map['translation'] = Variable<String>(translation.value);
    }
    if (context.present) {
      map['context'] = Variable<String>(context.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DictionaryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('lemma: $lemma, ')
          ..write('surfaceKey: $surfaceKey, ')
          ..write('translation: $translation, ')
          ..write('context: $context, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $DocumentVideoFramesTable extends DocumentVideoFrames
    with TableInfo<$DocumentVideoFramesTable, DocumentVideoFrame> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentVideoFramesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<int> documentId = GeneratedColumn<int>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES documents (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _secondMeta = const VerificationMeta('second');
  @override
  late final GeneratedColumn<int> second = GeneratedColumn<int>(
    'second',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jpegBytesMeta = const VerificationMeta(
    'jpegBytes',
  );
  @override
  late final GeneratedColumn<Uint8List> jpegBytes = GeneratedColumn<Uint8List>(
    'jpeg_bytes',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [documentId, second, jpegBytes];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'document_video_frames';
  @override
  VerificationContext validateIntegrity(
    Insertable<DocumentVideoFrame> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('second')) {
      context.handle(
        _secondMeta,
        second.isAcceptableOrUnknown(data['second']!, _secondMeta),
      );
    } else if (isInserting) {
      context.missing(_secondMeta);
    }
    if (data.containsKey('jpeg_bytes')) {
      context.handle(
        _jpegBytesMeta,
        jpegBytes.isAcceptableOrUnknown(data['jpeg_bytes']!, _jpegBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_jpegBytesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {documentId, second};
  @override
  DocumentVideoFrame map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DocumentVideoFrame(
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}document_id'],
      )!,
      second: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}second'],
      )!,
      jpegBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}jpeg_bytes'],
      )!,
    );
  }

  @override
  $DocumentVideoFramesTable createAlias(String alias) {
    return $DocumentVideoFramesTable(attachedDatabase, alias);
  }
}

class DocumentVideoFrame extends DataClass
    implements Insertable<DocumentVideoFrame> {
  final int documentId;

  /// Whole-second index (0-based) within the attached video.
  final int second;
  final Uint8List jpegBytes;
  const DocumentVideoFrame({
    required this.documentId,
    required this.second,
    required this.jpegBytes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<int>(documentId);
    map['second'] = Variable<int>(second);
    map['jpeg_bytes'] = Variable<Uint8List>(jpegBytes);
    return map;
  }

  DocumentVideoFramesCompanion toCompanion(bool nullToAbsent) {
    return DocumentVideoFramesCompanion(
      documentId: Value(documentId),
      second: Value(second),
      jpegBytes: Value(jpegBytes),
    );
  }

  factory DocumentVideoFrame.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DocumentVideoFrame(
      documentId: serializer.fromJson<int>(json['documentId']),
      second: serializer.fromJson<int>(json['second']),
      jpegBytes: serializer.fromJson<Uint8List>(json['jpegBytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<int>(documentId),
      'second': serializer.toJson<int>(second),
      'jpegBytes': serializer.toJson<Uint8List>(jpegBytes),
    };
  }

  DocumentVideoFrame copyWith({
    int? documentId,
    int? second,
    Uint8List? jpegBytes,
  }) => DocumentVideoFrame(
    documentId: documentId ?? this.documentId,
    second: second ?? this.second,
    jpegBytes: jpegBytes ?? this.jpegBytes,
  );
  DocumentVideoFrame copyWithCompanion(DocumentVideoFramesCompanion data) {
    return DocumentVideoFrame(
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      second: data.second.present ? data.second.value : this.second,
      jpegBytes: data.jpegBytes.present ? data.jpegBytes.value : this.jpegBytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DocumentVideoFrame(')
          ..write('documentId: $documentId, ')
          ..write('second: $second, ')
          ..write('jpegBytes: $jpegBytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(documentId, second, $driftBlobEquality.hash(jpegBytes));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DocumentVideoFrame &&
          other.documentId == this.documentId &&
          other.second == this.second &&
          $driftBlobEquality.equals(other.jpegBytes, this.jpegBytes));
}

class DocumentVideoFramesCompanion extends UpdateCompanion<DocumentVideoFrame> {
  final Value<int> documentId;
  final Value<int> second;
  final Value<Uint8List> jpegBytes;
  final Value<int> rowid;
  const DocumentVideoFramesCompanion({
    this.documentId = const Value.absent(),
    this.second = const Value.absent(),
    this.jpegBytes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DocumentVideoFramesCompanion.insert({
    required int documentId,
    required int second,
    required Uint8List jpegBytes,
    this.rowid = const Value.absent(),
  }) : documentId = Value(documentId),
       second = Value(second),
       jpegBytes = Value(jpegBytes);
  static Insertable<DocumentVideoFrame> custom({
    Expression<int>? documentId,
    Expression<int>? second,
    Expression<Uint8List>? jpegBytes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (second != null) 'second': second,
      if (jpegBytes != null) 'jpeg_bytes': jpegBytes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DocumentVideoFramesCompanion copyWith({
    Value<int>? documentId,
    Value<int>? second,
    Value<Uint8List>? jpegBytes,
    Value<int>? rowid,
  }) {
    return DocumentVideoFramesCompanion(
      documentId: documentId ?? this.documentId,
      second: second ?? this.second,
      jpegBytes: jpegBytes ?? this.jpegBytes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<int>(documentId.value);
    }
    if (second.present) {
      map['second'] = Variable<int>(second.value);
    }
    if (jpegBytes.present) {
      map['jpeg_bytes'] = Variable<Uint8List>(jpegBytes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentVideoFramesCompanion(')
          ..write('documentId: $documentId, ')
          ..write('second: $second, ')
          ..write('jpegBytes: $jpegBytes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DocumentVideoMediaTable extends DocumentVideoMedia
    with TableInfo<$DocumentVideoMediaTable, DocumentVideoMediaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentVideoMediaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<int> documentId = GeneratedColumn<int>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES documents (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [documentId, bytes, fileName];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'document_video_media';
  @override
  VerificationContext validateIntegrity(
    Insertable<DocumentVideoMediaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {documentId};
  @override
  DocumentVideoMediaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DocumentVideoMediaData(
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}document_id'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
    );
  }

  @override
  $DocumentVideoMediaTable createAlias(String alias) {
    return $DocumentVideoMediaTable(attachedDatabase, alias);
  }
}

class DocumentVideoMediaData extends DataClass
    implements Insertable<DocumentVideoMediaData> {
  final int documentId;
  final Uint8List bytes;
  final String fileName;
  const DocumentVideoMediaData({
    required this.documentId,
    required this.bytes,
    required this.fileName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<int>(documentId);
    map['bytes'] = Variable<Uint8List>(bytes);
    map['file_name'] = Variable<String>(fileName);
    return map;
  }

  DocumentVideoMediaCompanion toCompanion(bool nullToAbsent) {
    return DocumentVideoMediaCompanion(
      documentId: Value(documentId),
      bytes: Value(bytes),
      fileName: Value(fileName),
    );
  }

  factory DocumentVideoMediaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DocumentVideoMediaData(
      documentId: serializer.fromJson<int>(json['documentId']),
      bytes: serializer.fromJson<Uint8List>(json['bytes']),
      fileName: serializer.fromJson<String>(json['fileName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<int>(documentId),
      'bytes': serializer.toJson<Uint8List>(bytes),
      'fileName': serializer.toJson<String>(fileName),
    };
  }

  DocumentVideoMediaData copyWith({
    int? documentId,
    Uint8List? bytes,
    String? fileName,
  }) => DocumentVideoMediaData(
    documentId: documentId ?? this.documentId,
    bytes: bytes ?? this.bytes,
    fileName: fileName ?? this.fileName,
  );
  DocumentVideoMediaData copyWithCompanion(DocumentVideoMediaCompanion data) {
    return DocumentVideoMediaData(
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DocumentVideoMediaData(')
          ..write('documentId: $documentId, ')
          ..write('bytes: $bytes, ')
          ..write('fileName: $fileName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(documentId, $driftBlobEquality.hash(bytes), fileName);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DocumentVideoMediaData &&
          other.documentId == this.documentId &&
          $driftBlobEquality.equals(other.bytes, this.bytes) &&
          other.fileName == this.fileName);
}

class DocumentVideoMediaCompanion
    extends UpdateCompanion<DocumentVideoMediaData> {
  final Value<int> documentId;
  final Value<Uint8List> bytes;
  final Value<String> fileName;
  const DocumentVideoMediaCompanion({
    this.documentId = const Value.absent(),
    this.bytes = const Value.absent(),
    this.fileName = const Value.absent(),
  });
  DocumentVideoMediaCompanion.insert({
    this.documentId = const Value.absent(),
    required Uint8List bytes,
    required String fileName,
  }) : bytes = Value(bytes),
       fileName = Value(fileName);
  static Insertable<DocumentVideoMediaData> custom({
    Expression<int>? documentId,
    Expression<Uint8List>? bytes,
    Expression<String>? fileName,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (bytes != null) 'bytes': bytes,
      if (fileName != null) 'file_name': fileName,
    });
  }

  DocumentVideoMediaCompanion copyWith({
    Value<int>? documentId,
    Value<Uint8List>? bytes,
    Value<String>? fileName,
  }) {
    return DocumentVideoMediaCompanion(
      documentId: documentId ?? this.documentId,
      bytes: bytes ?? this.bytes,
      fileName: fileName ?? this.fileName,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<int>(documentId.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentVideoMediaCompanion(')
          ..write('documentId: $documentId, ')
          ..write('bytes: $bytes, ')
          ..write('fileName: $fileName')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FoldersTable folders = $FoldersTable(this);
  late final $DocumentsTable documents = $DocumentsTable(this);
  late final $DictionaryEntriesTable dictionaryEntries =
      $DictionaryEntriesTable(this);
  late final $DocumentVideoFramesTable documentVideoFrames =
      $DocumentVideoFramesTable(this);
  late final $DocumentVideoMediaTable documentVideoMedia =
      $DocumentVideoMediaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    folders,
    documents,
    dictionaryEntries,
    documentVideoFrames,
    documentVideoMedia,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'documents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('document_video_frames', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'documents',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('document_video_media', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$FoldersTableCreateCompanionBuilder = FoldersCompanion Function({
  Value<int> id,
  Value<int?> parentId,
  required String name,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$FoldersTableUpdateCompanionBuilder = FoldersCompanion Function({
  Value<int> id,
  Value<int?> parentId,
  Value<String> name,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

final class $$FoldersTableReferences
    extends BaseReferences<_$AppDatabase, $FoldersTable, Folder> {
  $$FoldersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FoldersTable _parentIdTable(_$AppDatabase db) =>
      db.folders.createAlias('folders__parent_id__folders__id');

  $$FoldersTableProcessedTableManager? get parentId {
    final $_column = $_itemColumn<int>('parent_id');
    if ($_column == null) return null;
    final manager = $$FoldersTableTableManager(
      $_db,
      $_db.folders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$DocumentsTable, List<Document>>
  _documentsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.documents,
    aliasName: 'folders__id__documents__folder_id',
  );

  $$DocumentsTableProcessedTableManager get documentsRefs {
    final manager = $$DocumentsTableTableManager(
      $_db,
      $_db.documents,
    ).filter((f) => f.folderId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_documentsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FoldersTableFilterComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$FoldersTableFilterComposer get parentId {
    final $$FoldersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableFilterComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> documentsRefs(
    Expression<bool> Function($$DocumentsTableFilterComposer f) f,
  ) {
    final $$DocumentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableFilterComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FoldersTableOrderingComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$FoldersTableOrderingComposer get parentId {
    final $$FoldersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableOrderingComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoldersTableAnnotationComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$FoldersTableAnnotationComposer get parentId {
    final $$FoldersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableAnnotationComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> documentsRefs<T extends Object>(
    Expression<T> Function($$DocumentsTableAnnotationComposer a) f,
  ) {
    final $$DocumentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableAnnotationComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FoldersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FoldersTable,
          Folder,
          $$FoldersTableFilterComposer,
          $$FoldersTableOrderingComposer,
          $$FoldersTableAnnotationComposer,
          $$FoldersTableCreateCompanionBuilder,
          $$FoldersTableUpdateCompanionBuilder,
          (Folder, $$FoldersTableReferences),
          Folder,
          PrefetchHooks Function({bool parentId, bool documentsRefs})
        > {
  $$FoldersTableTableManager(_$AppDatabase db, $FoldersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> parentId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                parentId: parentId,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> parentId = const Value.absent(),
                required String name,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => FoldersCompanion.insert(
                id: id,
                parentId: parentId,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FoldersTable, Folder>(table),
                  $$FoldersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({parentId = false, documentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (documentsRefs) db.documents],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (parentId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.parentId,
                        referencedTable: $$FoldersTableReferences
                            ._parentIdTable(db),
                        referencedColumn: $$FoldersTableReferences
                            ._parentIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (documentsRefs)
                    await $_getPrefetchedData<Folder, $FoldersTable, Document>(
                      currentTable: table,
                      referencedTable: $$FoldersTableReferences
                          ._documentsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$FoldersTableReferences(db, table, p0).documentsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.folderId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$FoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FoldersTable,
      Folder,
      $$FoldersTableFilterComposer,
      $$FoldersTableOrderingComposer,
      $$FoldersTableAnnotationComposer,
      $$FoldersTableCreateCompanionBuilder,
      $$FoldersTableUpdateCompanionBuilder,
      (Folder, $$FoldersTableReferences),
      Folder,
      PrefetchHooks Function({bool parentId, bool documentsRefs})
    >;
typedef $$DocumentsTableCreateCompanionBuilder = DocumentsCompanion Function({
  Value<int> id,
  Value<int?> folderId,
  required String title,
  required String format,
  Value<String?> storageKey,
  Value<String?> content,
  Value<int?> translationDocumentId,
  Value<int?> lastReadStartMs,
  Value<double?> lastReadAlignment,
  Value<String?> videoUri,
  Value<String?> videoSandboxPath,
  Value<int?> videoDurationSec,
  Value<int?> videoLastFramePage,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});
typedef $$DocumentsTableUpdateCompanionBuilder = DocumentsCompanion Function({
  Value<int> id,
  Value<int?> folderId,
  Value<String> title,
  Value<String> format,
  Value<String?> storageKey,
  Value<String?> content,
  Value<int?> translationDocumentId,
  Value<int?> lastReadStartMs,
  Value<double?> lastReadAlignment,
  Value<String?> videoUri,
  Value<String?> videoSandboxPath,
  Value<int?> videoDurationSec,
  Value<int?> videoLastFramePage,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

final class $$DocumentsTableReferences
    extends BaseReferences<_$AppDatabase, $DocumentsTable, Document> {
  $$DocumentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FoldersTable _folderIdTable(_$AppDatabase db) =>
      db.folders.createAlias('documents__folder_id__folders__id');

  $$FoldersTableProcessedTableManager? get folderId {
    final $_column = $_itemColumn<int>('folder_id');
    if ($_column == null) return null;
    final manager = $$FoldersTableTableManager(
      $_db,
      $_db.folders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_folderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $DocumentsTable _translationDocumentIdTable(_$AppDatabase db) => db
      .documents
      .createAlias('documents__translation_document_id__documents__id');

  $$DocumentsTableProcessedTableManager? get translationDocumentId {
    final $_column = $_itemColumn<int>('translation_document_id');
    if ($_column == null) return null;
    final manager = $$DocumentsTableTableManager(
      $_db,
      $_db.documents,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(
      _translationDocumentIdTable($_db),
    );
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $DocumentVideoFramesTable,
    List<DocumentVideoFrame>
  >
  _documentVideoFramesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.documentVideoFrames,
        aliasName: 'documents__id__document_video_frames__document_id',
      );

  $$DocumentVideoFramesTableProcessedTableManager get documentVideoFramesRefs {
    final manager = $$DocumentVideoFramesTableTableManager(
      $_db,
      $_db.documentVideoFrames,
    ).filter((f) => f.documentId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _documentVideoFramesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $DocumentVideoMediaTable,
    List<DocumentVideoMediaData>
  >
  _documentVideoMediaRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.documentVideoMedia,
        aliasName: 'documents__id__document_video_media__document_id',
      );

  $$DocumentVideoMediaTableProcessedTableManager get documentVideoMediaRefs {
    final manager = $$DocumentVideoMediaTableTableManager(
      $_db,
      $_db.documentVideoMedia,
    ).filter((f) => f.documentId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _documentVideoMediaRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DocumentsTableFilterComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReadStartMs => $composableBuilder(
    column: $table.lastReadStartMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lastReadAlignment => $composableBuilder(
    column: $table.lastReadAlignment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get videoUri => $composableBuilder(
    column: $table.videoUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get videoSandboxPath => $composableBuilder(
    column: $table.videoSandboxPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get videoDurationSec => $composableBuilder(
    column: $table.videoDurationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get videoLastFramePage => $composableBuilder(
    column: $table.videoLastFramePage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$FoldersTableFilterComposer get folderId {
    final $$FoldersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableFilterComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$DocumentsTableFilterComposer get translationDocumentId {
    final $$DocumentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.translationDocumentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableFilterComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> documentVideoFramesRefs(
    Expression<bool> Function($$DocumentVideoFramesTableFilterComposer f) f,
  ) {
    final $$DocumentVideoFramesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.documentVideoFrames,
      getReferencedColumn: (t) => t.documentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentVideoFramesTableFilterComposer(
            $db: $db,
            $table: $db.documentVideoFrames,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> documentVideoMediaRefs(
    Expression<bool> Function($$DocumentVideoMediaTableFilterComposer f) f,
  ) {
    final $$DocumentVideoMediaTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.documentVideoMedia,
      getReferencedColumn: (t) => t.documentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentVideoMediaTableFilterComposer(
            $db: $db,
            $table: $db.documentVideoMedia,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DocumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReadStartMs => $composableBuilder(
    column: $table.lastReadStartMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lastReadAlignment => $composableBuilder(
    column: $table.lastReadAlignment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get videoUri => $composableBuilder(
    column: $table.videoUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get videoSandboxPath => $composableBuilder(
    column: $table.videoSandboxPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get videoDurationSec => $composableBuilder(
    column: $table.videoDurationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get videoLastFramePage => $composableBuilder(
    column: $table.videoLastFramePage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$FoldersTableOrderingComposer get folderId {
    final $$FoldersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableOrderingComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$DocumentsTableOrderingComposer get translationDocumentId {
    final $$DocumentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.translationDocumentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableOrderingComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<String> get storageKey => $composableBuilder(
    column: $table.storageKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get lastReadStartMs => $composableBuilder(
    column: $table.lastReadStartMs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get lastReadAlignment => $composableBuilder(
    column: $table.lastReadAlignment,
    builder: (column) => column,
  );

  GeneratedColumn<String> get videoUri =>
      $composableBuilder(column: $table.videoUri, builder: (column) => column);

  GeneratedColumn<String> get videoSandboxPath => $composableBuilder(
    column: $table.videoSandboxPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get videoDurationSec => $composableBuilder(
    column: $table.videoDurationSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get videoLastFramePage => $composableBuilder(
    column: $table.videoLastFramePage,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$FoldersTableAnnotationComposer get folderId {
    final $$FoldersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableAnnotationComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$DocumentsTableAnnotationComposer get translationDocumentId {
    final $$DocumentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.translationDocumentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableAnnotationComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> documentVideoFramesRefs<T extends Object>(
    Expression<T> Function($$DocumentVideoFramesTableAnnotationComposer a) f,
  ) {
    final $$DocumentVideoFramesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.documentVideoFrames,
          getReferencedColumn: (t) => t.documentId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DocumentVideoFramesTableAnnotationComposer(
                $db: $db,
                $table: $db.documentVideoFrames,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> documentVideoMediaRefs<T extends Object>(
    Expression<T> Function($$DocumentVideoMediaTableAnnotationComposer a) f,
  ) {
    final $$DocumentVideoMediaTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.documentVideoMedia,
          getReferencedColumn: (t) => t.documentId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DocumentVideoMediaTableAnnotationComposer(
                $db: $db,
                $table: $db.documentVideoMedia,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$DocumentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DocumentsTable,
          Document,
          $$DocumentsTableFilterComposer,
          $$DocumentsTableOrderingComposer,
          $$DocumentsTableAnnotationComposer,
          $$DocumentsTableCreateCompanionBuilder,
          $$DocumentsTableUpdateCompanionBuilder,
          (Document, $$DocumentsTableReferences),
          Document,
          PrefetchHooks Function({
            bool folderId,
            bool translationDocumentId,
            bool documentVideoFramesRefs,
            bool documentVideoMediaRefs,
          })
        > {
  $$DocumentsTableTableManager(_$AppDatabase db, $DocumentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> folderId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<String?> storageKey = const Value.absent(),
                Value<String?> content = const Value.absent(),
                Value<int?> translationDocumentId = const Value.absent(),
                Value<int?> lastReadStartMs = const Value.absent(),
                Value<double?> lastReadAlignment = const Value.absent(),
                Value<String?> videoUri = const Value.absent(),
                Value<String?> videoSandboxPath = const Value.absent(),
                Value<int?> videoDurationSec = const Value.absent(),
                Value<int?> videoLastFramePage = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DocumentsCompanion(
                id: id,
                folderId: folderId,
                title: title,
                format: format,
                storageKey: storageKey,
                content: content,
                translationDocumentId: translationDocumentId,
                lastReadStartMs: lastReadStartMs,
                lastReadAlignment: lastReadAlignment,
                videoUri: videoUri,
                videoSandboxPath: videoSandboxPath,
                videoDurationSec: videoDurationSec,
                videoLastFramePage: videoLastFramePage,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> folderId = const Value.absent(),
                required String title,
                required String format,
                Value<String?> storageKey = const Value.absent(),
                Value<String?> content = const Value.absent(),
                Value<int?> translationDocumentId = const Value.absent(),
                Value<int?> lastReadStartMs = const Value.absent(),
                Value<double?> lastReadAlignment = const Value.absent(),
                Value<String?> videoUri = const Value.absent(),
                Value<String?> videoSandboxPath = const Value.absent(),
                Value<int?> videoDurationSec = const Value.absent(),
                Value<int?> videoLastFramePage = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DocumentsCompanion.insert(
                id: id,
                folderId: folderId,
                title: title,
                format: format,
                storageKey: storageKey,
                content: content,
                translationDocumentId: translationDocumentId,
                lastReadStartMs: lastReadStartMs,
                lastReadAlignment: lastReadAlignment,
                videoUri: videoUri,
                videoSandboxPath: videoSandboxPath,
                videoDurationSec: videoDurationSec,
                videoLastFramePage: videoLastFramePage,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DocumentsTable, Document>(table),
                  $$DocumentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                folderId = false,
                translationDocumentId = false,
                documentVideoFramesRefs = false,
                documentVideoMediaRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (documentVideoFramesRefs) db.documentVideoFrames,
                    if (documentVideoMediaRefs) db.documentVideoMedia,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (folderId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.folderId,
                            referencedTable: $$DocumentsTableReferences
                                ._folderIdTable(db),
                            referencedColumn: $$DocumentsTableReferences
                                ._folderIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (translationDocumentId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.translationDocumentId,
                            referencedTable: $$DocumentsTableReferences
                                ._translationDocumentIdTable(db),
                            referencedColumn: $$DocumentsTableReferences
                                ._translationDocumentIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (documentVideoFramesRefs)
                        await $_getPrefetchedData<
                          Document,
                          $DocumentsTable,
                          DocumentVideoFrame
                        >(
                          currentTable: table,
                          referencedTable: $$DocumentsTableReferences
                              ._documentVideoFramesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DocumentsTableReferences(
                                db,
                                table,
                                p0,
                              ).documentVideoFramesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.documentId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (documentVideoMediaRefs)
                        await $_getPrefetchedData<
                          Document,
                          $DocumentsTable,
                          DocumentVideoMediaData
                        >(
                          currentTable: table,
                          referencedTable: $$DocumentsTableReferences
                              ._documentVideoMediaRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DocumentsTableReferences(
                                db,
                                table,
                                p0,
                              ).documentVideoMediaRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.documentId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$DocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DocumentsTable,
      Document,
      $$DocumentsTableFilterComposer,
      $$DocumentsTableOrderingComposer,
      $$DocumentsTableAnnotationComposer,
      $$DocumentsTableCreateCompanionBuilder,
      $$DocumentsTableUpdateCompanionBuilder,
      (Document, $$DocumentsTableReferences),
      Document,
      PrefetchHooks Function({
        bool folderId,
        bool translationDocumentId,
        bool documentVideoFramesRefs,
        bool documentVideoMediaRefs,
      })
    >;
typedef $$DictionaryEntriesTableCreateCompanionBuilder =
    DictionaryEntriesCompanion Function({
      Value<int> id,
      required String lemma,
      Value<String?> surfaceKey,
      required String translation,
      Value<String?> context,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$DictionaryEntriesTableUpdateCompanionBuilder =
    DictionaryEntriesCompanion Function({
      Value<int> id,
      Value<String> lemma,
      Value<String?> surfaceKey,
      Value<String> translation,
      Value<String?> context,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$DictionaryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $DictionaryEntriesTable> {
  $$DictionaryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lemma => $composableBuilder(
    column: $table.lemma,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get surfaceKey => $composableBuilder(
    column: $table.surfaceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get translation => $composableBuilder(
    column: $table.translation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get context => $composableBuilder(
    column: $table.context,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DictionaryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $DictionaryEntriesTable> {
  $$DictionaryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lemma => $composableBuilder(
    column: $table.lemma,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get surfaceKey => $composableBuilder(
    column: $table.surfaceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get translation => $composableBuilder(
    column: $table.translation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get context => $composableBuilder(
    column: $table.context,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DictionaryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DictionaryEntriesTable> {
  $$DictionaryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get lemma =>
      $composableBuilder(column: $table.lemma, builder: (column) => column);

  GeneratedColumn<String> get surfaceKey => $composableBuilder(
    column: $table.surfaceKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get translation => $composableBuilder(
    column: $table.translation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get context =>
      $composableBuilder(column: $table.context, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DictionaryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DictionaryEntriesTable,
          DictionaryEntry,
          $$DictionaryEntriesTableFilterComposer,
          $$DictionaryEntriesTableOrderingComposer,
          $$DictionaryEntriesTableAnnotationComposer,
          $$DictionaryEntriesTableCreateCompanionBuilder,
          $$DictionaryEntriesTableUpdateCompanionBuilder,
          (
            DictionaryEntry,
            BaseReferences<
              _$AppDatabase,
              $DictionaryEntriesTable,
              DictionaryEntry
            >,
          ),
          DictionaryEntry,
          PrefetchHooks Function()
        > {
  $$DictionaryEntriesTableTableManager(
    _$AppDatabase db,
    $DictionaryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DictionaryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DictionaryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DictionaryEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> lemma = const Value.absent(),
                Value<String?> surfaceKey = const Value.absent(),
                Value<String> translation = const Value.absent(),
                Value<String?> context = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DictionaryEntriesCompanion(
                id: id,
                lemma: lemma,
                surfaceKey: surfaceKey,
                translation: translation,
                context: context,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String lemma,
                Value<String?> surfaceKey = const Value.absent(),
                required String translation,
                Value<String?> context = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DictionaryEntriesCompanion.insert(
                id: id,
                lemma: lemma,
                surfaceKey: surfaceKey,
                translation: translation,
                context: context,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DictionaryEntriesTable, DictionaryEntry>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $DictionaryEntriesTable,
                    DictionaryEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DictionaryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DictionaryEntriesTable,
      DictionaryEntry,
      $$DictionaryEntriesTableFilterComposer,
      $$DictionaryEntriesTableOrderingComposer,
      $$DictionaryEntriesTableAnnotationComposer,
      $$DictionaryEntriesTableCreateCompanionBuilder,
      $$DictionaryEntriesTableUpdateCompanionBuilder,
      (
        DictionaryEntry,
        BaseReferences<_$AppDatabase, $DictionaryEntriesTable, DictionaryEntry>,
      ),
      DictionaryEntry,
      PrefetchHooks Function()
    >;
typedef $$DocumentVideoFramesTableCreateCompanionBuilder =
    DocumentVideoFramesCompanion Function({
      required int documentId,
      required int second,
      required Uint8List jpegBytes,
      Value<int> rowid,
    });
typedef $$DocumentVideoFramesTableUpdateCompanionBuilder =
    DocumentVideoFramesCompanion Function({
      Value<int> documentId,
      Value<int> second,
      Value<Uint8List> jpegBytes,
      Value<int> rowid,
    });

final class $$DocumentVideoFramesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $DocumentVideoFramesTable,
          DocumentVideoFrame
        > {
  $$DocumentVideoFramesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DocumentsTable _documentIdTable(_$AppDatabase db) => db.documents
      .createAlias('document_video_frames__document_id__documents__id');

  $$DocumentsTableProcessedTableManager get documentId {
    final $_column = $_itemColumn<int>('document_id')!;

    final manager = $$DocumentsTableTableManager(
      $_db,
      $_db.documents,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_documentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DocumentVideoFramesTableFilterComposer
    extends Composer<_$AppDatabase, $DocumentVideoFramesTable> {
  $$DocumentVideoFramesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get second => $composableBuilder(
    column: $table.second,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get jpegBytes => $composableBuilder(
    column: $table.jpegBytes,
    builder: (column) => ColumnFilters(column),
  );

  $$DocumentsTableFilterComposer get documentId {
    final $$DocumentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableFilterComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentVideoFramesTableOrderingComposer
    extends Composer<_$AppDatabase, $DocumentVideoFramesTable> {
  $$DocumentVideoFramesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get second => $composableBuilder(
    column: $table.second,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get jpegBytes => $composableBuilder(
    column: $table.jpegBytes,
    builder: (column) => ColumnOrderings(column),
  );

  $$DocumentsTableOrderingComposer get documentId {
    final $$DocumentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableOrderingComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentVideoFramesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DocumentVideoFramesTable> {
  $$DocumentVideoFramesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get second =>
      $composableBuilder(column: $table.second, builder: (column) => column);

  GeneratedColumn<Uint8List> get jpegBytes =>
      $composableBuilder(column: $table.jpegBytes, builder: (column) => column);

  $$DocumentsTableAnnotationComposer get documentId {
    final $$DocumentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableAnnotationComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentVideoFramesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DocumentVideoFramesTable,
          DocumentVideoFrame,
          $$DocumentVideoFramesTableFilterComposer,
          $$DocumentVideoFramesTableOrderingComposer,
          $$DocumentVideoFramesTableAnnotationComposer,
          $$DocumentVideoFramesTableCreateCompanionBuilder,
          $$DocumentVideoFramesTableUpdateCompanionBuilder,
          (DocumentVideoFrame, $$DocumentVideoFramesTableReferences),
          DocumentVideoFrame,
          PrefetchHooks Function({bool documentId})
        > {
  $$DocumentVideoFramesTableTableManager(
    _$AppDatabase db,
    $DocumentVideoFramesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentVideoFramesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocumentVideoFramesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DocumentVideoFramesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> documentId = const Value.absent(),
                Value<int> second = const Value.absent(),
                Value<Uint8List> jpegBytes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocumentVideoFramesCompanion(
                documentId: documentId,
                second: second,
                jpegBytes: jpegBytes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int documentId,
                required int second,
                required Uint8List jpegBytes,
                Value<int> rowid = const Value.absent(),
              }) => DocumentVideoFramesCompanion.insert(
                documentId: documentId,
                second: second,
                jpegBytes: jpegBytes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DocumentVideoFramesTable, DocumentVideoFrame>(
                    table,
                  ),
                  $$DocumentVideoFramesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({documentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (documentId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.documentId,
                        referencedTable: $$DocumentVideoFramesTableReferences
                            ._documentIdTable(db),
                        referencedColumn: $$DocumentVideoFramesTableReferences
                            ._documentIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DocumentVideoFramesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DocumentVideoFramesTable,
      DocumentVideoFrame,
      $$DocumentVideoFramesTableFilterComposer,
      $$DocumentVideoFramesTableOrderingComposer,
      $$DocumentVideoFramesTableAnnotationComposer,
      $$DocumentVideoFramesTableCreateCompanionBuilder,
      $$DocumentVideoFramesTableUpdateCompanionBuilder,
      (DocumentVideoFrame, $$DocumentVideoFramesTableReferences),
      DocumentVideoFrame,
      PrefetchHooks Function({bool documentId})
    >;
typedef $$DocumentVideoMediaTableCreateCompanionBuilder =
    DocumentVideoMediaCompanion Function({
      Value<int> documentId,
      required Uint8List bytes,
      required String fileName,
    });
typedef $$DocumentVideoMediaTableUpdateCompanionBuilder =
    DocumentVideoMediaCompanion Function({
      Value<int> documentId,
      Value<Uint8List> bytes,
      Value<String> fileName,
    });

final class $$DocumentVideoMediaTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $DocumentVideoMediaTable,
          DocumentVideoMediaData
        > {
  $$DocumentVideoMediaTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DocumentsTable _documentIdTable(_$AppDatabase db) => db.documents
      .createAlias('document_video_media__document_id__documents__id');

  $$DocumentsTableProcessedTableManager get documentId {
    final $_column = $_itemColumn<int>('document_id')!;

    final manager = $$DocumentsTableTableManager(
      $_db,
      $_db.documents,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_documentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DocumentVideoMediaTableFilterComposer
    extends Composer<_$AppDatabase, $DocumentVideoMediaTable> {
  $$DocumentVideoMediaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  $$DocumentsTableFilterComposer get documentId {
    final $$DocumentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableFilterComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentVideoMediaTableOrderingComposer
    extends Composer<_$AppDatabase, $DocumentVideoMediaTable> {
  $$DocumentVideoMediaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  $$DocumentsTableOrderingComposer get documentId {
    final $$DocumentsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableOrderingComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentVideoMediaTableAnnotationComposer
    extends Composer<_$AppDatabase, $DocumentVideoMediaTable> {
  $$DocumentVideoMediaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  $$DocumentsTableAnnotationComposer get documentId {
    final $$DocumentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.documentId,
      referencedTable: $db.documents,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DocumentsTableAnnotationComposer(
            $db: $db,
            $table: $db.documents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DocumentVideoMediaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DocumentVideoMediaTable,
          DocumentVideoMediaData,
          $$DocumentVideoMediaTableFilterComposer,
          $$DocumentVideoMediaTableOrderingComposer,
          $$DocumentVideoMediaTableAnnotationComposer,
          $$DocumentVideoMediaTableCreateCompanionBuilder,
          $$DocumentVideoMediaTableUpdateCompanionBuilder,
          (DocumentVideoMediaData, $$DocumentVideoMediaTableReferences),
          DocumentVideoMediaData,
          PrefetchHooks Function({bool documentId})
        > {
  $$DocumentVideoMediaTableTableManager(
    _$AppDatabase db,
    $DocumentVideoMediaTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentVideoMediaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocumentVideoMediaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocumentVideoMediaTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> documentId = const Value.absent(),
                Value<Uint8List> bytes = const Value.absent(),
                Value<String> fileName = const Value.absent(),
              }) => DocumentVideoMediaCompanion(
                documentId: documentId,
                bytes: bytes,
                fileName: fileName,
              ),
          createCompanionCallback:
              ({
                Value<int> documentId = const Value.absent(),
                required Uint8List bytes,
                required String fileName,
              }) => DocumentVideoMediaCompanion.insert(
                documentId: documentId,
                bytes: bytes,
                fileName: fileName,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DocumentVideoMediaTable, DocumentVideoMediaData>(
                    table,
                  ),
                  $$DocumentVideoMediaTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({documentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (documentId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.documentId,
                        referencedTable: $$DocumentVideoMediaTableReferences
                            ._documentIdTable(db),
                        referencedColumn: $$DocumentVideoMediaTableReferences
                            ._documentIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DocumentVideoMediaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DocumentVideoMediaTable,
      DocumentVideoMediaData,
      $$DocumentVideoMediaTableFilterComposer,
      $$DocumentVideoMediaTableOrderingComposer,
      $$DocumentVideoMediaTableAnnotationComposer,
      $$DocumentVideoMediaTableCreateCompanionBuilder,
      $$DocumentVideoMediaTableUpdateCompanionBuilder,
      (DocumentVideoMediaData, $$DocumentVideoMediaTableReferences),
      DocumentVideoMediaData,
      PrefetchHooks Function({bool documentId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
  $$DocumentsTableTableManager get documents =>
      $$DocumentsTableTableManager(_db, _db.documents);
  $$DictionaryEntriesTableTableManager get dictionaryEntries =>
      $$DictionaryEntriesTableTableManager(_db, _db.dictionaryEntries);
  $$DocumentVideoFramesTableTableManager get documentVideoFrames =>
      $$DocumentVideoFramesTableTableManager(_db, _db.documentVideoFrames);
  $$DocumentVideoMediaTableTableManager get documentVideoMedia =>
      $$DocumentVideoMediaTableTableManager(_db, _db.documentVideoMedia);
}
