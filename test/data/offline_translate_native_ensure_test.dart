import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_translator_app/data/translate/offline_translate_native.dart';

void main() {
  tearDown(debugResetOfflineTranslateNativeEnsure);

  // Align fix: large AssetBundle views use chunked setRange + yields (not Isolate.run).
  test('TO-11 chunked own-copy preserves bytes across multi-chunk buffer',
      () async {
    // >64KiB threshold and >512KiB chunk → at least one yield between setRange.
    final src = Uint8List(1024 * 1024);
    for (var i = 0; i < src.length; i++) {
      src[i] = i & 0xff;
    }
    final owned = await debugOwnOfflineTranslateAssetBytes(src);
    expect(owned.length, src.length);
    expect(owned, orderedEquals(src));
  });

  test('TO-11 small own-copy stays sync-style fromList path', () async {
    final src = Uint8List.fromList([1, 2, 3, 4]);
    final owned = await debugOwnOfflineTranslateAssetBytes(src);
    expect(owned, orderedEquals(src));
    expect(identical(owned, src), isFalse);
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
      // Async gap only — production `_loadAndInit` owns the D3 frame yield.
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
