import 'dart:io';

import 'package:drift/native.dart';
import 'package:my_translator_app/data/database/app_database.dart';

/// In-memory Drift DB for unit/widget tests.
AppDatabase createTestDatabase() => AppDatabase(NativeDatabase.memory());

/// File-backed Drift DB for close/reopen persistence tests (LD-06 / DE-08).
AppDatabase createFileTestDatabase(File file) =>
    AppDatabase(NativeDatabase(file));
