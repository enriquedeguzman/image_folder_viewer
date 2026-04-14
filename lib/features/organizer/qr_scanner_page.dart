import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

class OrganizerQrScannerPage extends StatefulWidget {
  final String? saveDirectory;

  const OrganizerQrScannerPage({
    super.key,
    this.saveDirectory,
  });

  @override
  State<OrganizerQrScannerPage> createState() => _OrganizerQrScannerPageState();
}

class _OrganizerQrScannerPageState extends State<OrganizerQrScannerPage> {
  bool _found = false;
  bool _opening = false;

  Future<void> _handleScan(String value) async {
    if (_opening) return;
    _opening = true;

    final raw = value.trim();
    if (raw.isEmpty) {
      _showMessage('QR code is empty.');
      _resetScanner();
      return;
    }

    final fixed = raw.startsWith('http://') || raw.startsWith('https://')
        ? raw
        : 'https://$raw';

    final uri = Uri.tryParse(fixed);

    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      _showMessage('Invalid QR link: $raw');
      _resetScanner();
      return;
    }

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      );

      if (!mounted) return;

      if (!opened) {
        _showMessage('Could not open browser.');
        _resetScanner();
        return;
      }

      if (widget.saveDirectory != null && widget.saveDirectory!.trim().isNotEmpty) {
        try {
          final dir = Directory(widget.saveDirectory!);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }

          final timestamp =
          DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
          final fileName = 'qr_$timestamp.txt';
          final filePath = p.join(dir.path, fileName);

          final file = File(filePath);
          await file.writeAsString(fixed, flush: true);

          _showMessage('Link saved to Other folder.');
        } catch (e) {
          _showMessage('Opened link, but failed to save: $e');
        }
      }

      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      _showMessage('Failed to open link: $e');
      _resetScanner();
    }
  }

  void _resetScanner() {
    if (!mounted) return;
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _found = false;
          _opening = false;
        });
      }
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final savingEnabled =
        widget.saveDirectory != null && widget.saveDirectory!.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          savingEnabled ? 'Scan QR Code (Save Link)' : 'Scan QR Code',
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_found || _opening) return;

              final barcodes = capture.barcodes;
              if (barcodes.isEmpty) return;

              final value = barcodes.first.rawValue;
              if (value == null || value.trim().isEmpty) return;

              setState(() {
                _found = true;
              });

              _handleScan(value);
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _opening
                      ? 'Opening browser...'
                      : savingEnabled
                      ? 'Point camera at QR code • Link will open and save'
                      : 'Point camera at QR code • Link will open',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}