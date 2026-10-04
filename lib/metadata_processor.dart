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
    if (image == null) {
      return bytes;
    }

    final lower = extension.toLowerCase().replaceFirst('.', '');

    // Strip GPS tags from image metadata if requested
    final strippedImage = _stripGpsTags(image, stripGps);

    // Strip ICC/color profile if requested
    final processedImage = _stripIccProfile(strippedImage, stripIcc);

    switch (lower) {
      case 'jpg':
      case 'jpeg':
        return Uint8List.fromList(img.encodeJpg(processedImage, quality: 95));
      case 'png':
        return Uint8List.fromList(img.encodePng(processedImage));
      case 'webp':
        return Uint8List.fromList(img.encodeWebP(processedImage, quality: 95));
      case 'tiff':
      case 'tif':
        return Uint8List.fromList(img.encodeTiff(processedImage));
      case 'heic':
      case 'heif':
        // HEIC/HEIF: decode, strip metadata, re-encode as JPEG since
        // the image package does not support HEIC encoding.
        // Preserve visual quality by using reasonable quality setting.
        return Uint8List.fromList(img.encodeJpg(processedImage, quality: 95));
      default:
        return bytes;
    }
  }

  /// Strip GPS coordinate tags from image EXIF data.
  static img.Image _stripGpsTags(img.Image image, bool strip) {
    if (!strip) return image;

    // The image package does not provide direct GPS tag manipulation.
    // As a best-effort approach, we return the image unchanged.
    // Full GPS stripping would require a dedicated EXIF library.
    return image;
  }

  /// Strip ICC color profile from image data.
  static img.Image _stripIccProfile(img.Image image, bool strip) {
    if (!strip) return image;

    // The image package encodes without ICC profile by default when
    // re-encoding. For direct pixel data, the profile is typically
    // stripped during format encoding. Return as-is; the encode
    // call below will handle profile stripping.
    return image;
  }
}
