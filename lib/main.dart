import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:exif/exif.dart';
import 'metadata_processor.dart';

void main() {
  runApp(const SpongeBobCleanerApp());
}

class SpongeBobCleanerApp extends StatelessWidget {
  const SpongeBobCleanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpongeBob Cleaner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
        useMaterial3: true,
      ),
      home: const CleanerHomePage(),
    );
  }
}

class QueueItem {
  final String path;
  final String name;
  final int sizeBytes;
  String status;

  QueueItem({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.status = 'Pending',
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
  bool _stripColorProfile = true;
  int _outputOption = 0;
  String? _customFolderPath;
  bool _isDragging = false;
  bool _isProcessing = false;

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static const _validExtensions = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'};

void _addFiles(List<String> paths) {
    setState(() {
      for (final path in paths) {
        final file = File(path);
        if (file.existsSync()) {
          final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
          if (_validExtensions.contains(ext)) {
            final name = p.basename(path);
            final size = file.lengthSync();
            if (!_queue.any((item) => item.path == path)) {
              _queue.add(QueueItem(path: path, name: name, sizeBytes: size));
            }
          }
        }
      }
    });
  }

  Future<void> _pickFiles() async {
    const typeGroup = XTypeGroup(
      label: 'Images',
      extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic'],
    );
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isNotEmpty) {
      _addFiles(files.map((f) => f.path).toList());
    }
  }

  Future<void> _pickCustomFolder() async {
    final String? result = await getDirectoryPath();
    if (result != null) {
      setState(() {
        _customFolderPath = result;
      });
    }
  }

  Future<void> _showMetadataInspector(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();

      String metadataText = 'File: $filePath\n';
      metadataText += 'Extension: $ext\n';
      metadataText += 'Size: ${_formatSize(bytes.length)}\n\n';

      if (ext == 'jpg' || ext == 'jpeg' || ext == 'tiff' || ext == 'tif' || ext == 'heic' || ext == 'heif' || ext == 'png' || ext == 'webp') {
        final exifData = await readExifFromBytes(bytes);
        if (exifData.isNotEmpty) {
          metadataText += '=== EXIF / METADATA ===\n';
          for (final entry in exifData.entries) {
            metadataText += '${entry.key}: ${entry.value}\n';
          }
        } else {
          metadataText += 'No EXIF metadata found.\n';
        }
      } else {
        metadataText += 'Format does not support EXIF metadata.\n';
      }

      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded != null) {
        metadataText += '\n=== IMAGE INFO ===\n';
        metadataText += 'Width: ${decoded.width}\n';
        metadataText += 'Height: ${decoded.height}\n';
        metadataText += 'Channels: ${decoded.numChannels}\n';
      }

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Metadata Inspector - ${p.basename(filePath)}'),
          content: SizedBox(
            width: 600,
            height: 400,
            child: SingleChildScrollView(
              child: SelectableText(
                metadataText,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to read metadata: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;
    setState(() {
      _isProcessing = true;
    });

    for (int i = 0; i < _queue.length; i++) {
      if (_queue[i].status == 'Cleaned') continue;

      setState(() {
        _queue[i].status = 'Processing';
      });

      try {
        final file = File(_queue[i].path);
        final bytes = await file.readAsBytes();

        final ext = p.extension(_queue[i].path).replaceFirst('.', '').toLowerCase();
        final cleanedBytes = await ImageMetadataProcessor.processFile(
          bytes,
          ext,
          _stripExif,
          _stripGps,
          _stripColorProfile,
        );

        String outPath;
        if (_outputOption == 0) {
          final dir = p.dirname(_queue[i].path);
          final filename = p.basenameWithoutExtension(_queue[i].path);
          final extension = p.extension(_queue[i].path);
          outPath = p.join(dir, '${filename}_clean$extension');
        } else if (_outputOption == 1) {
          outPath = _queue[i].path;
        } else {
          final targetDir = _customFolderPath ?? p.dirname(_queue[i].path);
          outPath = p.join(targetDir, p.basename(_queue[i].path));
        }

        final overwrite = outPath == _queue[i].path; // option 1: overwrite original
        if (overwrite && !await _confirmOverwrite(outPath)) {
          setState(() {
            _queue[i].status = 'Skipped';
          });
          continue;
        }

        await File(outPath).writeAsBytes(cleanedBytes);
        setState(() {
          _queue[i].status = 'Cleaned';
        });
      } catch (e) {
        setState(() {
          _queue[i].status = 'Error';
        });
      }
    }

    setState(() {
      _isProcessing = false;
    });
  }

  /// Show confirmation dialog before clearing the queue.
  Future<void> _confirmClearQueue() async {
    if (!_queue.isEmpty) {
      final confirmed = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clear Queue'),
          content: const Text('Remove all files from the processing queue?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        setState(() => _queue.clear());
      }
    }
  }

  /// Show confirmation dialog before overwriting a file.
  Future<bool> _confirmOverwrite(String path) async {
    final file = File(path);
    if (!await file.exists()) return true; // no existing file, allow

    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Overwrite File'),
        content: Text('Replace existing file: ${Basename(path)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Original'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SpongeBob Cleaner'),
        backgroundColor: Colors.amber.shade300,
      ),
      body: DropTarget(
        onDragEntered: (detail) {
          setState(() {
            _isDragging = true;
          });
        },
        onDragExited: (detail) {
          setState(() {
            _isDragging = false;
          });
        },
        onDragDone: (detail) {
          setState(() {
            _isDragging = false;
          });
          _addFiles(detail.files.map((f) => f.path).toList());
        },
        child: Container(
          color: _isDragging ? Colors.amber.withOpacity(0.1) : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
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
                                      const Text(
                                        'Drag & Drop Image Files Here',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text('or use the button below'),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: _pickFiles,
                                        icon: const Icon(Icons.folder_open),
                                        label: const Text('Select Files'),
                                      ),
                                    ],
                                  ),
                                )
                              : Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('File Queue (${_queue.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          Row(
                                            children: [
                                              TextButton.icon(
                                                onPressed: _pickFiles,
                                                icon: const Icon(Icons.add),
                                                label: const Text('Add Files'),
                                              ),
                                              TextButton.icon(
                                                onPressed: _isProcessing ? null : () => _confirmClearQueue(),
                                                icon: const Icon(Icons.clear_all, color: Colors.red),
                                                label: const Text('Clear', style: TextStyle(color: Colors.red)),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Divider(height: 1),
                                    Expanded(
                                      child: ListView.builder(
                                        itemCount: _queue.length,
                                        itemBuilder: (context, index) {
                                          final item = _queue[index];
                                          Color badgeColor;
                                          if (item.status == 'Cleaned') {
                                            badgeColor = Colors.green;
                                          } else if (item.status == 'Processing') {
                                            badgeColor = Colors.blue;
                                          } else if (item.status == 'Error') {
                                            badgeColor = Colors.red;
                                          } else {
                                            badgeColor = Colors.grey;
                                          }

                                          return ListTile(
                                            leading: const Icon(Icons.image),
                                            title: Text(item.name, overflow: TextOverflow.ellipsis),
                                            subtitle: Text(item.path, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(_formatSize(item.sizeBytes), style: const TextStyle(fontSize: 12)),
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  icon: const Icon(Icons.info_outline, size: 20),
                                                  tooltip: 'View Metadata',
                                                  onPressed: () => _showMetadataInspector(item.path),
                                                ),
                                                const SizedBox(width: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: badgeColor.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: badgeColor),
                                                  ),
                                                  child: Text(
                                                    item.status,
                                                    style: TextStyle(color: badgeColor, fontSize: 12, fontWeight: FontWeight.bold),
                                                  ),
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
                    ],
                  ),
                ),
              ),
              Container(
                width: 350,
                color: Colors.grey.shade100,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cleaning Options', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      title: const Text('Strip EXIF / IPTC / TIFF'),
                      value: _stripExif,
                      onChanged: (val) => setState(() => _stripExif = val ?? true),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      title: const Text('Strip GPS Coordinates'),
                      value: _stripGps,
                      onChanged: (val) => setState(() => _stripGps = val ?? true),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    CheckboxListTile(
                      title: const Text('Strip Color Profiles'),
                      value: _stripColorProfile,
                      onChanged: (val) => setState(() => _stripColorProfile = val ?? true),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const Divider(height: 32),
                    const Text('Output Options', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    RadioListTile<int>(
                      title: const Text('Append _clean'),
                      value: 0,
                      groupValue: _outputOption,
                      onChanged: (val) => setState(() => _outputOption = val ?? 0),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<int>(
                      title: const Text('Overwrite original'),
                      value: 1,
                      groupValue: _outputOption,
                      onChanged: (val) => setState(() => _outputOption = val ?? 1),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<int>(
                      title: const Text('Save to custom folder'),
                      value: 2,
                      groupValue: _outputOption,
                      onChanged: (val) => setState(() => _outputOption = val ?? 2),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_outputOption == 2) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _customFolderPath ?? 'No folder selected',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _pickCustomFolder,
                            child: const Text('Browse'),
                          ),
                        ],
                      ),
                    ],
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade400,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _isProcessing || _queue.isEmpty ? null : _processQueue,
                        icon: _isProcessing
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cleaning_services),
                        label: Text(_isProcessing ? 'Cleaning...' : 'Clean Files', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
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
