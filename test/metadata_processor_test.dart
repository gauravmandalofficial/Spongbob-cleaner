import 'package:flutter_test/flutter_test.dart';
import 'package:metadata_cleaner/metadata_processor.dart';
import 'dart:typed_data';

void main() {
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
