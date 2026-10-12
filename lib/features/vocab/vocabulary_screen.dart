import 'package:flutter/material.dart';

import 'package:my_translator_app/data/database/app_database.dart';
import 'package:my_translator_app/data/dictionary/dictionary_exceptions.dart';
import 'package:my_translator_app/data/dictionary/dictionary_repository.dart';
import 'package:my_translator_app/data/dictionary/lemma_keys_for_surfaces_fn.dart';
import 'package:my_translator_app/src/rust/api/tokenize.dart' as rust_tokenize;

/// Minimal vocabulary UI: empty add form, list, delete (design D8 / D5.1).
class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({
    super.key,
    required this.dictionaryRepository,
    this.lemmaKeysForSurfaces,
  });

  final DictionaryRepository dictionaryRepository;

  /// Morph keys for manual add. Defaults to generated FRB.
  final LemmaKeysForSurfacesFn? lemmaKeysForSurfaces;

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  final _lemmaController = TextEditingController();
  final _translationController = TextEditingController();
  final _contextController = TextEditingController();

  List<DictionaryEntry> _entries = const [];
  var _loading = true;
  String? _listError;
  String? _formError;

  LemmaKeysForSurfacesFn get _lemmaKeysForSurfaces =>
      widget.lemmaKeysForSurfaces ??
      ((surfaces) => rust_tokenize.lemmaKeysForSurfaces(surfaces: surfaces));

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _lemmaController.dispose();
    _translationController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _listError = null;
    });
    try {
      final entries = await widget.dictionaryRepository.list();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _listError = 'Could not load vocabulary';
      });
    }
  }

  Future<void> _addEntry() async {
    setState(() => _formError = null);
    try {
      final input = _lemmaController.text;
      final surfaceKey = DictionaryRepository.normalizeSurface(input);
      // D5.1: multi-word typed input → casefold identity (no WordNet).
      final String lemma;
      if (surfaceKey.contains(RegExp(r'\s'))) {
        lemma = surfaceKey;
      } else {
        final keys = await _lemmaKeysForSurfaces([input]);
        if (!mounted) return;
        lemma = keys.isEmpty ? '' : keys.first;
      }
      if (!mounted) return;
      await widget.dictionaryRepository.add(
        lemma: lemma,
        surfaceKey: surfaceKey,
        translation: _translationController.text,
        context: _contextController.text,
      );
      if (!mounted) return;
      _lemmaController.clear();
      _translationController.clear();
      _contextController.clear();
      await _reload();
    } on DictionaryValidationException catch (e) {
      if (!mounted) return;
      setState(() => _formError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _formError = 'Could not add entry');
    }
  }

  Future<void> _confirmDelete(DictionaryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          key: const Key('vocabDeleteDialog'),
          title: const Text('Delete entry?'),
          content: Text('Delete "${entry.lemma}"?'),
          actions: [
            TextButton(
              key: const Key('vocabDeleteCancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('vocabDeleteConfirm'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await widget.dictionaryRepository.remove(entry.id);
      await _reload();
    } on DictionaryValidationException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not delete entry')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vocabulary')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: Key('vocabLoading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_listError != null) {
      return Center(
        key: const Key('vocabListError'),
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: _AddEntryForm(
            lemmaController: _lemmaController,
            translationController: _translationController,
            contextController: _contextController,
            formError: _formError,
            onSubmit: _addEntry,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _entries.isEmpty
              ? const Center(
                  key: Key('vocabEmpty'),
                  child: Text('No entries yet — add one above'),
                )
              : ListView(
                  key: const Key('vocabList'),
                  children: [
                    for (final entry in _entries)
                      ListTile(
                        key: Key('vocabEntry_${entry.id}'),
                        title: Text(entry.lemma),
                        subtitle: Text(
                          entry.context == null || entry.context!.isEmpty
                              ? entry.translation
                              : '${entry.translation} — ${entry.context}',
                        ),
                        trailing: IconButton(
                          key: Key('vocabDelete_${entry.id}'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(entry),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AddEntryForm extends StatelessWidget {
  const _AddEntryForm({
    required this.lemmaController,
    required this.translationController,
    required this.contextController,
    required this.formError,
    required this.onSubmit,
  });

  final TextEditingController lemmaController;
  final TextEditingController translationController;
  final TextEditingController contextController;
  final String? formError;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('vocabAddForm'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('vocabLemmaField'),
          controller: lemmaController,
          decoration: const InputDecoration(labelText: 'Lemma'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('vocabTranslationField'),
          controller: translationController,
          decoration: const InputDecoration(labelText: 'Translation'),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('vocabContextField'),
          controller: contextController,
          decoration: const InputDecoration(
            labelText: 'Context (optional)',
          ),
        ),
        if (formError != null) ...[
          const SizedBox(height: 8),
          Text(
            formError!,
            key: const Key('vocabFormError'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        ElevatedButton(
          key: const Key('vocabAddButton'),
          onPressed: onSubmit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
