import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Folders, Documents, DictionaryEntries, DocumentVideoFrames],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// Opens the shared app database (native file or Web wasm/worker).
  factory AppDatabase.connect() => AppDatabase(_openConnection());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(
          documents,
          documents.translationDocumentId,
        );
      }
      if (from < 3) {
        await migrator.addColumn(documents, documents.lastReadStartMs);
        await migrator.addColumn(documents, documents.lastReadAlignment);
      }
      // Schema 4: DDL only — morph rewrite is post-open migrateStubKeysIfNeeded.
      if (from < 4) {
        await migrator.addColumn(
          dictionaryEntries,
          dictionaryEntries.surfaceKey,
        );
      }
      // Schema 5: video attachment meta on original + JPEG frame cache table.
      if (from < 5) {
        await migrator.addColumn(documents, documents.videoUri);
        await migrator.addColumn(documents, documents.videoSandboxPath);
        await migrator.addColumn(documents, documents.videoDurationSec);
        await migrator.addColumn(documents, documents.videoLastFramePage);
        await migrator.createTable(documentVideoFrames);
      }
    },
  );
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'translation_reader',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}
