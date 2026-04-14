import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerPage extends StatefulWidget {
  final File file;
  final String title;

  const VideoPlayerPage({
    super.key,
    required this.file,
    required this.title,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _showOverlay = true;
  String? _errorText;
  Timer? _overlayTimer;
  bool _isLandscape = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.file(
        widget.file,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      _controller = controller;

      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(1.0);

      controller.addListener(_videoListener);

      if (!mounted) return;

      setState(() {
        _loading = false;
        _errorText = null;
      });

      _startOverlayTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = 'Unable to play this video.\n$e';
      });
    }
  }

  void _videoListener() {
    if (!mounted) return;

    final controller = _controller;
    if (controller == null) return;

    if (controller.value.hasError) {
      setState(() {
        _errorText = controller.value.errorDescription ?? 'Video playback error';
      });
      return;
    }

    setState(() {});
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _controller?.removeListener(_videoListener);
    _controller?.dispose();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    super.dispose();
  }

  void _startOverlayTimer() {
    _overlayTimer?.cancel();

    final controller = _controller;
    if (controller == null) return;
    if (!controller.value.isPlaying) return;

    _overlayTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _showOverlay = false;
      });
    });
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;

    try {
      if (controller.value.isPlaying) {
        await controller.pause();
        if (!mounted) return;
        setState(() {
          _showOverlay = true;
        });
      } else {
        await controller.play();
        if (!mounted) return;
        setState(() {
          _showOverlay = true;
        });
        _startOverlayTimer();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Playback failed.\n$e';
        _showOverlay = true;
      });
    }
  }

  Future<void> _seekToRelative(int seconds) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final current = controller.value.position;
    final duration = controller.value.duration;

    var target = current + Duration(seconds: seconds);

    if (target < Duration.zero) target = Duration.zero;
    if (target > duration) target = duration;

    await controller.seekTo(target);

    if (!mounted) return;
    setState(() {
      _showOverlay = true;
    });
    _startOverlayTimer();
  }

  Future<void> _toggleOrientation() async {
    _isLandscape = !_isLandscape;

    if (_isLandscape) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }

    if (!mounted) return;
    setState(() {
      _showOverlay = true;
    });
    _startOverlayTimer();
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildVideoArea(VideoPlayerController controller) {
    final size = controller.value.size;
    final width = size.width <= 0 ? 1.0 : size.width;
    final height = size.height <= 0 ? 1.0 : size.height;

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: width,
          height: height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready =
        !_loading && controller != null && controller.value.isInitialized;

    final position = ready ? controller.value.position : Duration.zero;
    final duration = ready ? controller.value.duration : Duration.zero;
    final maxMs = duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds;
    final progress = (position.inMilliseconds / maxMs).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isLandscape
          ? null
          : AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        toolbarHeight: 50,
        titleSpacing: 0,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading
          ? const Center(
        child: CircularProgressIndicator(),
      )
          : _errorText != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 56,
              ),
              const SizedBox(height: 16),
              Text(
                _errorText!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      )
          : GestureDetector(
        onTap: () {
          setState(() {
            _showOverlay = !_showOverlay;
          });
          if (_showOverlay) {
            _startOverlayTimer();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoArea(controller!),
            if (_showOverlay) Container(color: Colors.black26),
            if (_showOverlay)
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => _seekToRelative(-10),
                      iconSize: 44,
                      color: Colors.white,
                      icon: const Icon(Icons.replay_10),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: _togglePlay,
                      iconSize: 78,
                      color: Colors.white,
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () => _seekToRelative(10),
                      iconSize: 44,
                      color: Colors.white,
                      icon: const Icon(Icons.forward_10),
                    ),
                  ],
                ),
              ),
            if (_showOverlay)
              Positioned(
                left: 12,
                right: 12,
                bottom: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape:
                          const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                        ),
                        child: Slider(
                          value: progress,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (value) async {
                            if (!controller.value.isInitialized) {
                              return;
                            }

                            final target = Duration(
                              milliseconds:
                              (duration.inMilliseconds * value)
                                  .round(),
                            );

                            await controller.seekTo(target);

                            if (!mounted) return;
                            setState(() {
                              _showOverlay = true;
                            });
                            _startOverlayTimer();
                          },
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            _formatDuration(position),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _toggleOrientation,
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              _isLandscape
                                  ? Icons.stay_current_portrait
                                  : Icons.stay_current_landscape,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatDuration(duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (_showOverlay && _isLandscape)
              Positioned(
                top: 18,
                left: 10,
                child: SafeArea(
                  child: IconButton(
                    onPressed: () async {
                      if (_isLandscape) {
                        await _toggleOrientation();
                      }
                      if (mounted) {
                        Navigator.pop(context);
                      }
                    },
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}