import 'package:flutter/material.dart';
import 'package:my_translator_app/src/rust/api/simple.dart';
import 'package:my_translator_app/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter + Rust Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _textController = TextEditingController();
  String _result = 'Результат появится здесь';

  // Пример асинхронного вызова (Rust-функции могут быть async)
  Future<void> _callRust() async {
    final input = _textController.text;
    if (input.isEmpty) return;

    // Вызов функции из Rust
    final processed = await processText(input: input);
    final sum = await addNumbers(a: 10, b: 32);

    setState(() {
      _result = 'Rust вернул: "$processed" (сумма 10+32=$sum)';
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter + Rust Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'Введите текст (например, слово для перевода)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _callRust,
              child: const Text('Вызвать Rust'),
            ),
            const SizedBox(height: 20),
            Text(_result, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
