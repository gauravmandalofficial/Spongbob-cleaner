import 'package:flutter_test/flutter_test.dart';
import 'package:spongebob_cleaner/main.dart';

void main() {
  testWidgets('App renders title', (WidgetTester tester) async {
    await tester.pumpWidget(const SpongeBobCleanerApp());
    expect(find.text('SpongeBob Cleaner'), findsOneWidget);
  });
}
