import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:exif/exif.dart';

class ImageMetadataProcessor {
  static Future<Uint8List> processFile(
    Uint8List bytes,
    String extension,
    bool stripExif,
    bool stripGps,
    bool stripIcc,
  ) async {
    // 1. Verification Logging: Check BEFORE
    final beforeTags = await readExifFromBytes(bytes);
    print('BEFORE stripping: ${beforeTags.length} tags found.');

    img.Image? image = img.decodeImage(bytes);
    if (image == null) {
      print('FAILED to decode image.');
      return bytes;
    }

    // 2. Complete Metadata Stripping
    // Bake orientation so image doesn't rotate when EXIF removed
    image = img.bakeOrientation(image);

    // Clear EXIF and text metadata objects
    if (stripExif) {
      image.exif.clear();
      if (image.textData != null) {
        image.textData!.clear();
      }
    }

    if (stripIcc) {
      image.iccProfile = null;
    }

    // 3. Create fresh pixel-only image to guarantee zero leftover headers
    final cleanImage = img.Image.from(image, noAnimation: true);
    if (stripExif) {
      cleanImage.exif.clear();
      if (cleanImage.textData != null) {
        cleanImage.textData!.clear();
      }
    }
    if (stripIcc) {
      cleanImage.iccProfile = null;
    }

    final ext = extension.toLowerCase();
    Uint8List result;

    // 4. Handle HEIC / Unsupported by converting to clean JPG
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
      case 'heic':
      case 'heif':
      default:
        // Convert HEIC/HEIF to clean JPG
        result = Uint8List.fromList(img.encodeJpg(cleanImage, quality: 95));
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
