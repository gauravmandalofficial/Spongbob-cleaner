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
    final img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;

    final ext = extension.toLowerCase();
    int quality = 95;

    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return Uint8List.fromList(img.encodeJpg(image, quality: quality));
      case 'png':
        return Uint8List.fromList(img.encodePng(image));
      case 'webp':
        return Uint8List.fromList(img.encodeWebP(image, quality: quality));
      case 'tiff':
      case 'tif':
        return Uint8List.fromList(img.encodeTiff(image));
      case 'heic':
      case 'heif':
        return bytes;
      default:
        return bytes;
    }
  }
}
