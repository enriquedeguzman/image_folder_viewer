import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class SlideShowPage extends StatefulWidget {
  final List<File> files;
  final int startIndex;

  const SlideShowPage({
    super.key,
    required this.files,
    required this.startIndex,
  });

  @override
  State<SlideShowPage> createState() => _SlideShowPageState();
}

class _SlideShowPageState extends State<SlideShowPage> {
  late final PageController _pageController;
  late int _currentIndex;

  Timer? _timer;
  bool _autoPlay = true;
  bool _showUi = true;

  static const Duration _slideDuration = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex.clamp(0, widget.files.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();

    if (!_autoPlay || widget.files.length <= 1) return;

    _timer = Timer.periodic(_slideDuration, (_) {
      if (!mounted) return;

      final next = (_currentIndex + 1) % widget.files.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  void _toggleAutoPlay() {
    setState(() {
      _autoPlay = !_autoPlay;
    });
    _startTimer();
  }

  void _toggleUi() {
    setState(() {
      _showUi = !_showUi;
    });
  }

  void _goPrevious() {
    if (widget.files.isEmpty) return;
    final prev = (_currentIndex - 1 + widget.files.length) % widget.files.length;
    _pageController.animateToPage(
      prev,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _goNext() {
    if (widget.files.isEmpty) return;
    final next = (_currentIndex + 1) % widget.files.length;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    final currentFile = files[_currentIndex];
    final fileName = p.basename(currentFile.path);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleUi,
            child: PageView.builder(
              controller: _pageController,
              itemCount: files.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
                _startTimer();
              },
              itemBuilder: (context, index) {
                final file = files[index];
                return Center(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 5,
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) {
                        return const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 60,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),

          if (_showUi)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Slideshow',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${_currentIndex + 1} / ${files.length} • $fileName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _autoPlay ? 'Pause' : 'Play',
                    onPressed: _toggleAutoPlay,
                    icon: Icon(
                      _autoPlay ? Icons.pause_circle_outline : Icons.play_circle_outline,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

          if (_showUi)
            Positioned(
              left: 12,
              right: 12,
              bottom: MediaQuery.of(context).padding.bottom + 12,
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _goPrevious,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Prev'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _toggleAutoPlay,
                      icon: Icon(_autoPlay ? Icons.pause : Icons.play_arrow),
                      label: Text(_autoPlay ? 'Pause' : 'Play'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _goNext,
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Next'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}