import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'package:exif/exif.dart';
import 'metadata_processor.dart';

void main() {
  runApp(const MetadataCleanerApp());
}

class MetadataCleanerApp extends StatelessWidget {
  const MetadataCleanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpongeBob Metadata Cleaner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
        useMaterial3: true,
      ),
      home: const CleanerHomePage(),
    );
  }
}

enum OutputMode { saveCleanFolder, overwriteOriginal }

extension OutputModeExt on OutputMode {
  String get label {
    switch (this) {
      case OutputMode.saveCleanFolder:
        return 'Save to clean folder';
      case OutputMode.overwriteOriginal:
        return 'Overwrite original files';
    }
  }
}

class QueueItem {
  final String path;
  final String name;
  final int sizeBytes;
  String status;
  String? errorMsg;

  QueueItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.status = 'Pending',
    this.errorMsg,
  });
}

class CleanerHomePage extends StatefulWidget {
  const CleanerHomePage({super.key});

  @override
  State<CleanerHomePage> createState() => _CleanerHomePageState();
}

class _CleanerHomePageState extends State<CleanerHomePage> {
  final List<QueueItem> _queue = [];
  bool _stripExif = true;
  bool _stripGps = true;
  bool _stripColorProfile = false;
  OutputMode _outputMode = OutputMode.saveCleanFolder;
  String _cleanFolder = '';
  bool _isDragging = false;
  bool _isProcessing = false;
  int _processedCount = 0;

  @override
  void initState() {
    super.initState();
    final home = Platform.pathSeparator;
    _cleanFolder = '${Platform.environment['HOME'] ?? ''}/Pictures/Cleaned_Images';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _statusMessage() {
    if (_queue.isEmpty) return 'Drag & drop images or folders here';
    if (_isProcessing) return 'Processing ${'$_processedCount / ${_queue.length}'} files...';
    return '${_queue.length} total image(s) ready for processing';
  }

  void _addFiles(List<String> paths) {
    final Set<String> seen = _queue.map((e) => e.path).toSet();
    for (final path in paths) {
      if (seen.contains(path)) continue;
      final file = File(path);
      if (!file.existsSync()) continue;
      final name = p.basename(path);
      final size = file.lengthSync();
      setState(() {
        _queue.add(QueueItem(path: path, name: name, sizeBytes: size));
      });
    }
  }

  Future<void> _pickFiles() async {
    const typeGroup = XTypeGroup(
      label: 'Images',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic', 'tiff', 'tif'],
    );
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isNotEmpty) {
      _addFiles(files.map((f) => f.path).toList());
    }
  }

  Future<void> _pickFolder() async {
    final dir = await getDirectoryPath();
    if (dir != null) {
      setState(() {
        _cleanFolder = dir;
      });
    }
  }

  Future<void> _viewMetadata(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final exifData = await readExifFromBytes(bytes);
      final decoded = img.decodeImage(bytes);
      String text = 'File: $path\n';
      text += 'Size: ${_formatSize(bytes.length)}\n';
      if (decoded != null) {
        text += 'Dimensions: ${decoded.width} x ${decoded.height}\n';
      }
      text += '\n=== EXIF ===\n';
      if (exifData.isEmpty) {
        text += 'No EXIF metadata found\n';
      } else {
        exifData.forEach((k, v) => text += '$k: $v\n');
      }
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Metadata Inspector'),
          content: SizedBox(
            width: 600,
            height: 400,
            child: SingleChildScrollView(
              child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error reading metadata: $e')));
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;
    setState(() {
      _isProcessing = true;
      _processedCount = 0;
    });

    for (int i = 0; i < _queue.length; i++) {
      final item = _queue[i];
      setState(() {
        item.status = 'Processing';
      });

      try {
        final bytes = await File(item.path).readAsBytes();
        final ext = p.extension(item.path).replaceFirst('.', '').toLowerCase();
        final cleaned = await ImageMetadataProcessor.processFile(
          bytes,
          ext,
          _stripExif,
          _stripGps,
          _stripColorProfile,
        );

        String outPath;
        if (_outputMode == OutputMode.saveCleanFolder) {
          final dir = Directory(_cleanFolder);
          if (!dir.existsSync()) dir.createSync(recursive: true);
          outPath = p.join(_cleanFolder, item.name);
        } else {
          outPath = item.path;
        }

        final tmpPath = '${outPath}.tmp';
        await File(tmpPath).writeAsBytes(cleaned);
        if (_outputMode == OutputMode.overwriteOriginal) {
          await File(item.path).delete();
        }
        await File(tmpPath).rename(outPath);

        setState(() {
          item.status = 'Metadata Stripped';
          _processedCount++;
        });
      } catch (e) {
        setState(() {
          item.status = 'Error';
          item.errorMsg = e.toString();
          _processedCount++;
        });
      }
    }

    setState(() {
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = _queue.isEmpty ? 0.0 : _processedCount / _queue.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SpongeBob Cleaner'),
        backgroundColor: Colors.amber.shade300,
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (detail) {
          setState(() => _isDragging = false);
          final paths = detail.files.map((f) => f.path).toList();
          for (final path in paths) {
            final entity = FileSystemEntity.typeSync(path);
            if (entity == FileSystemEntityType.directory) {
              final dir = Directory(path);
              final files = dir.listSync(recursive: true).whereType<File>();
              for (final f in files) {
                final ext = p.extension(f.path).toLowerCase();
                if (['.jpg','.jpeg','.png','.webp','.heic','.tiff','.tif'].contains(ext)) {
                  _addFiles([f.path]);
                }
              }
            } else {
              _addFiles([path]);
            }
          }
        },
        child: Container(
          color: _isDragging ? Colors.amber.withOpacity(0.1) : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _isDragging ? Colors.amber : Colors.grey.shade400,
                              width: 2,
                              style: BorderStyle.dashed,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _queue.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.cloud_upload, size: 64, color: Colors.amber),
                                      const SizedBox(height: 16),
                                      const Text('Drag & Drop Images Here', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      const Text('or use button below'),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: _pickFiles,
                                        icon: const Icon(Icons.folder_open),
                                        label: const Text('Browse Files'),
                                      ),
                                    ],
                                  ),
                                )
                              : Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Row(
                                        children: [
                                          Text('File Queue (${_queue.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          const Spacer(),
                                          TextButton.icon(
                                            onPressed: _pickFiles,
                                            icon: const Icon(Icons.add),
                                            label: const Text('Add'),
                                          ),
                                          TextButton.icon(
                                            onPressed: _isProcessing ? null : () => setState(() => _queue.clear()),
                                            icon: const Icon(Icons.clear_all, color: Colors.red),
                                            label: const Text('Clear', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: ListView.builder(
                                        itemCount: _queue.length,
                                        itemBuilder: (ctx, i) {
                                          final item = _queue[i];
                                          Color badge;
                                          switch (item.status) {
                                            case 'Metadata Stripped':
                                              badge = Colors.green;
                                              break;
                                            case 'Processing':
                                              badge = Colors.blue;
                                              break;
                                            case 'Error':
                                              badge = Colors.red;
                                              break;
                                            default:
                                              badge = Colors.grey;
                                          }
                                          return ListTile(
                                            leading: const Icon(Icons.image),
                                            title: Text(item.name, overflow: TextOverflow.ellipsis),
                                            subtitle: Text(item.path, overflow: TextOverflow.ellipsis),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(_formatSize(item.sizeBytes), style: const TextStyle(fontSize: 12)),
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  icon: const Icon(Icons.info_outline, size: 20),
                                                  onPressed: () => _viewMetadata(item.path),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: badge.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: badge),
                                                  ),
                                                  child: Text(item.status, style: TextStyle(color: badge, fontSize: 12, fontWeight: FontWeight.bold)),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.close),
                                                  onPressed: () => setState(() => _queue.removeAt(i)),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(_statusMessage()),
                          const Spacer(),
                          if (_isProcessing) LinearProgressIndicator(value: progress),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _isProcessing || _queue.isEmpty ? null : _processQueue,
                            icon: _isProcessing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cleaning_services),
                            label: Text(_isProcessing ? 'Processing...' : 'Strip Metadata'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber.shade400,
                              foregroundColor: Colors.black87,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 340,
                color: Colors.grey.shade100,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    const Text('Destination Mode', style: TextStyle(fontWeight: FontWeight.w600)),
                    RadioListTile<OutputMode>(
                      title: const Text('Save to clean folder'),
                      value: OutputMode.saveCleanFolder,
                      groupValue: _outputMode,
                      onChanged: (v) => setState(() => _outputMode = v!),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<OutputMode>(
                      title: const Text('Overwrite original files'),
                      value: OutputMode.overwriteOriginal,
                      groupValue: _outputMode,
                      onChanged: (v) => setState(() => _outputMode = v!),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_outputMode == OutputMode.saveCleanFolder) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(_cleanFolder, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ),
                          TextButton(onPressed: _pickFolder, child: const Text('Change...')),
                        ],
                      ),
                    ],
                    const Divider(height: 32),
                    const Text('Metadata to Strip', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    CheckboxListTile(
                      title: const Text('EXIF / TIFF / IPTC'),
                      value: _stripExif,
                      onChanged: (v) => setState(() => _stripExif = v ?? true),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      title: const Text('GPS Coordinates'),
                      value: _stripGps,
                      onChanged: (v) => setState(() => _stripGps = v ?? true),
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      title: const Text('Color Profiles (ICC)'),
                      value: _stripColorProfile,
                      onChanged: (v) => setState(() => _stripColorProfile = v ?? false),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
