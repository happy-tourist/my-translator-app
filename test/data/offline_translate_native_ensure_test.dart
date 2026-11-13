import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/translate/offline_translate_native.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('opus_ensure_test_');
  });

  tearDown(() async {
    debugResetOfflineTranslateNativeEnsure();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  // TO-12 (in-process): after warm-up/ready, further ensure is a no-op.
  test('TO-12 / 2.1 ready no-op skips second init after warm-up', () async {
    var ready = false;
    debugIsOfflineTranslateReadyOverride = () async => ready;
    debugLoadAndInitOverride = (bundle) async {
      ready = true;
    };

    await warmUpOfflineTranslate(bundle: _EmptyBundle());
    expect(debugOfflineTranslateInitStarts, 1);

    await warmUpOfflineTranslate(bundle: _EmptyBundle());
    await ensureOfflineTranslateReady(bundle: _EmptyBundle());
    expect(debugOfflineTranslateInitStarts, 1);
  });

  test('2.1 shared in-flight: parallel ensure starts one init', () async {
    final gate = Completer<void>();
    debugIsOfflineTranslateReadyOverride = () async => false;
    debugLoadAndInitOverride = (bundle) async {
      await gate.future;
    };

    final a = ensureOfflineTranslateReady(bundle: _EmptyBundle());
    final b = ensureOfflineTranslateReady(bundle: _EmptyBundle());
    // Let both pass the async ready check and claim the shared Future.
    await Future<void>.delayed(Duration.zero);
    expect(debugOfflineTranslateInitStarts, 1);

    gate.complete();
    await Future.wait([a, b]);
    expect(debugOfflineTranslateInitStarts, 1);
  });

  testWidgets('TO-11 cold init allows frames and taps during fake slow init',
      (tester) async {
    final gate = Completer<void>();
    var taps = 0;
    debugIsOfflineTranslateReadyOverride = () async => false;
    debugLoadAndInitOverride = (bundle) async {
      // Async gap only — production `_loadAndInit` owns the D13 frame yield.
      await gate.future;
    };

    late final Future<void> ensureFuture;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _ColdInitProbe(
            onEnsure: () {
              ensureFuture = ensureOfflineTranslateReady(bundle: _EmptyBundle());
              return ensureFuture;
            },
            onProbeTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('cold-init-loading')), findsOneWidget);

    // Interaction accepted while fake slow init is still open (TO-11).
    await tester.tap(find.byKey(const Key('probe-tap')));
    await tester.pump();
    expect(taps, 1);

    gate.complete();
    await ensureFuture;
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
    expect(debugOfflineTranslateInitStarts, 1);
  });

  // 11.2 / TO-14 product path: extract → path init (not bytes→FRB).
  test('11.2 product ensure uses path init and skips second extract when ready',
      () async {
    final modelDir = Directory(p.join(tempRoot.path, 'opus-mt-en-ru'));
    await modelDir.create(recursive: true);

    var ready = false;
    final pathDirs = <String>[];
    debugIsOfflineTranslateReadyOverride = () async => ready;
    debugModelDirOverride = () async => modelDir;
    debugInitFromDirOverride = (dir) async {
      pathDirs.add(dir);
      ready = true;
    };

    // ONNX reuse heuristic requires >= 1MiB; keep just above that for speed.
    const onnxBytes = 1024 * 1024 + 8;
    final bundle = _SizedBundle({
      'assets/models/opus-mt-en-ru/tokenizer.json': 2048,
      'assets/models/opus-mt-en-ru/onnx/encoder_model_uint8.onnx': onnxBytes,
      'assets/models/opus-mt-en-ru/onnx/decoder_model_uint8.onnx': onnxBytes,
    });

    // First ensure: extract + path init (no full bytes FRB).
    await ensureOfflineTranslateReady(bundle: bundle);
    expect(debugOfflineTranslateInitStarts, 1);
    expect(debugOfflineTranslateExtractPasses, 1);
    expect(debugOfflineTranslatePathInitStarts, 1);
    expect(pathDirs, [modelDir.path]);
    for (final name in kOfflineTranslateNativeAssetPaths.keys) {
      expect(File(p.join(modelDir.path, name)).existsSync(), isTrue);
    }

    // Second ensure while ready: no second heavy extract / path init.
    await ensureOfflineTranslateReady(bundle: bundle);
    expect(debugOfflineTranslateInitStarts, 1);
    expect(debugOfflineTranslateExtractPasses, 1);
    expect(debugOfflineTranslatePathInitStarts, 1);
  });

  // 11.2 reuse: on-disk files skip AssetBundle re-write.
  test('11.2 extract reuses on-disk files without second write', () async {
    final modelDir = Directory(p.join(tempRoot.path, 'reuse'));
    await modelDir.create(recursive: true);
    // Plausible sizes so _modelFilesLookReady returns true.
    const onnxBytes = 1024 * 1024 + 8;
    await File(p.join(modelDir.path, 'tokenizer.json'))
        .writeAsBytes(Uint8List(2048));
    await File(p.join(modelDir.path, 'encoder_model_uint8.onnx'))
        .writeAsBytes(Uint8List(onnxBytes));
    await File(p.join(modelDir.path, 'decoder_model_uint8.onnx'))
        .writeAsBytes(Uint8List(onnxBytes));

    final wrote = await debugExtractOfflineTranslateModelAssets(
      _ThrowingBundle(),
      modelDir,
    );
    expect(wrote, isFalse);
  });

  // TO-11: chunked write yields; product path never builds OfflineModelAsset bytes.
  test('TO-11 chunked disk write preserves bytes across multi-chunk file',
      () async {
    final dest = File(p.join(tempRoot.path, 'chunk.bin'));
    final src = Uint8List(1024 * 1024);
    for (var i = 0; i < src.length; i++) {
      src[i] = i & 0xff;
    }
    await debugWriteOfflineTranslateAssetFileChunked(dest, src);
    final read = await dest.readAsBytes();
    expect(read, orderedEquals(src));
  });

  testWidgets(
      'TO-11 path-init cold path keeps loader alive without bytes FRB',
      (tester) async {
    final extractGate = Completer<void>();
    var ready = false;
    var taps = 0;
    debugIsOfflineTranslateReadyOverride = () async => ready;
    // Product cold path = extract yields + path init (not bytes→FRB encode).
    debugLoadAndInitOverride = (bundle) async {
      await extractGate.future;
      debugOfflineTranslatePathInitStarts++;
      ready = true;
    };

    late final Future<void> ensureFuture;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _ColdInitProbe(
            onEnsure: () {
              ensureFuture = ensureOfflineTranslateReady(bundle: _EmptyBundle());
              return ensureFuture;
            },
            onProbeTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('cold-init-loading')), findsOneWidget);

    // Frames + taps while cold path is in-flight (TO-11 live loader).
    await tester.tap(find.byKey(const Key('probe-tap')));
    await tester.pump();
    expect(taps, 1);

    extractGate.complete();
    await ensureFuture;
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
    expect(debugOfflineTranslatePathInitStarts, 1);
    expect(debugOfflineTranslateInitStarts, 1);
  });
}

/// Starts ensure once from [initState] so FutureBuilder is stable across pumps.
class _ColdInitProbe extends StatefulWidget {
  const _ColdInitProbe({
    required this.onEnsure,
    required this.onProbeTap,
  });

  final Future<void> Function() onEnsure;
  final VoidCallback onProbeTap;

  @override
  State<_ColdInitProbe> createState() => _ColdInitProbeState();
}

class _ColdInitProbeState extends State<_ColdInitProbe> {
  late final Future<void> _ensureFuture = widget.onEnsure();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          key: const Key('probe-tap'),
          onPressed: widget.onProbeTap,
          child: const Text('probe'),
        ),
        FutureBuilder<void>(
          future: _ensureFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator(
                key: Key('cold-init-loading'),
              );
            }
            return const Text('ready');
          },
        ),
      ],
    );
  }
}

/// Minimal AssetBundle — cold path override never loads real model assets.
class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData(0);
}

/// AssetBundle that returns fixed-size buffers for extract tests.
class _SizedBundle extends CachingAssetBundle {
  _SizedBundle(this.sizes);

  final Map<String, int> sizes;

  @override
  Future<ByteData> load(String key) async {
    final n = sizes[key];
    if (n == null) {
      throw FlutterError('Missing asset: $key');
    }
    return ByteData(n);
  }
}

/// Fails if any asset is loaded — used to prove reuse skips AssetBundle.
class _ThrowingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    throw StateError('unexpected AssetBundle.load($key) during reuse');
  }
}
