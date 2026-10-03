# SpongeBob Metadata Cleaner

Cross-platform desktop app to strip EXIF, GPS, IPTC metadata from images. Single codebase Flutter desktop.

## Supported formats
JPEG, PNG, HEIC, TIFF, WebP

## Local run
```bash
flutter pub get
flutter run -d macos
# or
flutter run -d windows
```

## Build
Mac:
```bash
flutter build macos --release
```

Windows:
```bash
flutter build windows --release
```

## CI/CD
Push tag `v*` triggers GitHub Actions build for macOS and Windows, uploads to GitHub Release.
