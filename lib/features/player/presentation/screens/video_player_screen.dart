import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
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
  late VideoPlayerController _controller;
  bool _isInitialized = false;
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
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isInitialized = false;
      _hasError = false;
    });

    try {
      if (widget.url.startsWith('http')) {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.url),
          httpHeaders: widget.headers,
        );
      } else {
        _controller = VideoPlayerController.file(
          File(widget.url),
        );
      }

      await _controller.initialize();
      _volume = _controller.value.volume;
      
      final savedSeconds = await PlaybackTracker.getPosition(_videoKey);
      final duration = _controller.value.duration;

      if (savedSeconds > 5 && savedSeconds < duration.inSeconds * 0.95) {
        await _controller.pause();
        setState(() {
          _isInitialized = true;
        });
        if (mounted) {
          _showResumeDialog(savedSeconds);
        }
      } else {
        await _controller.play();
        setState(() {
          _isInitialized = true;
        });
        _controller.addListener(_onPlayerUpdate);
        _startControlsTimer();
      }
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
              onPressed: () {
                Navigator.of(context).pop();
                _controller.seekTo(Duration.zero);
                _controller.play();
                _controller.addListener(_onPlayerUpdate);
                _startControlsTimer();
              },
              child: const Text('Start Over'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _controller.seekTo(Duration(seconds: savedSeconds));
                _controller.play();
                _controller.addListener(_onPlayerUpdate);
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
    if (!mounted) return;
    
    final value = _controller.value;
    if (value.isInitialized) {
      final currentSecond = value.position.inSeconds;
      if (value.isPlaying && (currentSecond - _lastSavedSecond).abs() >= 3) {
        _lastSavedSecond = currentSecond;
        PlaybackTracker.savePosition(_videoKey, currentSecond);
      }
      
      if (value.position >= value.duration - const Duration(seconds: 5)) {
        PlaybackTracker.clearPosition(_videoKey);
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _controller.removeListener(_onPlayerUpdate);
    
    if (_controller.value.isInitialized) {
      final currentPos = _controller.value.position;
      final totalDur = _controller.value.duration;
      if (currentPos < totalDur - const Duration(seconds: 5)) {
        PlaybackTracker.savePosition(_videoKey, currentPos.inSeconds);
      } else {
        PlaybackTracker.clearPosition(_videoKey);
      }
    }

    _controller.dispose();
    
    // Restore default orientation and System UI
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    if (_showControls && !_isLocked) {
      _controlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _controller.value.isPlaying) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _toggleControls() {
    if (_isLocked) {
      // If locked, show briefly the lock button only
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

  // Visual adjustment overlay for custom brightness
  double get _blackOverlayOpacity => (1.0 - _brightness).clamp(0.0, 0.85);

  void _handleVerticalDragUpdate(DragUpdateDetails details, double screenWidth, double screenHeight) {
    if (_isLocked) return;
    
    final localX = details.localPosition.dx;
    final deltaY = details.primaryDelta ?? 0;

    setState(() {
      _showControls = false; // Hide controls while swiping
      
      if (localX < screenWidth / 2) {
        // Brightness drag (Left screen half)
        _isDraggingBrightness = true;
        _isDraggingVolume = false;
        // Increase/decrease virtual brightness
        _brightness = (_brightness - (deltaY / screenHeight)).clamp(0.1, 1.0);
      } else {
        // Volume drag (Right screen half)
        _isDraggingVolume = true;
        _isDraggingBrightness = false;
        _volume = (_volume - (deltaY / screenHeight)).clamp(0.0, 1.0);
        _controller.setVolume(_volume);
      }
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    setState(() {
      _isDraggingVolume = false;
      _isDraggingBrightness = false;
    });
    _startControlsTimer();
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (_isLocked || !_isInitialized) return;
    setState(() {
      _isDraggingSeek = true;
      _initialSeekPosition = _controller.value.position;
      _dragSeekPosition = _initialSeekPosition;
      _seekChangeSeconds = 0;
      _showControls = false;
    });
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details, double screenWidth) {
    if (_isLocked || !_isInitialized) return;
    
    final deltaX = details.primaryDelta ?? 0;
    // Scale: full screen drag equals 3 minutes (180 seconds)
    final double scaleRatio = 180 / screenWidth;
    final int changeSeconds = (deltaX * scaleRatio).round();

    setState(() {
      _seekChangeSeconds += changeSeconds;
      final totalSeconds = _initialSeekPosition.inSeconds + _seekChangeSeconds;
      final clampedSeconds = totalSeconds.clamp(0, _controller.value.duration.inSeconds);
      _dragSeekPosition = Duration(seconds: clampedSeconds);
    });
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (_isLocked || !_isInitialized) return;
    setState(() {
      _isDraggingSeek = false;
    });
    _controller.seekTo(_dragSeekPosition);
    _startControlsTimer();
  }

  Duration _clampDuration(Duration pos, Duration max) {
    if (pos < Duration.zero) return Duration.zero;
    if (pos > max) return max;
    return pos;
  }

  void _doubleTapLeft() {
    if (_isLocked || !_isInitialized) return;
    final newPos = _controller.value.position - const Duration(seconds: 10);
    _controller.seekTo(_clampDuration(newPos, _controller.value.duration));
    _showFeedbackIndicator('Rewind 10s');
  }

  void _doubleTapRight() {
    if (_isLocked || !_isInitialized) return;
    final newPos = _controller.value.position + const Duration(seconds: 10);
    _controller.seekTo(_clampDuration(newPos, _controller.value.duration));
    _showFeedbackIndicator('Forward 10s');
  }

  void _showFeedbackIndicator(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        duration: const Duration(milliseconds: 600),
        behavior: SnackBarBehavior.floating,
        width: 150,
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildAspectRatioWrapper(Widget child) {
    if (!_isInitialized) return child;
    
    final double videoRatio = _controller.value.aspectRatio;
    
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
          width: _controller.value.size.width,
          height: _controller.value.size.height,
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

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
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
                if (_isInitialized)
                  _buildAspectRatioWrapper(VideoPlayer(_controller))
                else if (_hasError)
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
                            onPressed: _initializePlayer,
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
                              if (_controller.value.isPlaying) {
                                _controller.pause();
                              } else {
                                _controller.play();
                              }
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

          // 5. Player HUD Controls
          if (_showControls) _buildHUD(context),
        ],
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
    final totalDurStr = _formatDuration(_controller.value.duration);
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
                  onPressed: () => Navigator.of(context).pop(),
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
                  if (_isInitialized)
                    Row(
                      children: [
                        Text(
                          _formatDuration(_controller.value.position),
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
                              value: _controller.value.position.inMilliseconds.toDouble(),
                              min: 0.0,
                              max: _controller.value.duration.inMilliseconds.toDouble(),
                              onChanged: (val) {
                                _controller.seekTo(Duration(milliseconds: val.toInt()));
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
                          _formatDuration(_controller.value.duration),
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
                          final newPos = _controller.value.position - const Duration(seconds: 10);
                          _controller.seekTo(_clampDuration(newPos, _controller.value.duration));
                        },
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        icon: Icon(
                          _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                          color: Colors.orange,
                          size: 48,
                        ),
                        onPressed: () {
                          setState(() {
                            if (_controller.value.isPlaying) {
                              _controller.pause();
                            } else {
                              _controller.play();
                            }
                          });
                          _startControlsTimer();
                        },
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        icon: const Icon(Icons.forward_10, color: Colors.white, size: 28),
                        onPressed: () {
                          final newPos = _controller.value.position + const Duration(seconds: 10);
                          _controller.seekTo(_clampDuration(newPos, _controller.value.duration));
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

  Widget _buildSpeedButton() {
    return PopupMenuButton<double>(
      initialValue: _playbackSpeed,
      icon: const Icon(Icons.speed, color: Colors.white),
      tooltip: 'Playback speed',
      onSelected: (speed) {
        setState(() {
          _playbackSpeed = speed;
          _controller.setPlaybackSpeed(speed);
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

    return PopupMenuButton<PlayerAspectRatio>(
      initialValue: _aspectRatio,
      icon: Icon(icon, color: Colors.white),
      tooltip: 'Aspect Ratio',
      onSelected: (ratio) {
        setState(() {
          _aspectRatio = ratio;
        });
        _startControlsTimer();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: PlayerAspectRatio.original, child: Text('Original')),
        const PopupMenuItem(value: PlayerAspectRatio.fit, child: Text('Fit (Letterbox)')),
        const PopupMenuItem(value: PlayerAspectRatio.fill, child: Text('Fill (Crop)')),
        const PopupMenuItem(value: PlayerAspectRatio.stretch, child: Text('Stretch (Scale)')),
        const PopupMenuItem(value: PlayerAspectRatio.sixteenNine, child: Text('16:9')),
        const PopupMenuItem(value: PlayerAspectRatio.fourThree, child: Text('4:3')),
      ],
    );
  }
}
