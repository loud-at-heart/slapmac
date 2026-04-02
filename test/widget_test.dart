import 'package:flutter_test/flutter_test.dart';
import 'package:slapmac/main.dart';

void main() {
  testWidgets('requires user audio file before slapping', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SlapMacApp());

    expect(find.text('Choose slap audio'), findsOneWidget);
    expect(find.text('No file selected'), findsOneWidget);

    await tester.tap(find.text('Keyboard area'));
    await tester.pump();

    expect(find.text('Please choose your own slap audio file first.'), findsOneWidget);
    expect(find.textContaining('Total slaps: 0'), findsOneWidget);
  });
}
