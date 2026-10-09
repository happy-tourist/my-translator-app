import 'package:flutter/material.dart';

import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_content_store_platform.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/features/upload/library_screen.dart';
import 'package:my_translator_app/features/vocab/vocabulary_screen.dart';

/// Product shell: Library (default) + Vocabulary.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.database,
    this.contentStore,
    this.folderRepository,
    this.documentRepository,
    this.dictionaryRepository,
  });

  final AppDatabase database;
  final DocumentContentStore? contentStore;
  final FolderRepository? folderRepository;
  final DocumentRepository? documentRepository;
  final DictionaryRepository? dictionaryRepository;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _index = 0;
  late final DocumentContentStore _store;
  late final FolderRepository _folders;
  late final DocumentRepository _documents;
  late final DictionaryRepository _dictionary;

  @override
  void initState() {
    super.initState();
    _store = widget.contentStore ?? createPlatformDocumentContentStore();
    _folders =
        widget.folderRepository ??
        FolderRepository(widget.database, contentStore: _store);
    _documents =
        widget.documentRepository ??
        DocumentRepository(widget.database, contentStore: _store);
    _dictionary =
        widget.dictionaryRepository ?? DictionaryRepository(widget.database);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      LibraryScreen(
        folderRepository: _folders,
        documentRepository: _documents,
      ),
      VocabularyScreen(dictionaryRepository: _dictionary),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Vocab',
          ),
        ],
      ),
    );
  }
}
