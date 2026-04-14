import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../services/pricelist_manager.dart';

class PricelistUploadPage extends StatefulWidget {
  const PricelistUploadPage({super.key});

  @override
  State<PricelistUploadPage> createState() => _PricelistUploadPageState();
}

class _PricelistUploadPageState extends State<PricelistUploadPage> {
  bool _loading = true;
  bool _uploadingPdf = false;
  bool _importingCsv = false;

  bool _hasPdf = false;
  bool _hasCsv = false;
  bool _hasJson = false;

  String _pdfPath = '';
  String _csvPath = '';

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final pdfFile = await PricelistManager.getPricelistPdfFile();
      final csvFile = await PricelistManager.getPricelistCsvFile();
      final hasJson = await PricelistManager.hasPricelistJson();

      if (!mounted) return;

      setState(() {
        _hasPdf = pdfFile.existsSync();
        _hasCsv = csvFile.existsSync();
        _hasJson = hasJson;
        _pdfPath = pdfFile.path;
        _csvPath = csvFile.path;
      });
    } catch (e) {
      _showSnack('Failed to load pricelist status: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _uploadPdf() async {
    if (mounted) {
      setState(() => _uploadingPdf = true);
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        dialogTitle: 'Select Pricelist PDF',
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final path = result.files.single.path;
      if (path == null || path.trim().isEmpty) {
        _showSnack('No PDF file selected.');
        return;
      }

      await PricelistManager.savePricelistPdfFromPath(path);
      await _loadStatus();

      _showSnack('Pricelist PDF uploaded successfully.');
    } catch (e) {
      _showSnack('Failed to upload pricelist PDF: $e');
    } finally {
      if (mounted) {
        setState(() => _uploadingPdf = false);
      }
    }
  }

  Future<void> _importCsv() async {
    if (mounted) {
      setState(() => _importingCsv = true);
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        dialogTitle: 'Select Pricelist CSV',
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final path = result.files.single.path;
      if (path == null || path.trim().isEmpty) {
        _showSnack('No CSV file selected.');
        return;
      }

      final items = await PricelistManager.importPricelistFromCsvPath(path);

      await _loadStatus();
      _showSnack(
        'CSV imported successfully. ${items.length} items saved to master pricelist.',
      );
    } catch (e) {
      _showSnack('Failed to import CSV: $e');
    } finally {
      if (mounted) {
        setState(() => _importingCsv = false);
      }
    }
  }

  Future<void> _reimportSavedCsv() async {
    if (mounted) {
      setState(() => _importingCsv = true);
    }

    try {
      final items = await PricelistManager.importPricelistFromSavedCsv();

      await _loadStatus();
      _showSnack(
        'Saved CSV re-imported. ${items.length} items saved to master pricelist.',
      );
    } catch (e) {
      _showSnack('Failed to re-import saved CSV: $e');
    } finally {
      if (mounted) {
        setState(() => _importingCsv = false);
      }
    }
  }

  Future<void> _openSavedPdf() async {
    try {
      final file = await PricelistManager.getPricelistPdfFile();
      if (!await file.exists()) {
        _showSnack('No saved pricelist PDF found.');
        return;
      }

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        _showSnack('Cannot open PDF: ${result.message}');
      }
    } catch (e) {
      _showSnack('Failed to open pricelist PDF: $e');
    }
  }

  Future<void> _openSavedCsv() async {
    try {
      final file = await PricelistManager.getPricelistCsvFile();
      if (!await file.exists()) {
        _showSnack('No saved pricelist CSV found.');
        return;
      }

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        _showSnack('Cannot open CSV: ${result.message}');
      }
    } catch (e) {
      _showSnack('Failed to open pricelist CSV: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEAF3FF),
            Color(0xFFF4F8FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD8E6FA)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9AB6E6).withOpacity(0.14),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pricelist Files Status',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusChip('PDF', _hasPdf),
              _statusChip('CSV', _hasCsv),
              _statusChip('JSON Records', _hasJson),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'PDF Path:',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            _pdfPath,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'CSV Path:',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            _csvPath,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label: ${ok ? "Ready" : "Missing"}',
        style: TextStyle(
          color: ok ? Colors.green.shade700 : Colors.red.shade700,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD7DFEA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Actions',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _uploadingPdf ? null : _uploadPdf,
                icon: _uploadingPdf
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  _uploadingPdf ? 'Uploading PDF...' : 'Upload Pricelist PDF',
                ),
              ),
              FilledButton.icon(
                onPressed: _importingCsv ? null : _importCsv,
                icon: _importingCsv
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.table_chart_outlined),
                label: Text(
                  _importingCsv ? 'Importing CSV...' : 'Import Pricelist CSV',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _hasCsv && !_importingCsv ? _reimportSavedCsv : null,
                icon: const Icon(Icons.sync),
                label: const Text('Re-import Saved CSV'),
              ),
              OutlinedButton.icon(
                onPressed: _hasPdf ? _openSavedPdf : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Saved PDF'),
              ),
              OutlinedButton.icon(
                onPressed: _hasCsv ? _openSavedCsv : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Saved CSV'),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : _loadStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD7DFEA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recommended Flow',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 10),
          Text(
            '1. Upload PDF only if you want to keep the original reference file.\n'
                '2. Import CSV to create or replace master pricelist records.\n'
                '3. Customer medicine JSON files are no longer force-updated on every CSV import.\n'
                '4. Medicine images should be matched dynamically from master_data/medicine_images.\n'
                '5. Best image naming: brand_formulation_packing.jpg or brand.jpg.\n'
                '6. If your CSV changes, use Import CSV again or Re-import Saved CSV.',
            style: TextStyle(
              color: Color(0xFF475569),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageRuleCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD7DFEA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Image Naming Guide',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 10),
          SelectableText(
            'Examples:\n'
                'biogesic_500mg_tablet_box_of_100.jpg\n'
                'biogesic.jpg\n'
                'amoxicillin_500mg_capsule.jpg',
            style: TextStyle(
              color: Color(0xFF475569),
              height: 1.45,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Use lowercase names with underscores for more reliable auto-matching.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _uploadingPdf || _importingCsv || _loading;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pricelist Upload / Import',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: busy ? null : _loadStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFF7FAFF),
              Color(0xFFF2F7FF),
              Color(0xFFF9FBFF),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            _buildStatusCard(),
            const SizedBox(height: 12),
            _buildActionsCard(),
            const SizedBox(height: 12),
            _buildInfoCard(),
            const SizedBox(height: 12),
            _buildImageRuleCard(),
          ],
        ),
      ),
    );
  }
}