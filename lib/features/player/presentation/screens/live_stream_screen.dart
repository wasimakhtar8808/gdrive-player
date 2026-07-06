import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'video_player_screen.dart';

class LiveStreamScreen extends StatefulWidget {
  const LiveStreamScreen({super.key});

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  final TextEditingController _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  List<String> _recentStreams = [];
  late SharedPreferences _sharedPrefs;
  bool _isLoadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _loadRecentStreams();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentStreams() async {
    _sharedPrefs = await SharedPreferences.getInstance();
    setState(() {
      _recentStreams = _sharedPrefs.getStringList('recent_streams_history') ?? [];
      _isLoadingPrefs = false;
    });
  }

  Future<void> _saveRecentStream(String url) async {
    if (url.trim().isEmpty) return;
    
    // Remove if already exists to push it to the top
    _recentStreams.remove(url);
    _recentStreams.insert(0, url);
    
    // Limit history to 15 items
    if (_recentStreams.length > 15) {
      _recentStreams = _recentStreams.sublist(0, 15);
    }

    setState(() {});
    await _sharedPrefs.setStringList('recent_streams_history', _recentStreams);
  }

  Future<void> _deleteRecentStream(String url) async {
    setState(() {
      _recentStreams.remove(url);
    });
    await _sharedPrefs.setStringList('recent_streams_history', _recentStreams);
  }

  void _playStream(String url) {
    if (url.trim().isEmpty) return;
    _saveRecentStream(url);
    
    // Extract title from URL basename or fallback
    String title = 'Network Stream';
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.isNotEmpty) {
        title = uri.pathSegments.last;
      }
    } catch (_) {}

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          url: url,
          headers: const {},
          title: title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Stream'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.stream, color: Colors.cyan, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'Live & Network Streaming',
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Paste any HTTP/HTTPS direct video URL or live stream feed (HLS .m3u8, MP4, MKV, etc.) to play it with custom gesture controls.',
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // URL Input Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _urlController,
                        maxLines: 2,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: 'Network Stream URL',
                          hintText: 'http://example.com/live/stream.m3u8',
                          prefixIcon: Icon(Icons.link, color: Colors.cyan),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a valid URL';
                          }
                          if (!value.trim().startsWith('http://') && !value.trim().startsWith('https://')) {
                            return 'URL must start with http:// or https://';
                          }
                          return null;
                        },
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            _playStream(_urlController.text.trim());
                          }
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play Network Stream'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyan.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Recent Streams Title
              Text(
                'Recent Streams',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 10),

              // History list
              if (_isLoadingPrefs)
                const Center(child: CircularProgressIndicator(color: Colors.cyan))
              else if (_recentStreams.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: const Column(
                    children: [
                      Icon(Icons.history, color: Colors.white24, size: 48),
                      SizedBox(height: 12),
                      Text('No streaming history', style: TextStyle(color: Colors.white38)),
                    ],
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentStreams.length,
                  itemBuilder: (context, index) {
                    final streamUrl = _recentStreams[index];
                    return Card(
                      color: Colors.white.withOpacity(0.02),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.play_circle_outline, color: Colors.cyan),
                        title: Text(
                          streamUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          onPressed: () => _deleteRecentStream(streamUrl),
                        ),
                        onTap: () => _playStream(streamUrl),
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
