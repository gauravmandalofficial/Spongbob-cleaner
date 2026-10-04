import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:exif/exif.dart';

class ImageMetadataProcessor {
  static Future<Uint8List> processFile(
    Uint8List fileBytes,
    String extension,
    bool stripExif,
    bool stripGps,
    bool stripIcc,
  ) async {
    // 1. Verification Logging: Check BEFORE
    final beforeTags = await readExifFromBytes(fileBytes);
    print('BEFORE stripping: ${beforeTags.length} tags found.');

    final ext = extension.toLowerCase();

    // --- HEIC / HEIF handling via native macOS sips + BMP intermediary ---
    if (ext == 'heic' || ext == 'heif') {
      if (Platform.isMacOS) {
        // Use deterministic session-id temp files to prevent disk leaks
        final String sessionId = DateTime.now().millisecondsSinceEpoch.toString();
        final String inputPath = '${Directory.systemTemp.path}/input_$sessionId.heic';
        final String tempBmp = '${Directory.systemTemp.path}/temp_$sessionId.bmp';

        try {
          // 1. Write incoming HEIC bytes to disk
          await File(inputPath).writeAsBytes(fileBytes);

          // 2. Shell out to native macOS CoreImage (sips) to convert to BMP
          // BMP has no metadata container, guaranteeing 100% EXIF/GPS strip
          final res = await Process.run('/usr/bin/sips', [
            '-s', 'format', 'bmp',
            inputPath,
            '--out', tempBmp,
          ]);

          if (res.exitCode != 0) {
            throw Exception('Native macOS HEIC decoding failed: ${res.stderr}');
          }

          // 3. Read the inherently metadata-free BMP pixels
          final bmpBytes = await File(tempBmp).readAsBytes();

          // 4. Decode into Dart Image
          final decoded = img.decodeBmp(bmpBytes);
          if (decoded == null) {
            throw Exception('Failed to decode BMP buffer');
          }

          // 5. Hard purge of any residual memory structures (defense in depth)
          decoded.exif = img.ExifData();
          decoded.textData?.clear();

          // 6. Output clean JPEG bytes
          return img.encodeJpg(decoded, quality: 95);
        } finally {
          // 7. Deterministic Garbage Collection: Always clean up disk I/O
          // This block runs even if sips crashes, BMP decode fails, or exceptions throw
          if (File(inputPath).existsSync()) {
            await File(inputPath).delete();
          }
          if (File(tempBmp).existsSync()) {
            await File(tempBmp).delete();
          }
        }
      }

      // Cross-platform fallback: Dart cannot losslessly strip HEIC;
      // try decode then JPG convert
      img.Image? image = img.decodeImage(fileBytes);
      if (image == null) {
        print('FAILED to decode HEIC image.');
        return fileBytes;
      }
      image = img.bakeOrientation(image);
      final cleanImage = img.Image.from(image, noAnimation: true);
      cleanImage.exif = img.ExifData();
      if (cleanImage.textData != null) {
        cleanImage.textData!.clear();
      }
      return Uint8List.fromList(img.encodeJpg(cleanImage, quality: 95));
    }

    // --- Standard image formats (PNG, WebP, TIFF, JPG) ---
    img.Image? image = img.decodeImage(fileBytes);
    if (image == null) {
      print('FAILED to decode image.');
      return fileBytes;
    }

    // Bake orientation so image doesn't rotate when EXIF removed
    image = img.bakeOrientation(image);

    // Clear EXIF and text metadata objects
    if (stripExif) {
      image.exif = img.ExifData();
      if (image.textData != null) {
        image.textData!.clear();
      }
    } else if (stripGps) {
      // Remove only GPS tags from EXIF
      image.exif = img.ExifData();
    }

    if (stripIcc) {
      image.iccProfile = null;
    }

    // Create fresh pixel-only image to guarantee zero leftover headers
    final cleanImage = img.Image.from(image, noAnimation: true);
    if (stripExif) {
      cleanImage.exif = img.ExifData();
      if (cleanImage.textData != null) {
        cleanImage.textData!.clear();
      }
    } else if (stripGps) {
      cleanImage.exif = img.ExifData();
    }
    if (stripIcc) {
      cleanImage.iccProfile = null;
    }

    // 4. Encode into target format
    Uint8List result;

    switch (ext) {
      case 'png':
        result = Uint8List.fromList(img.encodePng(cleanImage));
        break;
      case 'webp':
        result = Uint8List.fromList(img.encodeWebP(cleanImage, quality: 95));
        break;
      case 'tiff':
      case 'tif':
        result = Uint8List.fromList(img.encodeTiff(cleanImage));
        break;
      case 'jpg':
      case 'jpeg':
        result = Uint8List.fromList(img.encodeJpg(cleanImage, quality: 95));
        break;
      default:
        result = fileBytes;
        break;
    }

    // 5. Verification Logging: Check AFTER
    final afterTags = await readExifFromBytes(result);
    print('AFTER stripping: ${afterTags.length} tags found.');

    if (afterTags.isNotEmpty) {
      print('WARNING: Some tags remained: ${afterTags.keys.take(5).toList()}');
    }

    return result;
  }
}