import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/gallery_models.dart';

class FullViewPage extends StatefulWidget {
  final List<MyAppImage> images;
  final int initialIndex;
  final Set<String> favoriteIds;
  final ValueChanged<MyAppImage> onToggleFavorite;
  final Future<void> Function(MyAppImage image) onShareImage;
  final Future<File?> Function(MyAppImage image) fileFromImage;

  const FullViewPage({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.favoriteIds,
    required this.onToggleFavorite,
    required this.onShareImage,
    required this.fileFromImage,
  });

  @override
  State<FullViewPage> createState() => _FullViewPageState();
}

class _FullViewPageState extends State<FullViewPage> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showBars = true;
  bool _isLandscape = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _restoreDefaultOrientation();
    super.dispose();
  }

  MyAppImage get _currentImage => widget.images[_currentIndex];

  Future<void> _setPortraitMode() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  Future<void> _setLandscapeMode() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _restoreDefaultOrientation() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _toggleRotate() async {
    if (_isLandscape) {
      await _setPortraitMode();
    } else {
      await _setLandscapeMode();
    }

    if (!mounted) return;
    setState(() {
      _isLandscape = !_isLandscape;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite = widget.favoriteIds.contains(_currentImage.id);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _showBars
          ? AppBar(
        toolbarHeight: 50,
        titleSpacing: 0,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _currentImage.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Rotate Screen',
            onPressed: _toggleRotate,
            icon: Icon(
              _isLandscape
                  ? Icons.stay_current_portrait
                  : Icons.screen_rotation,
            ),
          ),
          IconButton(
            onPressed: () {
              widget.onToggleFavorite(_currentImage);
              setState(() {});
            },
            icon: Icon(isFavorite ? Icons.star : Icons.star_border),
          ),
          IconButton(
            onPressed: () => widget.onShareImage(_currentImage),
            icon: const Icon(Icons.share),
          ),
        ],
      )
          : null,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _showBars = !_showBars;
              });
            },
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final image = widget.images[index];
                return FutureBuilder<File?>(
                  future: widget.fileFromImage(image),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done &&
                        snapshot.data != null) {
                      return Center(
                        child: InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 5,
                          child: Image.file(
                            snapshot.data!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      );
                    }

                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  },
                );
              },
            ),
          ),
          if (_showBars)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black54,
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  'Image ${_currentIndex + 1} of ${widget.images.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}