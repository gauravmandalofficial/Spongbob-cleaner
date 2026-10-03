import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageMetadataProcessor {
  static Future<Uint8List> processFile(
    Uint8List bytes,
    String extension,
    bool stripExif,
    bool stripGps,
    bool stripIcc,
  ) async {
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // 1. Bake EXIF orientation so image does not rotate when orientation tag stripped
    image = img.bakeOrientation(image);

    // 2. Strip all metadata from image object
    if (stripExif) {
      image.exif.clear();
      if (image.textData != null) {
        image.textData!.clear();
      }
    }

    if (stripIcc) {
      image.iccProfile = null;
    }

    // 3. Create fresh pixel-only image buffer to guarantee 0 leftover headers
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
    const int quality = 95;

    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return Uint8List.fromList(img.encodeJpg(cleanImage, quality: quality));
      case 'png':
        return Uint8List.fromList(img.encodePng(cleanImage));
      case 'webp':
        return Uint8List.fromList(img.encodeWebP(cleanImage, quality: quality));
      case 'tiff':
      case 'tif':
        return Uint8List.fromList(img.encodeTiff(cleanImage));
      case 'heic':
      case 'heif':
        // Encode as clean high-quality JPG if HEIC input
        return Uint8List.fromList(img.encodeJpg(cleanImage, quality: quality));
      default:
        return Uint8List.fromList(img.encodeJpg(cleanImage, quality: quality));
    }
  }
}

