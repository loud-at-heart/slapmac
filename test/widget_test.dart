import 'package:flutter_test/flutter_test.dart';
import 'package:slapmac/main.dart';

void main() {
  testWidgets('shows accelerometer-based slap detection UI', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SlapMacApp());
    await tester.pump();

    expect(find.text('Choose slap audio'), findsOneWidget);
    expect(find.text('No file selected'), findsOneWidget);
    expect(find.textContaining('Detection model:'), findsOneWidget);
    expect(find.textContaining('Detected slaps: 0'), findsOneWidget);
  });
}
