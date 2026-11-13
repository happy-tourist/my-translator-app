import 'dart:async';

import 'package:flutter/material.dart';

import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';
import 'package:my_translator_app/data/dictionary/lemma_keys_for_surfaces_fn.dart';
import 'package:my_translator_app/data/library/document_content_store.dart';
import 'package:my_translator_app/data/library/document_content_store_platform.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/data/translate/offline_translate.dart';
import 'package:my_translator_app/data/translate/offline_translate_platform.dart';
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
    this.offlineTranslate,
    this.enableOfflineTranslateWarmUp = true,
  });

  final AppDatabase database;
  final DocumentContentStore? contentStore;
  final FolderRepository? folderRepository;
  final DocumentRepository? documentRepository;
  final DictionaryRepository? dictionaryRepository;
  final LemmaKeysForSurfacesFn? lemmaKeysForSurfaces;
  final OfflineTranslateFn? offlineTranslate;

  /// Production default: fullscreen warm-up gate ON (design D1).
  /// Tests set `false` and/or inject [offlineTranslate] to skip AssetBundle/FRB load
  /// and the gate entirely (shell is interactive immediately).
  final bool enableOfflineTranslateWarmUp;

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
  /// One facade for Vocab + Reader (design D4.1).
  late final OfflineTranslateFn _offlineTranslate;
  /// Fullscreen gate state (design D1 / TO-09 / TO-13): product shell
  /// (Library/Vocab) is not built/interactive until this flips true.
  var _gateDone = false;

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
    _offlineTranslate =
        widget.offlineTranslate ?? createPlatformOfflineTranslate();

    // Design D1 / TO-09: after Drift open (AppShell build), block the product
    // shell behind a fullscreen loading gate until ensure/warm-up settles.
    // Escape hatch: disabled flag and/or injectable translate → skip the gate
    // entirely so tests never wait on AssetBundle/FRB load.
    final shouldWarmUp = widget.enableOfflineTranslateWarmUp &&
        widget.offlineTranslate == null;
    if (shouldWarmUp) {
      unawaited(_runWarmUpGate());
    } else {
      _gateDone = true;
    }
  }

  Future<void> _runWarmUpGate() async {
    // Quiet (D6 / TO-13): [warmUpOfflineTranslate] swallows init errors — the
    // gate is dismissed either way (success or fail), no SnackBar from here.
    await warmUpOfflineTranslate();
    if (!mounted) return;
    setState(() => _gateDone = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_gateDone) {
      // Fullscreen loading gate (design D1 / TO-09): Library/Vocab and the
      // bottom nav are not built — product shell is not interactive yet.
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final pages = <Widget>[
      LibraryScreen(
        folderRepository: _folders,
        documentRepository: _documents,
        dictionaryRepository: _dictionary,
        offlineTranslate: _offlineTranslate,
      ),
      VocabularyScreen(
        dictionaryRepository: _dictionary,
        lemmaKeysForSurfaces: _lemmaKeysForSurfaces,
        offlineTranslate: _offlineTranslate,
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
