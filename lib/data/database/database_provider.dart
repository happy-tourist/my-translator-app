import 'app_database.dart';

/// Opens [AppDatabase] and runs a lightweight readiness check (schema access).
Future<AppDatabase> openAppDatabase() async {
  final db = AppDatabase.connect();
  // Touch the connection so open failures surface before UI leaves loading.
  await db.customSelect('SELECT 1').get();
  return db;
}
