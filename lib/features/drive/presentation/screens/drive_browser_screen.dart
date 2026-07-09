import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../../configuration/presentation/providers/config_provider.dart';
import '../../../configuration/domain/entities/token_entity.dart';
import '../../../player/presentation/screens/video_player_screen.dart';
import '../providers/drive_provider.dart';

class ConvertedVideo {
  final String id;
  final String title;
  final String rawUrl;
  final String streamUrl;
  final DateTime timestamp;

  ConvertedVideo({
    required this.id,
    required this.title,
    required this.rawUrl,
    required this.streamUrl,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'rawUrl': rawUrl,
    'streamUrl': streamUrl,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ConvertedVideo.fromJson(Map<String, dynamic> json) => ConvertedVideo(
    id: json['id'] as String,
    title: json['title'] as String,
    rawUrl: json['rawUrl'] as String,
    streamUrl: json['streamUrl'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

class DriveBrowserScreen extends StatefulWidget {
  const DriveBrowserScreen({super.key});

  @override
  State<DriveBrowserScreen> createState() => _DriveBrowserScreenState();
}

class _DriveBrowserScreenState extends State<DriveBrowserScreen> {
  // Converter State
  final TextEditingController _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  List<ConvertedVideo> _history = [];
  bool _isLoadingHistory = true;
  late SharedPreferences _sharedPrefs;

  // Explorer State
  bool _showExplorer = true;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDriveExplorerIfNeeded();
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<TokenEntity?> _onAuthErrorCallback() async {
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    final success = await configProvider.refreshAccessToken();
    return success ? configProvider.tokens : null;
  }

  void _loadDriveExplorerIfNeeded() {
    final configProvider = Provider.of<ConfigProvider>(context, listen: false);
    if (configProvider.isGoogleSignedIn) {
      final driveProvider = Provider.of<DriveProvider>(context, listen: false);
      driveProvider.loadCurrentFolder(
        configProvider.tokens,
        onAuthError: _onAuthErrorCallback,
      );
    }
  }

  Future<void> _loadHistory() async {
    _sharedPrefs = await SharedPreferences.getInstance();
    final jsonStr = _sharedPrefs.getString('gdrive_conversions_history');
    if (jsonStr != null) {
      try {
        final List<dynamic> decoded = json.decode(jsonStr);
        setState(() {
          _history = decoded
              .map((item) => ConvertedVideo.fromJson(item))
              .toList();
          _isLoadingHistory = false;
        });
      } catch (_) {
        setState(() => _isLoadingHistory = false);
      }
    } else {
      setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _saveHistory() async {
    final jsonStr = json.encode(_history.map((e) => e.toJson()).toList());
    await _sharedPrefs.setString('gdrive_conversions_history', jsonStr);
  }

  String? _extractFileId(String url) {
    final regExp1 = RegExp(r'\/file\/d\/([a-zA-Z0-9-_]+)');
    final match1 = regExp1.firstMatch(url);
    if (match1 != null && match1.groupCount >= 1) {
      return match1.group(1);
    }

    final regExp2 = RegExp(r'[?&]id=([a-zA-Z0-9-_]+)');
    final match2 = regExp2.firstMatch(url);
    if (match2 != null && match2.groupCount >= 1) {
      return match2.group(1);
    }

    return null;
  }

  String? _generateStreamUrl(String rawUrl, String apiKey) {
    final fileId = _extractFileId(rawUrl);
    if (fileId == null) return null;
    return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&key=$apiKey';
  }

  void _convertAndPlay(String rawUrl, String apiKey) {
    if (apiKey.isEmpty) {
      _showWarningSnackBar('Please configure your API Key in Settings first.');
      return;
    }

    final streamUrl = _generateStreamUrl(rawUrl, apiKey);
    if (streamUrl == null) {
      _showWarningSnackBar(
        'Invalid Google Drive share link. Unable to parse File ID.',
      );
      return;
    }

    final fileId = _extractFileId(rawUrl)!;
    final title = 'GDrive Video ($fileId)';

    _addToHistory(fileId, title, rawUrl, streamUrl);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            VideoPlayerScreen(url: streamUrl, headers: const {}, title: title),
      ),
    );
  }

  void _convertAndCopy(String rawUrl, String apiKey) {
    if (apiKey.isEmpty) {
      _showWarningSnackBar('Please configure your API Key in Settings first.');
      return;
    }

    final streamUrl = _generateStreamUrl(rawUrl, apiKey);
    if (streamUrl == null) {
      _showWarningSnackBar(
        'Invalid Google Drive share link. Unable to parse File ID.',
      );
      return;
    }

    final fileId = _extractFileId(rawUrl)!;
    _addToHistory(fileId, 'GDrive Video ($fileId)', rawUrl, streamUrl);

    Clipboard.setData(ClipboardData(text: streamUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Streaming link generated and copied! Paste it in VLC or MX Player.',
        ),
        backgroundColor: Colors.teal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _addToHistory(String id, String title, String rawUrl, String streamUrl) {
    setState(() {
      _history.removeWhere((item) => item.id == id);
      _history.insert(
        0,
        ConvertedVideo(
          id: id,
          title: title,
          rawUrl: rawUrl,
          streamUrl: streamUrl,
          timestamp: DateTime.now(),
        ),
      );
      if (_history.length > 20) {
        _history = _history.sublist(0, 20);
      }
    });
    _saveHistory();
  }

  void _deleteHistoryItem(String id) {
    setState(() {
      _history.removeWhere((item) => item.id == id);
    });
    _saveHistory();
  }

  void _showWarningSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final configProvider = Provider.of<ConfigProvider>(context);
    final driveProvider = Provider.of<DriveProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _showExplorer ? 'Google Drive Explorer' : 'GDrive Link Converter',
        ),
        actions: _showExplorer && configProvider.isGoogleSignedIn
            ? [
                IconButton(
                  icon: Icon(
                    driveProvider.isGridView
                        ? Icons.view_list
                        : Icons.grid_view,
                  ),
                  tooltip: driveProvider.isGridView
                      ? 'Switch to List'
                      : 'Switch to Grid',
                  onPressed: driveProvider.toggleViewMode,
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          _buildSegmentControl(theme),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _showExplorer
                  ? _buildExplorerView(configProvider, driveProvider, theme)
                  : _buildConverterView(configProvider, theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentControl(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showExplorer = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _showExplorer
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'Browse Drive',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _showExplorer
                          ? Colors.white
                          : theme.colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showExplorer = false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: !_showExplorer
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'Link Converter',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: !_showExplorer
                          ? Colors.white
                          : theme.colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplorerView(
    ConfigProvider configProvider,
    DriveProvider driveProvider,
    ThemeData theme,
  ) {
    if (!configProvider.isGoogleSignedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 80, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'Google Drive Not Connected',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Connect your Google Account to browse your files, view directory trees, and play files directly within the application.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: configProvider.isLoading
                    ? null
                    : () async {
                        final success = await configProvider.signInWithGoogle();
                        if (success) {
                          driveProvider.loadCurrentFolder(
                            configProvider.tokens,
                            onAuthError: _onAuthErrorCallback,
                          );
                        }
                      },
                icon: const Icon(Icons.login),
                label: const Text('Connect Google Drive'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Search video or folder...',
              prefixIcon: const Icon(Icons.search, color: Colors.orange),
              suffixIcon: _isSearching
                  ? IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () {
                        _searchController.clear();
                        _searchFocusNode.unfocus();
                        setState(() => _isSearching = false);
                        driveProvider.loadCurrentFolder(
                          configProvider.tokens,
                          onAuthError: _onAuthErrorCallback,
                        );
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                setState(() => _isSearching = true);
                driveProvider.search(
                  value.trim(),
                  configProvider.tokens,
                  onAuthError: _onAuthErrorCallback,
                );
              }
            },
          ),
        ),

        // Breadcrumbs & Navigator Control Bar
        _buildBreadcrumbs(driveProvider, configProvider.tokens, theme),

        // Items list/grid
        Expanded(
          child: RefreshIndicator(
            color: Colors.orange,
            onRefresh: () => driveProvider.loadCurrentFolder(
              configProvider.tokens,
              onAuthError: _onAuthErrorCallback,
            ),
            child: _buildExplorerContent(driveProvider, configProvider, theme),
          ),
        ),
      ],
    );
  }

  Widget _buildBreadcrumbs(
    DriveProvider driveProvider,
    TokenEntity token,
    ThemeData theme,
  ) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      alignment: Alignment.centerLeft,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: driveProvider.breadcrumbs.length,
        itemBuilder: (context, index) {
          final breadcrumb = driveProvider.breadcrumbs[index];
          final isLast = index == driveProvider.breadcrumbs.length - 1;

          return Row(
            children: [
              InkWell(
                onTap: isLast
                    ? null
                    : () => driveProvider.navigateToBreadcrumbIndex(
                          index,
                          token,
                          onAuthError: _onAuthErrorCallback,
                        ),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4.0,
                    vertical: 6.0,
                  ),
                  child: Text(
                    breadcrumb.name,
                    style: TextStyle(
                      color: isLast
                          ? Colors.orange
                          : theme.colorScheme.onSurface.withOpacity(0.6),
                      fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExplorerContent(
    DriveProvider driveProvider,
    ConfigProvider configProvider,
    ThemeData theme,
  ) {
    if (driveProvider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.orange),
      );
    }

    if (driveProvider.errorMessage.isNotEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            padding: const EdgeInsets.all(24.0),
            margin: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Failed to fetch files',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  driveProvider.errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => driveProvider.loadCurrentFolder(
                    configProvider.tokens,
                    onAuthError: _onAuthErrorCallback,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (driveProvider.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 80),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.folder_open, color: Colors.white24, size: 64),
                const SizedBox(height: 16),
                Text(
                  _isSearching ? 'No results found' : 'This folder is empty',
                  style: const TextStyle(color: Colors.white54, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return driveProvider.isGridView
        ? _buildGridContent(driveProvider, configProvider, theme)
        : _buildListContent(driveProvider, configProvider, theme);
  }

  Widget _buildListContent(
    DriveProvider driveProvider,
    ConfigProvider configProvider,
    ThemeData theme,
  ) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: driveProvider.items.length,
      itemBuilder: (context, index) {
        final item = driveProvider.items[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: Colors.white.withOpacity(0.01),
          child: ListTile(
            leading: item.isFolder
                ? const Icon(Icons.folder, color: Colors.amber, size: 36)
                : const Icon(
                    Icons.play_circle_fill,
                    color: Colors.orange,
                    size: 36,
                  ),
            title: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              item.isFolder
                  ? 'Folder'
                  : '${item.sizeString} • ${item.formattedDate}',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
            trailing: item.isFolder
                ? const Icon(Icons.chevron_right, color: Colors.white30)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.copy,
                          color: Colors.tealAccent,
                          size: 20,
                        ),
                        tooltip: 'Copy stream link',
                        onPressed: () {
                          final source = driveProvider.getStreamSource(
                            item,
                            configProvider.tokens,
                          );
                          Clipboard.setData(ClipboardData(text: source.url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Direct streaming link copied!'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
            onTap: () {
              if (item.isFolder) {
                driveProvider.navigateToFolder(
                  item,
                  configProvider.tokens,
                  onAuthError: _onAuthErrorCallback,
                );
              } else {
                final source = driveProvider.getStreamSource(
                  item,
                  configProvider.tokens,
                );
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerScreen(
                      url: source.url,
                      headers: source.headers,
                      title: source.title,
                    ),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildGridContent(
    DriveProvider driveProvider,
    ConfigProvider configProvider,
    ThemeData theme,
  ) {
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: driveProvider.items.length,
      itemBuilder: (context, index) {
        final item = driveProvider.items[index];

        return Card(
          margin: EdgeInsets.zero,
          color: Colors.white.withOpacity(0.01),
          child: InkWell(
            onTap: () {
              if (item.isFolder) {
                driveProvider.navigateToFolder(
                  item,
                  configProvider.tokens,
                  onAuthError: _onAuthErrorCallback,
                );
              } else {
                final source = driveProvider.getStreamSource(
                  item,
                  configProvider.tokens,
                );
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerScreen(
                      url: source.url,
                      headers: source.headers,
                      title: source.title,
                    ),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      item.isFolder
                          ? const Icon(
                              Icons.folder,
                              color: Colors.amber,
                              size: 40,
                            )
                          : const Icon(
                              Icons.play_circle_fill,
                              color: Colors.orange,
                              size: 40,
                            ),
                      if (!item.isFolder)
                        IconButton(
                          icon: const Icon(
                            Icons.copy,
                            color: Colors.tealAccent,
                            size: 18,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            final source = driveProvider.getStreamSource(
                              item,
                              configProvider.tokens,
                            );
                            Clipboard.setData(ClipboardData(text: source.url));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Streaming link copied!'),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.isFolder ? 'Folder' : item.sizeString,
                    style: const TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConverterView(ConfigProvider configProvider, ThemeData theme) {
    final apiKey = configProvider.tokens.apiKey;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.transform,
                          color: Colors.orange,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Drive Link to Streaming Link',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Paste your raw Google Drive sharing link here. The app will extract the File ID and automatically append your API Token to create a direct streaming link.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _urlController,
                      maxLines: 3,
                      minLines: 1,
                      decoration: const InputDecoration(
                        labelText: 'Google Drive Sharing Link',
                        hintText: 'https://drive.google.com/file/d/.../view',
                        prefixIcon: Icon(
                          Icons.insert_link,
                          color: Colors.orange,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a link';
                        }
                        if (_extractFileId(value.trim()) == null) {
                          return 'Could not parse a valid Google Drive File ID';
                        }
                        return null;
                      },
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              if (_formKey.currentState!.validate()) {
                                _convertAndCopy(
                                  _urlController.text.trim(),
                                  apiKey,
                                );
                              }
                            },
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text(
                              'Copy Stream Link',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.tealAccent,
                              side: const BorderSide(color: Colors.teal),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              if (_formKey.currentState!.validate()) {
                                _convertAndPlay(
                                  _urlController.text.trim(),
                                  apiKey,
                                );
                              }
                            },
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text(
                              'Play in App',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: Colors.blueGrey.shade900.withOpacity(0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.blueGrey.shade800, width: 1),
              ),
              child: const Padding(
                padding: EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(Icons.audiotrack, color: Colors.tealAccent, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Multi-Language & Audio Tracks:\n'
                        'To select alternative audio languages, use "Copy Stream Link" and open the URL in external VLC or MX Player.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Conversion History', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            if (_isLoadingHistory)
              const Center(
                child: CircularProgressIndicator(color: Colors.orange),
              )
            else if (_history.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: const Column(
                  children: [
                    Icon(
                      Icons.history_toggle_off,
                      color: Colors.white24,
                      size: 48,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No conversions yet',
                      style: TextStyle(color: Colors.white38),
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  final item = _history[index];
                  return Card(
                    color: Colors.white.withOpacity(0.01),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(
                        Icons.video_collection,
                        color: Colors.orange,
                      ),
                      title: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'ID: ${item.id}\nRaw URL: ${item.rawUrl}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.copy,
                              color: Colors.tealAccent,
                              size: 20,
                            ),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: item.streamUrl),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Stream URL copied!'),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            onPressed: () => _deleteHistoryItem(item.id),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => VideoPlayerScreen(
                              url: item.streamUrl,
                              headers: const {},
                              title: item.title,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
