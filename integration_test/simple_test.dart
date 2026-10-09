import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_translator_app/app/app.dart';
import 'package:my_translator_app/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('shell opens Library after Drift init', (WidgetTester tester) async {
    await tester.pumpWidget(const TranslationReaderApp());
    // Cold start: loading, then Library destination.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Vocab'), findsOneWidget);
    expect(find.text('Вызвать Rust'), findsNothing);
  });
}
