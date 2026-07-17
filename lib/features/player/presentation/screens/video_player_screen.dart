import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/datasources/playback_tracker.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String url;
  final Map<String, String> headers;
  final String title;

  const VideoPlayerScreen({
    super.key,
    required this.url,
    required this.headers,
    required this.title,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

enum PlayerAspectRatio { original, fit, fill, stretch, sixteenNine, fourThree }

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VlcPlayerController? _controller;
  bool _isInitialized = false;
  bool _isControllerCreated = false;
  bool _hasError = false;
  String _errorMessage = '';

  // Controls UI visibility
  bool _showControls = true;
  Timer? _controlsTimer;

  // Custom Gestures State
  double _brightness = 0.8; // Virtual brightness (1.0 - opacity of dark overlay)
  double _volume = 1.0;
  bool _isDraggingVolume = false;
  bool _isDraggingBrightness = false;
  bool _isDraggingSeek = false;
  
  // Seek Gesture Variables
  Duration _dragSeekPosition = Duration.zero;
  Duration _initialSeekPosition = Duration.zero;
  int _seekChangeSeconds = 0;

  // Player Settings
  PlayerAspectRatio _aspectRatio = PlayerAspectRatio.fit;
  double _playbackSpeed = 1.0;
  bool _isLocked = false;

  int _lastSavedSecond = 0;

  // Center Indicators, Audio/Subtitle tracks and HW/SW decoding
  String? _doubleTapFeedback;
  Timer? _doubleTapFeedbackTimer;
  String? _frameChangeText;
  Timer? _frameChangeTimer;
  
  Map<int, String> _audioTracks = {};
  Map<int, String> _subtitleTracks = {};
  int _activeAudioTrack = -1;
  int _activeSubtitleTrack = -1;
  bool _isFetchingTracks = false;
  bool _useHardwareDecoding = true;

  String get _videoKey {
    final regExp = RegExp(r'\/files\/([a-zA-Z0-9-_]+)');
    final match = regExp.firstMatch(widget.url);
    if (match != null && match.groupCount >= 1) {
      return match.group(1)!;
    }
    return widget.url;
  }

  @override
  void initState() {
    super.initState();
    // Force Landscape for video playback
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    // Enable Screen Wake Lock
    WakelockPlus.enable();
    
    _initializePlayer();
  }

  Future<void> _initializePlayer({Duration startAt = Duration.zero}) async {
    if (_isControllerCreated && _controller != null) {
      try {
        _controller!.removeListener(_onPlayerUpdate);
        _controller!.dispose();
      } catch (_) {}
      _isControllerCreated = false;
    }

    setState(() {
      _isInitialized = false;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _useHardwareDecoding = prefs.getBool('player_hw_decoding') ?? true;

      final acceleration = _useHardwareDecoding ? HwAcc.full : HwAcc.disabled;

      if (widget.url.startsWith('http')) {
        _controller = VlcPlayerController.network(
          widget.url,
          hwAcc: acceleration,
          autoPlay: false,
        );
      } else {
        _controller = VlcPlayerController.file(
          File(widget.url),
          hwAcc: acceleration,
          autoPlay: false,
        );
      }

      _isControllerCreated = true;
      _isFetchingTracks = false;
      _audioTracks = {};
      _subtitleTracks = {};

      _controller!.addListener(_onPlayerUpdate);

      // Trigger build so VlcPlayer widget is immediately mounted in tree
      setState(() {});

      _controller!.addOnInitListener(() async {
        if (!mounted) return;

        setState(() {
          _isInitialized = true;
        });

        // Give native wrapper some time to build
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted || _controller == null) return;

        int savedSeconds = 0;
        if (startAt != Duration.zero) {
          savedSeconds = startAt.inSeconds;
        } else {
          try {
            savedSeconds = await PlaybackTracker.getPosition(_videoKey);
          } catch (_) {}
        }
        if (!mounted || _controller == null) return;

        if (savedSeconds > 0) {
          if (startAt != Duration.zero) {
            try {
              await _controller?.seekTo(Duration(seconds: savedSeconds));
              await _controller?.play();
            } catch (_) {}
            _startControlsTimer();
          } else {
            _showResumeDialog(savedSeconds);
          }
        } else {
          try {
            await _controller?.play();
          } catch (_) {}
          _startControlsTimer();
        }
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load video: ${e.toString()}';
      });
    }
  }

  void _showResumeDialog(int savedSeconds) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Resume Playback?'),
          content: Text(
            'Would you like to resume playing this video from where you left off at ${_formatDuration(Duration(seconds: savedSeconds))}?',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await _controller?.seekTo(Duration.zero);
                  await _controller?.play();
                } catch (_) {}
                _startControlsTimer();
              },
              child: const Text('Start Over'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await _controller?.seekTo(Duration(seconds: savedSeconds));
                  await _controller?.play();
                } catch (_) {}
                _startControlsTimer();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Resume'),
            ),
          ],
        );
      },
    );
  }

  void _onPlayerUpdate() {
    if (!mounted || _controller == null) return;
    
    final value = _controller!.value;
    if (value.hasError) {
      setState(() {
        _hasError = true;
        _errorMessage = value.errorDescription ?? 'An error occurred during playback';
      });
      return;
    }

    if (value.isInitialized) {
      final currentSecond = value.position.inSeconds;
      if (value.isPlaying && (currentSecond - _lastSavedSecond).abs() >= 3) {
        _lastSavedSecond = currentSecond;
        PlaybackTracker.savePosition(_videoKey, currentSecond);
      }
      
      if (value.position >= value.duration - const Duration(seconds: 5)) {
        PlaybackTracker.clearPosition(_videoKey);
      }

      // Fetch tracks dynamically once initialized
      if (_audioTracks.isEmpty && !_isFetchingTracks) {
        _isFetchingTracks = true;
        _fetchTracks();
      }
    }
    setState(() {});
  }

  Future<void> _fetchTracks() async {
    if (_controller == null) return;
    try {
      final audios = await _controller!.getAudioTracks();
      if (!mounted || _controller == null) return;
      final subs = await _controller!.getSpuTracks();
      if (!mounted || _controller == null) return;
      final currentAudio = await _controller!.getAudioTrack();
      if (!mounted || _controller == null) return;
      final currentSub = await _controller!.getSpuTrack();
      if (!mounted || _controller == null) return;
      setState(() {
        _audioTracks = audios;
        _subtitleTracks = subs;
        _activeAudioTrack = currentAudio ?? -1;
        _activeSubtitleTrack = currentSub ?? -1;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _doubleTapFeedbackTimer?.cancel();
    _frameChangeTimer?.cancel();
    
    if (_controller != null) {
      try {
        _controller!.removeListener(_onPlayerUpdate);
      } catch (_) {}

      try {
        if (_controller!.value.isInitialized) {
          final currentPos = _controller!.value.position;
          final totalDur = _controller!.value.duration;
          if (currentPos < totalDur - const Duration(seconds: 5)) {
            PlaybackTracker.savePosition(_videoKey, currentPos.inSeconds);
          } else {
            PlaybackTracker.clearPosition(_videoKey);
          }
        }
      } catch (_) {}

      try {
        _controller!.dispose();
      } catch (_) {}
    }
    
    // Restore default orientation and System UI
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    
    // Disable Screen Wake Lock
    WakelockPlus.disable();
    
    super.dispose();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    if (_showControls && !_isLocked) {
      _controlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _controller != null && _controller!.value.isPlaying) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _toggleControls() {
    if (_isLocked) {
      setState(() {
        _showControls = !_showControls;
      });
      _startControlsTimer();
      return;
    }
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startControlsTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  double get _blackOverlayOpacity => (1.0 - _brightness).clamp(0.0, 0.85);

  void _handleVerticalDragUpdate(DragUpdateDetails details, double screenWidth, double screenHeight) {
    if (_isLocked || !_isInitialized || _controller == null) return;
    
    final localX = details.localPosition.dx;
    final deltaY = details.primaryDelta ?? 0;

    setState(() {
      _showControls = false;
      
      if (localX < screenWidth / 2) {
        _isDraggingBrightness = true;
        _isDraggingVolume = false;
        _brightness = (_brightness - (deltaY / screenHeight)).clamp(0.1, 1.0);
      } else {
        _isDraggingVolume = true;
        _isDraggingBrightness = false;
        _volume = (_volume - (deltaY / screenHeight)).clamp(0.0, 1.0);
        try {
          _controller!.setVolume((_volume * 100).round()); // VLC volume ranges 0-100
        } catch (_) {}
      }
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_isLocked || !_isInitialized || _controller == null) return;
    setState(() {
      _isDraggingVolume = false;
      _isDraggingBrightness = false;
    });
    _startControlsTimer();
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (_isLocked || !_isInitialized || _controller == null) return;
    setState(() {
      _isDraggingSeek = true;
      _initialSeekPosition = _controller!.value.position;
      _dragSeekPosition = _initialSeekPosition;
      _seekChangeSeconds = 0;
      _showControls = false;
    });
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details, double screenWidth) {
    if (_isLocked || !_isInitialized || _controller == null) return;
    
    final deltaX = details.primaryDelta ?? 0;
    final double scaleRatio = 180 / screenWidth;
    final int changeSeconds = (deltaX * scaleRatio).round();

    setState(() {
      _seekChangeSeconds += changeSeconds;
      final totalSeconds = _initialSeekPosition.inSeconds + _seekChangeSeconds;
      final clampedSeconds = totalSeconds.clamp(0, _controller!.value.duration.inSeconds);
      _dragSeekPosition = Duration(seconds: clampedSeconds);
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (_isLocked || !_isInitialized || _controller == null) return;
    setState(() {
      _isDraggingSeek = false;
    });
    try {
      _controller!.seekTo(_dragSeekPosition);
    } catch (_) {}
    _startControlsTimer();
  }

  Duration _clampDuration(Duration pos, Duration max) {
    if (pos < Duration.zero) return Duration.zero;
    if (pos > max) return max;
    return pos;
  }

  void _doubleTapLeft() {
    if (_isLocked || !_isInitialized || _controller == null) return;
    final newPos = _controller!.value.position - const Duration(seconds: 10);
    try {
      _controller!.seekTo(_clampDuration(newPos, _controller!.value.duration));
    } catch (_) {}
    _showFeedbackIndicator('Rewind 10s');
  }

  void _doubleTapRight() {
    if (_isLocked || !_isInitialized || _controller == null) return;
    final newPos = _controller!.value.position + const Duration(seconds: 10);
    try {
      _controller!.seekTo(_clampDuration(newPos, _controller!.value.duration));
    } catch (_) {}
    _showFeedbackIndicator('Forward 10s');
  }

  void _showFeedbackIndicator(String message) {
    _doubleTapFeedbackTimer?.cancel();
    setState(() {
      _doubleTapFeedback = message;
    });
    _doubleTapFeedbackTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _doubleTapFeedback = null;
        });
      }
    });
  }

  double get _videoRatio {
    if (_controller != null && _controller!.value.size.width > 0 && _controller!.value.size.height > 0) {
      return _controller!.value.size.width / _controller!.value.size.height;
    }
    return 16 / 9;
  }

  Widget _buildAspectRatioWrapper(Widget child) {
    if (!_isInitialized) return child;
    
    final double videoRatio = _videoRatio;
    BoxFit fit;
    switch (_aspectRatio) {
      case PlayerAspectRatio.original:
        return Center(
          child: AspectRatio(
            aspectRatio: videoRatio,
            child: child,
          ),
        );
      case PlayerAspectRatio.fit:
        fit = BoxFit.contain;
        break;
      case PlayerAspectRatio.fill:
        fit = BoxFit.cover;
        break;
      case PlayerAspectRatio.stretch:
        fit = BoxFit.fill;
        break;
      case PlayerAspectRatio.sixteenNine:
        return Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: child,
          ),
        );
      case PlayerAspectRatio.fourThree:
        return Center(
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: child,
          ),
        );
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: fit,
        child: SizedBox(
          width: _controller != null && _controller!.value.size.width > 0 ? _controller!.value.size.width : 1920,
          height: _controller != null && _controller!.value.size.height > 0 ? _controller!.value.size.height : 1080,
          child: child,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Future<bool> _handleBack() async {
    if (_isLocked) return false;
    _controlsTimer?.cancel();
    if (_controller != null) {
      try {
        _controller!.removeListener(_onPlayerUpdate);
      } catch (_) {}
      try {
        await _controller!.pause();
      } catch (_) {}
    }
    
    // Force portrait orientation immediately before popping
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    
    // Brief delay to allow the device to begin rotating back to portrait
    await Future.delayed(const Duration(milliseconds: 150));
    
    if (mounted) {
      Navigator.of(context).pop();
    }
    return true;
  }

  Future<void> _toggleHardwareDecoding() async {
    final currentPosition = _isInitialized && _controller != null
        ? _controller!.value.position
        : Duration.zero;
    
    _controlsTimer?.cancel();
    if (_controller != null) {
      try {
        _controller!.removeListener(_onPlayerUpdate);
      } catch (_) {}
      try {
        await _controller!.dispose();
      } catch (_) {}
      _isControllerCreated = false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('player_hw_decoding', !_useHardwareDecoding);

    _showFrameChangeIndicator(!_useHardwareDecoding ? 'Hardware Decoding Enabled' : 'Software Decoding Enabled');

    await _initializePlayer(startAt: currentPosition);
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
          // 1. Video Render Area
          GestureDetector(
            onTap: _toggleControls,
            onVerticalDragUpdate: (details) => _handleVerticalDragUpdate(details, size.width, size.height),
            onVerticalDragEnd: _handleVerticalDragEnd,
            onHorizontalDragStart: _handleHorizontalDragStart,
            onHorizontalDragUpdate: (details) => _handleHorizontalDragUpdate(details, size.width),
            onHorizontalDragEnd: _handleHorizontalDragEnd,
            child: Stack(
              children: [
                if (_hasError)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 60),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => _initializePlayer(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_isControllerCreated && _controller != null)
                  _buildAspectRatioWrapper(
                    VlcPlayer(
                      controller: _controller!,
                      aspectRatio: _videoRatio,
                      placeholder: const Center(
                        child: CircularProgressIndicator(color: Colors.orange),
                      ),
                    ),
                  )
                else
                  const Center(
                    child: CircularProgressIndicator(color: Colors.orange),
                  ),

                // 2. Direct Tap Areas for Double Taps (left third / right third)
                if (!_isLocked && _isInitialized)
                  Positioned.fill(
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onDoubleTap: _doubleTapLeft,
                            child: const SizedBox.expand(),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onDoubleTap: () {
                              if (_controller == null) return;
                              setState(() {
                                try {
                                  if (_controller!.value.isPlaying) {
                                    _controller!.pause();
                                  } else {
                                    _controller!.play();
                                  }
                                } catch (_) {}
                              });
                            },
                            child: const SizedBox.expand(),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onDoubleTap: _doubleTapRight,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 3. Virtual Brightness Overlay (Black sheet)
                IgnorePointer(
                  child: AnimatedContainer(
                    duration: Duration.zero,
                    color: Colors.black.withOpacity(_blackOverlayOpacity),
                  ),
                ),
              ],
            ),
          ),

          // 4. Custom Swipe Overlay HUD Indicators
          if (_isDraggingVolume)
            Center(
              child: _buildSwipeIndicator(
                icon: _volume == 0
                    ? Icons.volume_mute
                    : _volume < 0.5
                        ? Icons.volume_down
                        : Icons.volume_up,
                label: 'Volume',
                value: _volume,
              ),
            ),
          if (_isDraggingBrightness)
            Center(
              child: _buildSwipeIndicator(
                icon: Icons.brightness_6,
                label: 'Brightness',
                value: _brightness,
              ),
            ),
          if (_isDraggingSeek)
            Center(
              child: _buildSeekSwipeIndicator(),
            ),

          // Double-Tap and Frame Change Center Indicators (No background, center text)
          if (_doubleTapFeedback != null)
            Center(
              child: IgnorePointer(
                child: Text(
                  _doubleTapFeedback!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(blurRadius: 8, color: Colors.black87, offset: Offset(0, 2)),
                    ],
                  ),
                ),
              ),
            ),
          if (_frameChangeText != null)
            Center(
              child: IgnorePointer(
                child: Text(
                  _frameChangeText!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(blurRadius: 10, color: Colors.black, offset: Offset(0, 2)),
                    ],
                  ),
                ),
              ),
            ),

          // 5. Player HUD Controls
          if (_showControls && _isInitialized && _isControllerCreated) _buildHUD(context),
        ],
      ),
     ),
    );
  }

  Widget _buildSwipeIndicator({required IconData icon, required String label, required double value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.orange, size: 48),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 12),
          SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('${(value * 100).round()}%',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSeekSwipeIndicator() {
    final seekPosStr = _formatDuration(_dragSeekPosition);
    final totalDurStr = _controller != null ? _formatDuration(_controller!.value.duration) : '';
    final diffSign = _seekChangeSeconds >= 0 ? '+' : '';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _seekChangeSeconds >= 0 ? Icons.fast_forward : Icons.fast_rewind,
            color: Colors.tealAccent,
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            '$seekPosStr / $totalDurStr',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '$diffSign${_seekChangeSeconds}s',
            style: const TextStyle(color: Colors.tealAccent, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildHUD(BuildContext context) {
    return Positioned.fill(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top Bar
          Container(
            height: 70,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.black.withOpacity(0.0)],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                 IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _handleBack,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!_isLocked && _isInitialized) ...[
                  // Decoding hardware mode
                  _buildDecoderButton(),
                  // Audio Track selector
                  _buildAudioTrackButton(),
                  // Subtitles selector
                  _buildSubtitlesButton(),
                  // Playback speed selector
                  _buildSpeedButton(),
                  // Aspect Ratio selector
                  _buildAspectRatioButton(),
                ],
              ],
            ),
          ),

          // Middle Screen: Lock Button on left
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: Icon(
                        _isLocked ? Icons.lock : Icons.lock_open,
                        color: _isLocked ? Colors.orange : Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          _isLocked = !_isLocked;
                        });
                        _startControlsTimer();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Bar
          if (!_isLocked)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.black.withOpacity(0.0)],
                ),
              ),
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Timeline / Slider
                  if (_isInitialized && _controller != null)
                    Row(
                      children: [
                        Text(
                          _formatDuration(_controller!.value.position),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.orange,
                              inactiveTrackColor: Colors.white24,
                              trackHeight: 4,
                              thumbColor: Colors.orange,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            ),
                            child: Slider(
                              value: _controller!.value.position.inMilliseconds.toDouble(),
                              min: 0.0,
                              max: _controller!.value.duration.inMilliseconds.toDouble(),
                              onChanged: (val) {
                                try {
                                  _controller?.seekTo(Duration(milliseconds: val.toInt()));
                                } catch (_) {}
                              },
                              onChangeStart: (val) {
                                _controlsTimer?.cancel();
                              },
                              onChangeEnd: (val) {
                                _startControlsTimer();
                              },
                            ),
                          ),
                        ),
                        Text(
                          _formatDuration(_controller!.value.duration),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),

                  // Control actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10, color: Colors.white, size: 28),
                        onPressed: () {
                          if (_controller == null) return;
                          final newPos = _controller!.value.position - const Duration(seconds: 10);
                          try {
                            _controller!.seekTo(_clampDuration(newPos, _controller!.value.duration));
                          } catch (_) {}
                        },
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        icon: Icon(
                          _controller != null && _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                          color: Colors.orange,
                          size: 48,
                        ),
                        onPressed: () {
                          if (_controller == null) return;
                          setState(() {
                            try {
                              if (_controller!.value.isPlaying) {
                                _controller!.pause();
                              } else {
                                _controller!.play();
                              }
                            } catch (_) {}
                          });
                          _startControlsTimer();
                        },
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        icon: const Icon(Icons.forward_10, color: Colors.white, size: 28),
                        onPressed: () {
                          if (_controller == null) return;
                          final newPos = _controller!.value.position + const Duration(seconds: 10);
                          try {
                            _controller!.seekTo(_clampDuration(newPos, _controller!.value.duration));
                          } catch (_) {}
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDecoderButton() {
    return IconButton(
      icon: Icon(
        _useHardwareDecoding ? Icons.developer_board : Icons.memory,
        color: _useHardwareDecoding ? Colors.green : Colors.white,
      ),
      tooltip: _useHardwareDecoding ? 'Decoder: HW (Hardware)' : 'Decoder: SW (Software)',
      onPressed: _toggleHardwareDecoding,
    );
  }

  Widget _buildAudioTrackButton() {
    return PopupMenuButton<int>(
      initialValue: _activeAudioTrack,
      icon: const Icon(Icons.audiotrack, color: Colors.white),
      tooltip: 'Audio Track / Voice',
      onSelected: (trackId) async {
        try {
          await _controller?.setAudioTrack(trackId);
        } catch (_) {}
        setState(() {
          _activeAudioTrack = trackId;
        });
        final name = _audioTracks[trackId] ?? 'Track $trackId';
        _showFrameChangeIndicator('Audio: $name');
        _startControlsTimer();
      },
      itemBuilder: (context) {
        if (_audioTracks.isEmpty) {
          return [const PopupMenuItem(value: -1, child: Text('No Audio Tracks'))];
        }
        return _audioTracks.entries.map((e) {
          return PopupMenuItem<int>(
            value: e.key,
            child: Text(e.value),
          );
        }).toList();
      },
    );
  }

  Widget _buildSubtitlesButton() {
    return PopupMenuButton<int>(
      initialValue: _activeSubtitleTrack,
      icon: const Icon(Icons.subtitles, color: Colors.white),
      tooltip: 'Subtitles',
      onSelected: (trackId) async {
        try {
          await _controller?.setSpuTrack(trackId);
        } catch (_) {}
        setState(() {
          _activeSubtitleTrack = trackId;
        });
        final name = trackId == -1 ? 'Off' : (_subtitleTracks[trackId] ?? 'Track $trackId');
        _showFrameChangeIndicator('Subtitles: $name');
        _startControlsTimer();
      },
      itemBuilder: (context) {
        final list = <PopupMenuEntry<int>>[
          const PopupMenuItem<int>(value: -1, child: Text('Disable Subtitles')),
        ];
        if (_subtitleTracks.isNotEmpty) {
          list.addAll(_subtitleTracks.entries.map((e) {
            return PopupMenuItem<int>(
              value: e.key,
              child: Text(e.value),
            );
          }));
        }
        return list;
      },
    );
  }

  Widget _buildSpeedButton() {
    return PopupMenuButton<double>(
      initialValue: _playbackSpeed,
      icon: const Icon(Icons.speed, color: Colors.white),
      tooltip: 'Playback speed',
      onSelected: (speed) {
        setState(() {
          _playbackSpeed = speed;
          try {
            _controller?.setPlaybackSpeed(speed);
          } catch (_) {}
        });
        _startControlsTimer();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 0.5, child: Text('0.5x')),
        const PopupMenuItem(value: 0.75, child: Text('0.75x')),
        const PopupMenuItem(value: 1.0, child: Text('Normal (1.0x)')),
        const PopupMenuItem(value: 1.25, child: Text('1.25x')),
        const PopupMenuItem(value: 1.5, child: Text('1.5x')),
        const PopupMenuItem(value: 2.0, child: Text('2.0x')),
      ],
    );
  }

  void _cycleAspectRatio() {
    if (_isLocked || !_isInitialized) return;
    
    final nextIndex = (_aspectRatio.index + 1) % PlayerAspectRatio.values.length;
    final nextRatio = PlayerAspectRatio.values[nextIndex];
    
    setState(() {
      _aspectRatio = nextRatio;
    });

    String ratioLabel = '';
    switch (nextRatio) {
      case PlayerAspectRatio.original:
        ratioLabel = 'Original';
        break;
      case PlayerAspectRatio.fit:
        ratioLabel = 'Fit (Letterbox)';
        break;
      case PlayerAspectRatio.fill:
        ratioLabel = 'Fill (Crop)';
        break;
      case PlayerAspectRatio.stretch:
        ratioLabel = 'Stretch (Scale)';
        break;
      case PlayerAspectRatio.sixteenNine:
        ratioLabel = '16:9';
        break;
      case PlayerAspectRatio.fourThree:
        ratioLabel = '4:3';
        break;
    }

    _showFrameChangeIndicator(ratioLabel);
    _startControlsTimer();
  }

  void _showFrameChangeIndicator(String label) {
    _frameChangeTimer?.cancel();
    setState(() {
      _frameChangeText = label;
    });
    _frameChangeTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _frameChangeText = null;
        });
      }
    });
  }

  Widget _buildAspectRatioButton() {
    IconData icon;
    switch (_aspectRatio) {
      case PlayerAspectRatio.original:
        icon = Icons.aspect_ratio;
        break;
      case PlayerAspectRatio.fit:
        icon = Icons.fit_screen;
        break;
      case PlayerAspectRatio.fill:
        icon = Icons.fullscreen;
        break;
      case PlayerAspectRatio.stretch:
        icon = Icons.crop_free;
        break;
      case PlayerAspectRatio.sixteenNine:
        icon = Icons.tv;
        break;
      case PlayerAspectRatio.fourThree:
        icon = Icons.picture_in_picture;
        break;
    }

    return IconButton(
      icon: Icon(icon, color: Colors.white),
      tooltip: 'Cycle Aspect Ratio',
      onPressed: _cycleAspectRatio,
    );
  }
}
