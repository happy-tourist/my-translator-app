import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PanicException;

import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/library/document_repository.dart';
import 'package:my_translator_app/data/library/folder_repository.dart';
import 'package:my_translator_app/data/library/library_exceptions.dart';
import 'package:my_translator_app/features/reader/reader_screen.dart';
import 'package:my_translator_app/src/rust/api/parse.dart' as rust_parse;

/// Picked file payload for injectable import (tests / file_picker).
class PickedLibraryFile {
  const PickedLibraryFile({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

typedef LibraryFilePicker = Future<PickedLibraryFile?> Function();

/// Injectable FRB parse seam for widget tests (frb-boundary).
typedef ParseSubtitlesFn =
    Future<rust_parse.ParsedSubtitles> Function({
      required List<int> bytes,
      String? formatHint,
    });

/// Minimal library UI: folder nav, create, import, cascade delete confirm (D8).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.folderRepository,
    required this.documentRepository,
    this.filePicker,
    this.parseSubtitles,
  });

  final FolderRepository folderRepository;
  final DocumentRepository documentRepository;
  final LibraryFilePicker? filePicker;

  /// Defaults to generated FRB [rust_parse.parseSubtitles].
  final ParseSubtitlesFn? parseSubtitles;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final List<Folder> _path = [];
  List<Folder> _folders = const [];
  List<Document> _documents = const [];
  var _loading = true;
  var _opening = false;
  String? _listError;

  int? get _currentFolderId => _path.isEmpty ? null : _path.last.id;

  ParseSubtitlesFn get _parse =>
      widget.parseSubtitles ?? rust_parse.parseSubtitles;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _listError = null;
    });
    try {
      final folders = await widget.folderRepository.listChildren(
        _currentFolderId,
      );
      final documents = _currentFolderId == null
          ? <Document>[]
          : await widget.documentRepository.listInFolder(_currentFolderId!);
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _documents = documents;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _listError = 'Could not load library';
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(key: const Key('libraryErrorSnack'), content: Text(message)),
    );
  }

  String _messageForParseError(rust_parse.ParseErrorKind kind) {
    switch (kind) {
      case rust_parse.ParseErrorKind.unsupportedFormat:
        return 'Unsupported or unrecognized subtitle format';
      case rust_parse.ParseErrorKind.encoding:
        return 'File encoding is not valid UTF-8';
      case rust_parse.ParseErrorKind.empty:
        return 'No subtitle cues found in this file';
      case rust_parse.ParseErrorKind.malformed:
        return 'Could not parse this subtitle file';
    }
  }

  Future<void> _createFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => const _CreateFolderDialog(),
    );
    if (name == null || !mounted) return;
    try {
      await widget.folderRepository.createFolder(
        name: name,
        parentId: _currentFolderId,
      );
      await _reload();
    } on LibraryValidationException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Could not create folder');
    }
  }

  Future<void> _importFile() async {
    if (_currentFolderId == null) return;
    try {
      final picked = widget.filePicker != null
          ? await widget.filePicker!()
          : await _defaultPick();
      if (picked == null || !mounted) return;
      await widget.documentRepository.importIntoFolder(
        folderId: _currentFolderId,
        fileName: picked.fileName,
        bytes: picked.bytes,
      );
      if (!mounted) return;
      await _reload();
    } on LibraryValidationException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Could not import file');
    }
  }

  Future<PickedLibraryFile?> _defaultPick() async {
    // file_picker 13+: static pickFiles; bytes via readAsBytes().
    // Allow any type so unsupported extensions reach validation (LD-03).
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return null;
    final file = files.first;
    final bytes = await file.readAsBytes();
    return PickedLibraryFile(fileName: file.name, bytes: bytes);
  }

  Future<void> _confirmDeleteFolder(Folder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          key: const Key('libraryCascadeDeleteDialog'),
          title: const Text('Delete folder?'),
          content: Text(
            'Delete "${folder.name}" and all nested folders and documents?',
          ),
          actions: [
            TextButton(
              key: const Key('libraryCascadeDeleteCancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('libraryCascadeDeleteConfirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.folderRepository.deleteFolderCascade(folder.id);
      if (!mounted) return;
      await _reload();
    } on LibraryValidationException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Could not delete folder');
    }
  }

  Future<void> _confirmDeleteDocument(Document doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete document?'),
          content: Text('Delete "${doc.title}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.documentRepository.deleteDocument(doc.id);
      if (!mounted) return;
      await _reload();
    } on LibraryValidationException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Could not delete document');
    }
  }

  void _openFolder(Folder folder) {
    setState(() => _path.add(folder));
    _reload();
  }

  void _goUp() {
    if (_path.isEmpty) return;
    setState(() => _path.removeLast());
    _reload();
  }

  Future<void> _onDocumentTap(Document doc) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final bytes = await widget.documentRepository.loadBytes(doc);
      if (!mounted) return;
      final parsed = await _parse(bytes: bytes, formatHint: doc.format);
      if (!mounted) return;
      // RC-05 / D4: never push Reader with zero cues (Rust should Err Empty).
      if (parsed.cues.isEmpty) {
        _showError(_messageForParseError(rust_parse.ParseErrorKind.empty));
        return;
      }
      setState(() => _opening = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(title: doc.title, cues: parsed.cues),
        ),
      );
    } on rust_parse.ParseErrorKind catch (kind) {
      if (!mounted) return;
      _showError(_messageForParseError(kind));
    } on PanicException catch (e) {
      assert(() {
        debugPrint('Rust panic opening document: ${e.message}');
        return true;
      }());
      if (!mounted) return;
      _showError('Could not load document');
    } catch (e, st) {
      assert(() {
        debugPrint('Open document failed: $e\n$st');
        return true;
      }());
      if (!mounted) return;
      _showError('Could not load document');
    } finally {
      if (mounted && _opening) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _path.isEmpty
        ? 'Library'
        : _path.map((f) => f.name).join(' / ');
    final isEmpty = !_loading && _folders.isEmpty && _documents.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: _path.isEmpty
            ? null
            : IconButton(
                key: const Key('libraryGoUp'),
                icon: const Icon(Icons.arrow_back),
                onPressed: _goUp,
              ),
        actions: [
          IconButton(
            key: const Key('libraryCreateFolderButton'),
            tooltip: 'Create folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _createFolder,
          ),
          if (_currentFolderId != null)
            IconButton(
              key: const Key('libraryImportButton'),
              tooltip: 'Import subtitle',
              icon: const Icon(Icons.file_upload_outlined),
              onPressed: _importFile,
            ),
        ],
      ),
      body: _buildBody(isEmpty),
    );
  }

  Widget _buildBody(bool isEmpty) {
    if (_loading) {
      return const Center(
        key: Key('libraryLoading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_listError != null) {
      return Center(
        key: const Key('libraryListError'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_listError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _reload, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (isEmpty) {
      return Center(
        key: const Key('libraryEmpty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This folder is empty'),
              const SizedBox(height: 12),
              ElevatedButton(
                key: const Key('libraryEmptyCreateFolder'),
                onPressed: _createFolder,
                child: const Text('Create folder'),
              ),
            ],
          ),
        ),
      );
    }
    // Non-wiping open overlay (design D5): keep list visible under progress.
    return Stack(
      children: [
        ListView(
          key: const Key('libraryList'),
          children: [
            ..._folders.map(
              (folder) => ListTile(
                key: Key('libraryFolder_${folder.id}'),
                leading: const Icon(Icons.folder),
                title: Text(folder.name),
                onTap: () => _openFolder(folder),
                trailing: IconButton(
                  key: Key('libraryDeleteFolder_${folder.id}'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDeleteFolder(folder),
                ),
              ),
            ),
            ..._documents.map(
              (doc) => ListTile(
                key: Key('libraryDocument_${doc.id}'),
                leading: const Icon(Icons.description_outlined),
                title: Text(doc.title),
                subtitle: Text(doc.format),
                onTap: () => _onDocumentTap(doc),
                trailing: IconButton(
                  key: Key('libraryDeleteDocument_${doc.id}'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDeleteDocument(doc),
                ),
              ),
            ),
          ],
        ),
        if (_opening) ...[
          ModalBarrier(
            dismissible: false,
            color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.2),
          ),
          const Center(
            key: Key('libraryOpening'),
            child: CircularProgressIndicator(),
          ),
        ],
      ],
    );
  }
}

class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog();

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New folder'),
      content: TextField(
        key: const Key('libraryFolderNameField'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Folder name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('libraryCreateFolderConfirm'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
