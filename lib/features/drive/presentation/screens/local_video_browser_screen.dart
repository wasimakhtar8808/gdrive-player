import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../player/presentation/screens/video_player_screen.dart';

class LocalVideoBrowserScreen extends StatefulWidget {
  const LocalVideoBrowserScreen({super.key});

  @override
  State<LocalVideoBrowserScreen> createState() => _LocalVideoBrowserScreenState();
}

class _LocalVideoBrowserScreenState extends State<LocalVideoBrowserScreen> {
  final Map<String, List<File>> _folderVideosMap = {};
  List<String> _folders = [];
  String? _selectedFolder;
  bool _permissionGranted = false;
  bool _isLoading = true;
  String _loadingMessage = 'Requesting storage permission...';

  @override
  void initState() {
    super.initState();
    _requestPermissionAndScan();
  }

  Future<void> _requestPermissionAndScan() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Requesting storage permission...';
    });

    // Request permissions
    final status = await Permission.storage.request();
    var manageStatus = PermissionStatus.granted;
    
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.status.isDenied) {
        manageStatus = await Permission.manageExternalStorage.request();
      } else {
        manageStatus = await Permission.manageExternalStorage.status;
      }
    }

    if (status.isGranted || manageStatus.isGranted) {
      setState(() {
        _permissionGranted = true;
        _loadingMessage = 'Scanning device storage for videos...';
      });
      await _scanForVideos();
    } else {
      setState(() {
        _permissionGranted = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _scanForVideos() async {
    _folderVideosMap.clear();
    _folders.clear();

    try {
      final root = Directory('/storage/emulated/0');
      await _scanDirectory(root);

      setState(() {
        _folders = _folderVideosMap.keys.toList();
        // Sort folders by name alphabetically
        _folders.sort((a, b) {
          final aName = a.split('/').last.toLowerCase();
          final bName = b.split('/').last.toLowerCase();
          return aName.compareTo(bName);
        });
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning storage: $e')),
        );
      }
    }
  }

  Future<void> _scanDirectory(Directory dir) async {
    try {
      final Stream<FileSystemEntity> stream = dir.list(recursive: false, followLinks: false);
      await for (final entity in stream) {
        if (entity is Directory) {
          final dirName = entity.path.split('/').last;
          // Skip hidden folders and system directories (Android, obb, data) to make scan very fast
          if (dirName.startsWith('.') || entity.path.contains('/Android') || dirName.toLowerCase() == 'android') {
            continue;
          }
          await _scanDirectory(entity);
        } else if (entity is File) {
          final path = entity.path.toLowerCase();
          if (path.endsWith('.mp4') ||
              path.endsWith('.mkv') ||
              path.endsWith('.webm') ||
              path.endsWith('.avi') ||
              path.endsWith('.mov') ||
              path.endsWith('.flv') ||
              path.endsWith('.3gp')) {
            final parentPath = entity.parent.path;
            if (!_folderVideosMap.containsKey(parentPath)) {
              _folderVideosMap[parentPath] = [];
            }
            _folderVideosMap[parentPath]!.add(entity);
          }
        }
      }
    } catch (_) {
      // Ignore permission-restricted directories
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedFolder == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          setState(() {
            _selectedFolder = null;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_selectedFolder == null
              ? 'Local Video Folders'
              : _selectedFolder!.split('/').last),
          leading: _selectedFolder != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _selectedFolder = null;
                    });
                  },
                )
              : const Icon(Icons.video_library),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _requestPermissionAndScan,
            ),
          ],
        ),
        body: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.orange),
                    const SizedBox(height: 16),
                    Text(_loadingMessage, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            : !_permissionGranted
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.folder_off, size: 64, color: Colors.orange),
                          const SizedBox(height: 16),
                          const Text(
                            'Storage Permission Required',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Please grant storage access permission to browse and play local videos from your device storage.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _requestPermissionAndScan,
                            icon: const Icon(Icons.settings),
                            label: const Text('Grant Permission'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _selectedFolder == null
                    ? _folders.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.video_library_outlined, size: 48, color: Colors.grey),
                                SizedBox(height: 12),
                                Text('No folders containing videos found', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _folders.length,
                            itemBuilder: (context, index) {
                              final folderPath = _folders[index];
                              final folderName = folderPath.split('/').last;
                              final videoCount = _folderVideosMap[folderPath]?.length ?? 0;

                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                color: const Color(0xFF161B22),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                child: ListTile(
                                  leading: const Icon(Icons.folder, color: Colors.amber, size: 40),
                                  title: Text(
                                    folderName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                  subtitle: Text(
                                    '$videoCount video${videoCount > 1 ? 's' : ''}\n$folderPath',
                                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                                  ),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.chevron_right, color: Colors.orange),
                                  onTap: () {
                                    setState(() {
                                      _selectedFolder = folderPath;
                                    });
                                  },
                                ),
                              );
                            },
                          )
                    : ListView.builder(
                        itemCount: _folderVideosMap[_selectedFolder]?.length ?? 0,
                        itemBuilder: (context, index) {
                          final file = _folderVideosMap[_selectedFolder]![index];
                          final name = file.path.split('/').last;
                          final size = file.lengthSync();

                          return ListTile(
                            leading: const Icon(Icons.local_movies, color: Colors.orange, size: 36),
                            title: Text(name, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(_formatSize(size), style: const TextStyle(color: Colors.grey)),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => VideoPlayerScreen(
                                    url: file.path,
                                    headers: const {},
                                    title: name,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
      ),
    );
  }
}
