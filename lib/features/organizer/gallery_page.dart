import 'dart:io';

import 'package:flutter/material.dart';

class FullScreenGalleryPage extends StatefulWidget {
  final List<File> files;
  final int initialIndex;

  const FullScreenGalleryPage({
    super.key,
    required this.files,
    required this.initialIndex,
  });

  @override
  State<FullScreenGalleryPage> createState() => _FullScreenGalleryPageState();
}

class _FullScreenGalleryPageState extends State<FullScreenGalleryPage> {
  late final PageController _pageController;
  late int _currentIndex;

  bool _isCover = false; // false = contain, true = cover
  bool _showUi = true;

  @override
  void initState() {
    super.initState();

    final safeIndex = widget.files.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.files.length - 1);

    _currentIndex = safeIndex;
    _pageController = PageController(initialPage: safeIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleFit() {
    setState(() {
      _isCover = !_isCover;
    });
  }

  void _toggleUi() {
    setState(() {
      _showUi = !_showUi;
    });
  }

  void _close() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No images',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0).abs() > 300) {
              _close();
            }
          },
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: widget.files.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final file = widget.files[index];

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleUi,
                    onDoubleTap: _toggleFit,
                    child: Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      child: InteractiveViewer(
                        panEnabled: true,
                        scaleEnabled: true,
                        minScale: 1.0,
                        maxScale: 5.0,
                        child: Center(
                          child: Image.file(
                            file,
                            fit: _isCover ? BoxFit.cover : BoxFit.contain,
                            errorBuilder: (_, __, ___) {
                              return const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white70,
                                  size: 60,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              if (_showUi)
                Positioned(
                  top: 10,
                  left: 10,
                  child: SafeArea(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: IconButton(
                        onPressed: _close,
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),

              if (_showUi)
                Positioned(
                  top: 16,
                  right: 16,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_currentIndex + 1}/${widget.files.length}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),

              if (_showUi)
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _isCover
                              ? 'Double tap: show full image'
                              : 'Double tap: fill screen',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}