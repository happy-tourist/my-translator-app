import 'package:flutter/material.dart';

import 'package:my_translator_app/app/app.dart';
import 'package:my_translator_app/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await RustLib.init();
  } catch (e, st) {
    assert(() {
      debugPrint('RustLib.init failed: $e\n$st');
      return true;
    }());
    runApp(const _InitFailureApp());
    return;
  }
  runApp(const TranslationReaderApp());
}

/// Minimal fatal UI when FRB init fails (no product shell / Drift).
class _InitFailureApp extends StatelessWidget {
  const _InitFailureApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Translation Reader',
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Could not start the app engine. Restart the app or check '
              'that the device/browser supports the native bridge.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
