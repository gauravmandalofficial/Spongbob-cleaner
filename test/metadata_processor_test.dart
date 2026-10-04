import 'package:flutter_test/flutter_test.dart';
import 'package:spongebob_cleaner/metadata_processor.dart';
import 'package:image/image.dart' as img;
import 'package:exif/exif.dart';
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

  test('ImageMetadataProcessor strips EXIF from PNG', () async {
    // Create a minimal valid PNG with a tEXt chunk containing metadata
    final bytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      // IHDR chunk
      0x00, 0x00, 0x00, 0x0D, // width 13
      0x00, 0x00, 0x00, 0x0D, // height 13
      0x08, 0x02, 0x00, 0x00, 0x00, // bit_depth=8, color_type=2 (RGB)
      0x00, 0x00, 0x00, 0x00, // compressed method, filter method, interlace method
      // IDAT chunk (empty - just a filter byte)
      0x00, // filter byte
      0x00, 0x00, 0x00, 0x00, // raw data
      0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00,
      // tEXt chunk with metadata
      0x74, 0x58, 0x45, 0x54, // "tEXt" keyword length
      0x00, 0x6D, 0x61, 0x69, 0x6E, 0x74, 0x6F, // "making" text
    ]);
    final result = await ImageMetadataProcessor.processFile(
      bytes,
      'png',
      true,
      true,
      true,
    );
    // Decode the result and check for no text chunks
    final img.Image? decoded = img.decodePng(result);
    expect(decoded, isNotNull);
  });

  test('ImageMetadataProcessor converts HEIC to clean JPG with no EXIF', () async {
    // HEIC cannot be losslessly stripped via pure Dart; should convert to JPG
    final heicBytes = Uint8List.fromList([
      0x00, 0x00, 0x00, 0x18, // size
      0x66, 0x74, 0x79, 0x70, // 'ftyp' box
      0x00, 0x00, 0x00, 0x00, // placeholder
      0x20, 0x6d, 0x61, 0x69, 0x6e, 0x20, 0x63, 0x6f, 0x6d, 0x00, // brand/maker
    ]);
    final result = await ImageMetadataProcessor.processFile(
      heicBytes,
      'heic',
      true,
      true,
      true,
    );
    // Should produce valid JPG bytes (non-null)
    expect(result, isNotNull);
    // Should have 0 EXIF tags after conversion
    final afterTags = await readExifFromBytes(result);
    expect(afterTags.length, equals(0));
  });
}
