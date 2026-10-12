import 'package:flutter/material.dart';

import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';
import 'package:my_translator_app/data/dictionary/lemma_keys_for_surfaces_fn.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_content_store_platform.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/features/upload/library_screen.dart';
import 'package:my_translator_app/features/vocab/vocabulary_screen.dart';
import 'package:my_translator_app/src/rust/api/tokenize.dart' as rust_tokenize;

/// Product shell: Library (default) + Vocabulary.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.database,
    this.contentStore,
    this.folderRepository,
    this.documentRepository,
    this.dictionaryRepository,
    this.lemmaKeysForSurfaces,
  });

  final AppDatabase database;
  final DocumentContentStore? contentStore;
  final FolderRepository? folderRepository;
  final DocumentRepository? documentRepository;
  final DictionaryRepository? dictionaryRepository;
  final LemmaKeysForSurfacesFn? lemmaKeysForSurfaces;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _index = 0;
  late final DocumentContentStore _store;
  late final FolderRepository _folders;
  late final DocumentRepository _documents;
  late final DictionaryRepository _dictionary;
  late final LemmaKeysForSurfacesFn _lemmaKeysForSurfaces;

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
    _lemmaKeysForSurfaces =
        widget.lemmaKeysForSurfaces ??
        ((surfaces) => rust_tokenize.lemmaKeysForSurfaces(surfaces: surfaces));
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      LibraryScreen(
        folderRepository: _folders,
        documentRepository: _documents,
        dictionaryRepository: _dictionary,
      ),
      VocabularyScreen(
        dictionaryRepository: _dictionary,
        lemmaKeysForSurfaces: _lemmaKeysForSurfaces,
      ),
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
