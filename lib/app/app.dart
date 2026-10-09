import 'package:flutter/material.dart';

import 'package:my_translator_app/app/shell.dart';
import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/database/database_provider.dart';

/// Root app: opens Drift after FRB init, then shows product shell.
class TranslationReaderApp extends StatefulWidget {
  const TranslationReaderApp({super.key});

  @override
  State<TranslationReaderApp> createState() => _TranslationReaderAppState();
}

class _TranslationReaderAppState extends State<TranslationReaderApp> {
  AppDatabase? _db;
  Object? _openError;
  var _opening = true;

  @override
  void initState() {
    super.initState();
    _openDb();
  }

  @override
  void dispose() {
    _db?.close();
    super.dispose();
  }

  Future<void> _openDb() async {
    // Avoid setState during initState: only refresh UI on retry / after await.
    if (_openError != null || !_opening) {
      setState(() {
        _opening = true;
        _openError = null;
      });
    }
    try {
      final db = await openAppDatabase();
      if (!mounted) {
        await db.close();
        return;
      }
      setState(() {
        _db = db;
        _opening = false;
        _openError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _openError = e;
        _opening = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Translation Reader',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_opening) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_openError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Could not open local storage. Check free space and try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _openDb,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return AppShell(database: _db!);
  }
}
