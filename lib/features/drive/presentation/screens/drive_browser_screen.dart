import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../../configuration/presentation/providers/config_provider.dart';
import '../../../player/presentation/screens/video_player_screen.dart';

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
  final TextEditingController _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  List<ConvertedVideo> _history = [];
  bool _isLoadingHistory = true;
  late SharedPreferences _sharedPrefs;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    _sharedPrefs = await SharedPreferences.getInstance();
    final jsonStr = _sharedPrefs.getString('gdrive_conversions_history');
    if (jsonStr != null) {
      try {
        final List<dynamic> decoded = json.decode(jsonStr);
        setState(() {
          _history = decoded.map((item) => ConvertedVideo.fromJson(item)).toList();
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
    // Regex for: /file/d/FILE_ID/
    final regExp1 = RegExp(r'\/file\/d\/([a-zA-Z0-9-_]+)');
    final match1 = regExp1.firstMatch(url);
    if (match1 != null && match1.groupCount >= 1) {
      return match1.group(1);
    }

    // Regex for: ?id=FILE_ID or &id=FILE_ID
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
      _showWarningSnackBar('Invalid Google Drive share link. Unable to parse File ID.');
      return;
    }

    final fileId = _extractFileId(rawUrl)!;
    final title = 'GDrive Video ($fileId)';

    _addToHistory(fileId, title, rawUrl, streamUrl);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          url: streamUrl,
          headers: const {},
          title: title,
        ),
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
      _showWarningSnackBar('Invalid Google Drive share link. Unable to parse File ID.');
      return;
    }

    final fileId = _extractFileId(rawUrl)!;
    _addToHistory(fileId, 'GDrive Video ($fileId)', rawUrl, streamUrl);

    Clipboard.setData(ClipboardData(text: streamUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Streaming link generated and copied! Paste it in VLC or MX Player.'),
        backgroundColor: Colors.teal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _addToHistory(String id, String title, String rawUrl, String streamUrl) {
    // Avoid duplicates
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
      // Limit to 20 conversions
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
    final apiKey = configProvider.tokens.apiKey;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GDrive Link Converter'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Converter Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.transform, color: Colors.orange, size: 24),
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
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _urlController,
                        maxLines: 3,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: 'Google Drive Sharing Link',
                          hintText: 'https://drive.google.com/file/d/.../view',
                          prefixIcon: Icon(Icons.insert_link, color: Colors.orange),
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
                                  _convertAndCopy(_urlController.text.trim(), apiKey);
                                }
                              },
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Copy Stream Link', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.tealAccent,
                                side: const BorderSide(color: Colors.teal),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                if (_formKey.currentState!.validate()) {
                                  _convertAndPlay(_urlController.text.trim(), apiKey);
                                }
                              },
                              icon: const Icon(Icons.play_arrow, size: 18),
                              label: const Text('Play in App', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

              // Audio / Subtitles Track Info Card
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
                          style: TextStyle(fontSize: 12, height: 1.4, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Converted History
              Text(
                'Conversion History',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 10),

              if (_isLoadingHistory)
                const Center(child: CircularProgressIndicator(color: Colors.orange))
              else if (_history.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: const Column(
                    children: [
                      Icon(Icons.history_toggle_off, color: Colors.white24, size: 48),
                      SizedBox(height: 12),
                      Text('No conversions yet', style: TextStyle(color: Colors.white38)),
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
                        leading: const Icon(Icons.video_collection, color: Colors.orange),
                        title: Text(
                          item.title,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'ID: ${item.id}\nRaw URL: ${item.rawUrl}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.white38),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy, color: Colors.tealAccent, size: 20),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: item.streamUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Stream URL copied!')),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
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
      ),
    );
  }
}
