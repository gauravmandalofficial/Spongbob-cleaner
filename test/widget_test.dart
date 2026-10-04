import 'package:flutter_test/flutter_test.dart';
import 'package:spongebob_cleaner/main.dart';
import 'package:spongebob_cleaner/metadata_processor.dart';
import 'dart:typed_data';

void main() {
  testWidgets('App renders title', (WidgetTester tester) async {
    await tester.pumpWidget(const SpongeBobCleanerApp());
    expect(find.text('SpongeBob by GM'), findsOneWidget);
  });

  test('ImageMetadataProcessor handles empty or invalid bytes gracefully', () async {
    final invalidBytes = Uint8List.fromList([0, 1, 2, 3]);
    final result = await ImageMetadataProcessor.processFile(
      invalidBytes,
      'jpg',
      true,
      true,
      true,
    );
    expect(result, equals(invalidBytes));
  });
}
