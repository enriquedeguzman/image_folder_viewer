import 'dart:convert';
import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../order/customer_ledger_page.dart';
import '../order/order_entry_page.dart';
import 'customer_detail_page.dart';
import 'gallery_page.dart';
import 'qr_scanner_page.dart';

class CustomerSectionPage extends StatefulWidget {
  final String customerName;
  final CustomerSectionInfo section;
  final Directory sectionDir;
  final String? sourceRootPath;
  final List<String> priorityFolders;
  final Future<void> Function()? onRequestSetSourceRoot;

  const CustomerSectionPage({
    super.key,
    required this.customerName,
    required this.section,
    required this.sectionDir,
    required this.sourceRootPath,
    required this.priorityFolders,
    this.onRequestSetSourceRoot,
  });

  @override
  State<CustomerSectionPage> createState() => _CustomerSectionPageState();
}

class _CustomerSectionPageState extends State<CustomerSectionPage> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  List<File> _items = [];

  Map<String, double> _invoiceAmounts = {};
  Map<String, String> _invoiceDateIsos = {};
  Map<String, List<_PaymentEntry>> _invoicePayments = {};
  Map<String, double> _invoiceOverpayments = {};
  Map<String, int> _invoiceItemCounts = {};

  bool _loading = true;
  bool _busy = false;
  String _searchQuery = '';

  bool get _isMedicineSection => widget.section.keyName == 'medicine';
  bool get _isInvoiceSection => widget.section.keyName == 'invoices';
  bool get _isVideoSection => widget.section.keyName == 'videos';
  bool get _isScreenshotSection => widget.section.keyName == 'screenshot';
  bool get _allowVideoImport => _isVideoSection;

  Directory get _customerDir => widget.sectionDir.parent;
  Directory get _ordersDir => Directory(p.join(_customerDir.path, 'orders'));
  Directory get _screenshotDir =>
      Directory(p.join(_customerDir.path, 'screenshot'));

  int get _invoiceTotalOrders => _items.length;

  double get _invoiceGrandTotalOrder =>
      _invoiceAmounts.values.fold(0.0, (sum, amount) => sum + amount);

  double get _invoiceGrandTotalPaid => _invoicePayments.values.fold(
    0.0,
        (sum, payments) =>
    sum + payments.fold(0.0, (pSum, p) => pSum + p.amount),
  );

  double get _invoiceGrandTotalBalance {
    final balance = _invoiceGrandTotalOrder - _invoiceGrandTotalPaid;
    return balance > 0 ? balance : 0.0;
  }

  List<File> get _medicineFiles {
    final files = List<File>.from(_items);

    if (!(_isMedicineSection || _isScreenshotSection)) return files;
    if (_searchQuery.trim().isEmpty) return files;

    final q = _searchQuery.trim().toLowerCase();

    return files.where((file) {
      final name = p.basenameWithoutExtension(file.path).toLowerCase();
      return name.contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadItems();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _safeNameForFile(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');

    return cleaned.isEmpty ? 'file' : cleaned;
  }

  String _cleanMedicineBaseName(String originalPath) {
    var name = p.basenameWithoutExtension(originalPath).trim();

    name = name.replaceAll(
      RegExp(r'^(scaled_|IMG_|image_)', caseSensitive: false),
      '',
    );
    name = name.replaceAll(RegExp(r'^\d+[_-]*'), '');
    name = name.replaceAll(RegExp(r'\s+'), ' ');
    name = name.trim();

    if (name.isEmpty) {
      name = 'medicine_image';
    }

    return _safeNameForFile(name);
  }

  String _extractOrderNoFromPdfName(String fileName) {
    final base = p.basenameWithoutExtension(fileName);
    final match =
    RegExp(r'(ORD-\d{8}-\d{6})', caseSensitive: false).firstMatch(base);
    return match?.group(1) ?? '';
  }

  String _peso(double value) => _currencyFormat.format(value);

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();

    final raw = value.toString().trim();
    if (raw.isEmpty) return 0;

    final cleaned = raw.replaceAll(',', '').replaceAll('₱', '');
    return double.tryParse(cleaned) ?? 0;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim()) ?? 0;
  }

  String _todayYmd() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatYmdToMdy(String ymd) {
    final dt = DateTime.tryParse(ymd);
    if (dt == null) return ymd;
    return '${dt.month}/${dt.day}/${dt.year.toString().substring(2)}';
  }

  double _computeFinalTotalFromItems(List<dynamic> itemsRaw) {
    double total = 0;

    for (final item in itemsRaw) {
      if (item is! Map) continue;

      final qty = _toInt(item['qty']);
      final unitPrice = _toDouble(item['unitPrice']);
      final discountPercent = _toDouble(item['discountPercent']);
      final directDiscountPercent = _toDouble(item['directDiscountPercent']);

      final adjustedUnitPrice = directDiscountPercent > 0
          ? unitPrice * (1 - (directDiscountPercent / 100))
          : unitPrice;

      final gross = qty * adjustedUnitPrice;
      final discount =
      discountPercent > 0 ? gross * (discountPercent / 100) : 0.0;

      total += gross - discount;
    }

    return total;
  }

  List<_PaymentEntry> _parsePayments(Map<String, dynamic> map) {
    final rawPayments = map['payments'];
    final payments = <_PaymentEntry>[];

    if (rawPayments is List) {
      for (final row in rawPayments) {
        if (row is! Map) continue;
        final date = (row['date'] ?? '').toString().trim();
        final amount = _toDouble(row['amount']);
        final reference = (row['reference'] ?? '').toString().trim();
        if (date.isEmpty || amount <= 0) continue;
        payments.add(
          _PaymentEntry(
            date: date,
            amount: amount,
            reference: reference,
          ),
        );
      }
    } else {
      final oldAmountPaid = _toDouble(map['amountPaid']);
      final oldCollectedAt = (map['collectedAt'] ?? '').toString().trim();
      if (oldAmountPaid > 0) {
        final date = oldCollectedAt.isNotEmpty
            ? (DateTime.tryParse(oldCollectedAt)
            ?.toIso8601String()
            .split('T')
            .first ??
            _todayYmd())
            : _todayYmd();
        payments.add(_PaymentEntry(date: date, amount: oldAmountPaid));
      }
    }

    payments.sort((a, b) => a.date.compareTo(b.date));
    return payments;
  }

  Future<void> _loadInvoiceOrderData() async {
    final amounts = <String, double>{};
    final dateIsos = <String, String>{};
    final paymentsMap = <String, List<_PaymentEntry>>{};
    final overpayments = <String, double>{};
    final itemCounts = <String, int>{};

    try {
      if (!await _ordersDir.exists()) {
        await _ordersDir.create(recursive: true);
      }

      await for (final entity in _ordersDir.list(followLinks: false)) {
        if (entity is! File) continue;
        if (p.extension(entity.path).toLowerCase() != '.json') continue;

        try {
          final raw = await entity.readAsString();
          final map = jsonDecode(raw);
          if (map is! Map<String, dynamic>) continue;

          final orderNo = (map['orderNo'] ?? '').toString().trim();
          if (orderNo.isEmpty) continue;

          double finalTotal = _toDouble(map['finalTotal']);
          if (finalTotal <= 0) {
            final itemsRaw = map['items'];
            if (itemsRaw is List) {
              finalTotal = _computeFinalTotalFromItems(itemsRaw);
            }
          }

          final dateIso = (map['dateIso'] ?? '').toString().trim();
          final payments = _parsePayments(map);
          final overpayment = _toDouble(map['overpayment']);

          int itemCount = 0;
          final itemsRaw = map['items'];
          if (itemsRaw is List) {
            itemCount = itemsRaw.length;
          }

          amounts[orderNo] = finalTotal;
          dateIsos[orderNo] = dateIso;
          paymentsMap[orderNo] = payments;
          overpayments[orderNo] = overpayment;
          itemCounts[orderNo] = itemCount;
        } catch (_) {}
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _invoiceAmounts = amounts;
      _invoiceDateIsos = dateIsos;
      _invoicePayments = paymentsMap;
      _invoiceOverpayments = overpayments;
      _invoiceItemCounts = itemCounts;
    });
  }

  Future<void> _loadItems() async {
    if (!mounted) return;

    setState(() => _loading = true);

    try {
      if (!await widget.sectionDir.exists()) {
        await widget.sectionDir.create(recursive: true);
      }

      final items = <File>[];

      await for (final entity
      in widget.sectionDir.list(recursive: false, followLinks: false)) {
        if (entity is! File) continue;

        final ext = p.extension(entity.path).toLowerCase();

        if (_isMedicineSection) {
          if (_isImageFile(entity.path)) items.add(entity);
          continue;
        }

        if (_isInvoiceSection) {
          if (ext == '.pdf') items.add(entity);
          continue;
        }

        if (_isScreenshotSection) {
          if (_isImageFile(entity.path)) items.add(entity);
          continue;
        }

        if (_isVideoSection) {
          if (_isVideoFile(entity.path)) items.add(entity);
          continue;
        }

        if (_isAllowedDocumentFile(entity.path)) {
          items.add(entity);
        }
      }

      items.sort((a, b) {
        try {
          final aStat = a.statSync().modified;
          final bStat = b.statSync().modified;
          return bStat.compareTo(aStat);
        } catch (_) {
          return 0;
        }
      });

      if (_isInvoiceSection) {
        await _loadInvoiceOrderData();
      }

      if (!mounted) return;

      setState(() {
        _items = items;
      });
    } catch (e) {
      _showSnack('Failed to load items: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _saveIncomingFileToSection(
      String sourcePath, {
        String? customBaseName,
      }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return;

    if (!await widget.sectionDir.exists()) {
      await widget.sectionDir.create(recursive: true);
    }

    final ext = p.extension(sourcePath).toLowerCase();
    final rawBaseName = customBaseName ?? p.basenameWithoutExtension(sourcePath);
    final baseName = _safeNameForFile(rawBaseName);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final targetName = '${baseName}_$timestamp$ext';
    final targetPath = p.join(widget.sectionDir.path, targetName);

    await sourceFile.copy(targetPath);
  }

  Future<void> _takePictureToSection() async {
    if (_busy) return;

    try {
      setState(() => _busy = true);

      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (picked == null) return;

      await _saveIncomingFileToSection(picked.path);
      await _loadItems();
      _showSnack('Picture saved to ${widget.section.title}.');
    } catch (e) {
      _showSnack('Camera error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importImageToSection() async {
    if (_busy) return;

    try {
      setState(() => _busy = true);

      if (_isMedicineSection || _isScreenshotSection) {
        final pickedFiles = await _imagePicker.pickMultiImage(
          imageQuality: 95,
        );

        if (pickedFiles.isEmpty) return;

        for (final picked in pickedFiles) {
          final cleanedBaseName = _cleanMedicineBaseName(picked.path);
          await _saveIncomingFileToSection(
            picked.path,
            customBaseName: cleanedBaseName,
          );
        }

        await _loadItems();
        _showSnack(
          '${pickedFiles.length} image(s) imported to ${widget.section.title}.',
        );
        return;
      }

      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (picked == null) return;

      await _saveIncomingFileToSection(picked.path);
      await _loadItems();
      _showSnack('Image imported to ${widget.section.title}.');
    } catch (e) {
      _showSnack('Image import error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importPdfToSection() async {
    if (_busy) return;

    try {
      setState(() => _busy = true);

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null || filePath.trim().isEmpty) return;

      await _saveIncomingFileToSection(filePath);
      await _loadItems();
      _showSnack('PDF imported to ${widget.section.title}.');
    } catch (e) {
      _showSnack('PDF import error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importVideoToSection() async {
    if (!_allowVideoImport || _busy) {
      if (!_allowVideoImport) {
        _showSnack('Video import is not enabled for this section.');
      }
      return;
    }

    try {
      setState(() => _busy = true);

      final picked = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );
      if (picked == null) return;

      await _saveIncomingFileToSection(picked.path);
      await _loadItems();
      _showSnack('Video imported to ${widget.section.title}.');
    } catch (e) {
      _showSnack('Video import error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanDocumentToSection() async {
    if (_busy) return;

    try {
      setState(() => _busy = true);

      final scannedPaths = await CunningDocumentScanner.getPictures();
      if (scannedPaths == null || scannedPaths.isEmpty) return;

      for (final path in scannedPaths) {
        await _saveIncomingFileToSection(path);
      }

      await _loadItems();
      _showSnack('${scannedPaths.length} scanned page(s) saved.');
    } catch (e) {
      _showSnack('Scanner error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSectionAddOptions() async {
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isMedicineSection || _isScreenshotSection)
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Import Images'),
                    subtitle: const Text('Select one or multiple images'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _importImageToSection();
                    },
                  )
                else if (_isVideoSection)
                  ListTile(
                    leading: const Icon(Icons.video_library),
                    title: const Text('Import Video'),
                    subtitle: const Text('Video files only'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _importVideoToSection();
                    },
                  )
                else ...[
                    ListTile(
                      leading: const Icon(Icons.camera_alt),
                      title: const Text('Take Picture'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _takePictureToSection();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo),
                      title: const Text('Import Image'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _importImageToSection();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.picture_as_pdf),
                      title: const Text('Import PDF'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _importPdfToSection();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.document_scanner),
                      title: const Text('Scan Document'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _scanDocumentToSection();
                      },
                    ),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openImageViewerFromFiles(
      List<File> files,
      int initialIndex,
      ) async {
    if (!mounted || files.isEmpty) return;

    await Future<void>.delayed(const Duration(milliseconds: 80));

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenGalleryPage(
          files: files,
          initialIndex: initialIndex.clamp(0, files.length - 1),
        ),
      ),
    );
  }

  Future<void> _openDocumentFile(File file) async {
    try {
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        _showSnack('Cannot open file: ${result.message}');
      }
    } catch (e) {
      _showSnack('Failed to open file: $e');
    }
  }

  Future<void> _openTxtLinkInBrowser(File file) async {
    try {
      final raw = await file.readAsString();
      final value = raw.trim();

      if (value.isEmpty) {
        _showSnack('Link file is empty.');
        return;
      }

      final fixed = value.startsWith('http://') || value.startsWith('https://')
          ? value
          : 'https://$value';

      final uri = Uri.tryParse(fixed);

      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
        _showSnack('Invalid saved link.');
        return;
      }

      final opened = await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      );

      if (!opened) {
        _showSnack('Could not open browser.');
      }
    } catch (e) {
      _showSnack('Failed to open link: $e');
    }
  }

  Future<void> _openAnyFile(File file, {List<File>? imageFiles}) async {
    final ext = p.extension(file.path).toLowerCase();
    final isImage = _isImageFile(file.path);
    final isVideo = _isVideoFile(file.path);
    final isPdf = ext == '.pdf';
    final isTxt = ext == '.txt';

    if (isImage) {
      final images = imageFiles ?? [file];
      final imageIndex = images.indexWhere((f) => f.path == file.path);
      await _openImageViewerFromFiles(images, imageIndex < 0 ? 0 : imageIndex);
      return;
    }

    if (isTxt) {
      await _openTxtLinkInBrowser(file);
      return;
    }

    if (isPdf || isVideo || ext == '.json') {
      await _openDocumentFile(file);
      return;
    }

    await _openDocumentFile(file);
  }

  Future<void> _shareFile(File file) async {
    try {
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Shared from Customer Organizer',
      );
    } catch (e) {
      _showSnack('Share failed: $e');
    }
  }

  Future<void> _savePdfToScreenshotFolder(File pdfFile) async {
    try {
      if (!await _screenshotDir.exists()) {
        await _screenshotDir.create(recursive: true);
      }

      final document = await PdfDocument.openFile(pdfFile.path);
      final page = await document.getPage(1);

      final rendered = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );

      await page.close();
      await document.close();

      if (rendered == null || rendered.bytes.isEmpty) {
        _showSnack('Failed to render screenshot image.');
        return;
      }

      final orderNo = _extractOrderNoFromPdfName(p.basename(pdfFile.path));
      final baseName = orderNo.isNotEmpty
          ? orderNo
          : p.basenameWithoutExtension(pdfFile.path);

      final outFile = File(
        p.join(
          _screenshotDir.path,
          '${_safeNameForFile(baseName)}_${DateTime.now().millisecondsSinceEpoch}.png',
        ),
      );

      await outFile.writeAsBytes(rendered.bytes, flush: true);
      _showSnack('Screenshot image saved.');
    } catch (e) {
      _showSnack('Failed to save screenshot image: $e');
    }
  }

  Future<void> _deleteInvoicePairIfNeeded(File file) async {
    await file.delete();

    if (!_isInvoiceSection) return;
    if (p.extension(file.path).toLowerCase() != '.pdf') return;

    final orderNo = _extractOrderNoFromPdfName(p.basename(file.path));
    if (orderNo.isEmpty) return;

    final jsonFile = File(p.join(_ordersDir.path, '$orderNo.json'));
    if (await jsonFile.exists()) {
      await jsonFile.delete();
    }
  }

  Future<void> _deleteFile(File file) async {
    final fileName = p.basename(file.path);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete File'),
          content: Text('Delete "$fileName"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await _deleteInvoicePairIfNeeded(file);
      await _loadItems();
      _showSnack('File deleted.');
    } catch (e) {
      _showSnack('Failed to delete file: $e');
    }
  }

  Future<void> _editSavedSalesOrder(File pdfFile) async {
    try {
      final orderNo = _extractOrderNoFromPdfName(p.basename(pdfFile.path));
      if (orderNo.isEmpty) {
        _showSnack('Order number not found.');
        return;
      }

      if (!await _ordersDir.exists()) {
        await _ordersDir.create(recursive: true);
      }

      final jsonFile = File(p.join(_ordersDir.path, '$orderNo.json'));
      if (!await jsonFile.exists()) {
        _showSnack('Order JSON not found.');
        return;
      }

      final raw = await jsonFile.readAsString();
      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) {
        _showSnack('Invalid order data.');
        return;
      }

      if (!mounted) return;

      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => OrderEntryPage(
            customerName: widget.customerName,
            invoicesDir: widget.sectionDir,
            existingOrderNo: orderNo,
            existingOrderData: Map<String, dynamic>.from(decoded),
            existingJsonFile: jsonFile,
            existingPdfFile: pdfFile,
          ),
        ),
      );

      if (result == true) {
        await _loadItems();
        _showSnack('Sales order updated.');
      }
    } catch (e) {
      _showSnack('Edit failed: $e');
    }
  }

  int _agingDaysForOrder(String orderNo, File file) {
    try {
      final dateIso = (_invoiceDateIsos[orderNo] ?? '').trim();
      final dt = dateIso.isNotEmpty ? DateTime.tryParse(dateIso) : null;
      if (dt != null) {
        final orderDate = DateTime(dt.year, dt.month, dt.day);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final days = today.difference(orderDate).inDays;
        return days < 0 ? 0 : days;
      }
    } catch (_) {}

    try {
      final dt = file.statSync().modified;
      final fileDate = DateTime(dt.year, dt.month, dt.day);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final days = today.difference(fileDate).inDays;
      return days < 0 ? 0 : days;
    } catch (_) {
      return 0;
    }
  }

  String _agingBucket(int days) {
    if (days <= 30) return '0-30';
    if (days <= 60) return '31-60';
    if (days <= 90) return '61-90';
    return '90+';
  }

  Color _agingColor(int days) {
    if (days <= 30) return Colors.green;
    if (days <= 60) return Colors.orange;
    if (days <= 90) return Colors.red;
    return Colors.red.shade900;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PAID':
        return Colors.green;
      case 'PARTIAL':
        return Colors.orange;
      case 'OVERPAID':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Widget _compactChip(
      String text,
      Color color, {
        EdgeInsets? padding,
        double fontSize = 8.0,
        FontWeight fontWeight = FontWeight.w800,
        double radius = 5,
      }) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          height: 1,
        ),
      ),
    );
  }

  List<_PaymentEntry> _orderPayments(String orderNo) {
    return List<_PaymentEntry>.from(_invoicePayments[orderNo] ?? const []);
  }

  double _orderAmountPaid(String orderNo) {
    return _orderPayments(orderNo).fold(0.0, (sum, p) => sum + p.amount);
  }

  double _orderBalance(String orderNo, double finalTotal) {
    return finalTotal - _orderAmountPaid(orderNo);
  }

  double _orderOverpayment(String orderNo, double finalTotal) {
    final stored = _invoiceOverpayments[orderNo] ?? 0.0;
    if (stored > 0) return stored;
    final over = _orderAmountPaid(orderNo) - finalTotal;
    return over > 0 ? over : 0;
  }

  String _orderStatus(String orderNo, double finalTotal) {
    final paid = _orderAmountPaid(orderNo);
    final balance = _orderBalance(orderNo, finalTotal);

    if (finalTotal <= 0) return 'UNPAID';
    if (balance < 0) return 'OVERPAID';
    if (balance == 0) return 'PAID';
    if (paid > 0) return 'PARTIAL';
    return 'UNPAID';
  }

  String _latestPaymentText(String orderNo) {
    final payments = _orderPayments(orderNo);
    if (payments.isEmpty) return '';
    final last = payments.last;
    final ref = last.reference.trim();

    if (ref.isNotEmpty) {
      return '${_formatYmdToMdy(last.date)} ${_peso(last.amount)} • $ref';
    }

    return '${_formatYmdToMdy(last.date)} ${_peso(last.amount)}';
  }

  Future<void> _showPaymentHistory(String orderNo) async {
    final payments = _orderPayments(orderNo);

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Payment History'),
        content: SizedBox(
          width: 320,
          child: payments.isEmpty
              ? const Text('No collection entries yet.')
              : ListView.separated(
            shrinkWrap: true,
            itemCount: payments.length,
            separatorBuilder: (_, __) => const Divider(height: 14),
            itemBuilder: (context, index) {
              final item = payments[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatYmdToMdy(item.date),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        _peso(item.amount),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2F6FD6),
                        ),
                      ),
                    ],
                  ),
                  if (item.reference.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Ref: ${item.reference}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _collectPaymentForOrder(String orderNo, double finalTotal) async {
    final dateController = TextEditingController(text: _todayYmd());
    final amountController = TextEditingController();
    final referenceController = TextEditingController();

    final result = await showDialog<_PaymentEntry>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Collect Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dateController,
                decoration: const InputDecoration(
                  labelText: 'Date',
                  hintText: 'YYYY-MM-DD',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountController,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Amount Collected',
                  hintText: 'Enter amount',
                  helperText: 'Total Order: ${_peso(finalTotal)}',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: referenceController,
                decoration: const InputDecoration(
                  labelText: 'Reference',
                  hintText: 'OR / GCash / Check',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final date = dateController.text.trim();
                final amount = _toDouble(amountController.text);
                final reference = referenceController.text.trim();

                if (DateTime.tryParse(date) == null) {
                  return;
                }

                Navigator.pop(
                  dialogContext,
                  _PaymentEntry(
                    date: date,
                    amount: amount,
                    reference: reference,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == null) return;
    if (result.amount <= 0) {
      _showSnack('Enter valid amount.');
      return;
    }
    if (DateTime.tryParse(result.date) == null) {
      _showSnack('Enter valid date.');
      return;
    }

    try {
      final jsonFile = File(p.join(_ordersDir.path, '$orderNo.json'));
      if (!await jsonFile.exists()) {
        _showSnack('Order file not found.');
        return;
      }

      final raw = await jsonFile.readAsString();
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) {
        _showSnack('Invalid order file.');
        return;
      }

      double orderTotal = _toDouble(map['finalTotal']);
      if (orderTotal <= 0) {
        final itemsRaw = map['items'];
        if (itemsRaw is List) {
          orderTotal = _computeFinalTotalFromItems(itemsRaw);
        }
      }

      final payments = _parsePayments(map);
      payments.add(result);
      payments.sort((a, b) => a.date.compareTo(b.date));

      final totalPaid = payments.fold(0.0, (sum, p) => sum + p.amount);
      final balance = orderTotal - totalPaid;
      final overpayment =
      totalPaid > orderTotal ? (totalPaid - orderTotal) : 0.0;

      String status;
      if (balance < 0) {
        status = 'OVERPAID';
      } else if (balance == 0) {
        status = 'PAID';
      } else if (totalPaid > 0) {
        status = 'PARTIAL';
      } else {
        status = 'UNPAID';
      }

      map['payments'] = payments
          .map((e) => {
        'date': e.date,
        'amount': e.amount,
        'reference': e.reference,
      })
          .toList();
      map['amountPaid'] = totalPaid;
      map['balance'] = balance > 0 ? balance : 0.0;
      map['overpayment'] = overpayment;
      map['status'] = status;
      map['collectedAt'] = DateTime.now().toIso8601String();

      await jsonFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(map),
      );

      await _loadItems();
      _showSnack('Collection updated.');
    } catch (e) {
      _showSnack('Failed to save collection: $e');
    }
  }

  Widget _buildCompactHeader(int totalCount) {
    final totalOrders = _isInvoiceSection ? _invoiceTotalOrders : totalCount;
    final totalOrder = _isInvoiceSection ? _invoiceGrandTotalOrder : 0.0;
    final totalPaid = _isInvoiceSection ? _invoiceGrandTotalPaid : 0.0;
    final totalBalance = _isInvoiceSection ? _invoiceGrandTotalBalance : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD8E6FA)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.customerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.section.title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_isInvoiceSection) ...[
                    const SizedBox(height: 6),
                    Text(
                      '$totalOrders Order${totalOrders == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total Order: ${_peso(totalOrder)}',
                      style: const TextStyle(
                        fontSize: 10.7,
                        color: Color(0xFF334155),
                        height: 1.1,
                      ),
                    ),
                    Text(
                      'Total Paid: ${_peso(totalPaid)}',
                      style: const TextStyle(
                        fontSize: 10.7,
                        color: Color(0xFF334155),
                        height: 1.1,
                      ),
                    ),
                    Text(
                      'Total Balance: ${_peso(totalBalance)}',
                      style: const TextStyle(
                        fontSize: 10.7,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2F6FD6),
                        height: 1.1,
                      ),
                    ),
                  ] else
                    Text(
                      '$totalCount item${totalCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (_isInvoiceSection)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderEntryPage(
                        customerName: widget.customerName,
                        invoicesDir: widget.sectionDir,
                      ),
                    ),
                  );

                  if (result == true) {
                    await _loadItems();
                  }
                },
                style: FilledButton.styleFrom(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.receipt_long, size: 16),
                label: const Text('New'),
              )
            else
              FilledButton.icon(
                onPressed: _busy ? null : _showSectionAddOptions,
                style: FilledButton.styleFrom(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceList() {
    final files = List<File>.from(_items);

    if (files.isEmpty) {
      return const _EmptySectionView(message: 'No sales orders yet');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final name = p.basename(file.path);
        final orderNo = _extractOrderNoFromPdfName(name);

        final finalTotal = _invoiceAmounts[orderNo] ?? 0;
        final amountPaid = _orderAmountPaid(orderNo);
        final rawBalance = _orderBalance(orderNo, finalTotal);
        final balance = rawBalance > 0 ? rawBalance : 0.0;
        final overpayment = _orderOverpayment(orderNo, finalTotal);
        final status = _orderStatus(orderNo, finalTotal);
        final itemCount = _invoiceItemCounts[orderNo] ?? 0;

        final agingDays = _agingDaysForOrder(orderNo, file);
        final agingBucket = _agingBucket(agingDays);
        final agingColor = _agingColor(agingDays);
        final statusColor = _statusColor(status);
        final latestPaidText = _latestPaymentText(orderNo);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD7DFEA)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _openDocumentFile(file),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf,
                    size: 17,
                    color: Colors.red,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _openDocumentFile(file),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                          style: const TextStyle(
                            fontSize: 11.3,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Saved PDF',
                                style: TextStyle(
                                  fontSize: 9.8,
                                  color: Color(0xFF64748B),
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: orderNo.isEmpty || finalTotal <= 0
                                    ? null
                                    : () => _collectPaymentForOrder(
                                  orderNo,
                                  finalTotal,
                                ),
                                onLongPress: orderNo.isEmpty
                                    ? null
                                    : () => _showPaymentHistory(orderNo),
                                child: Padding(
                                  padding:
                                  const EdgeInsets.symmetric(vertical: 1),
                                  child: Wrap(
                                    spacing: 2,
                                    runSpacing: 2,
                                    children: [
                                      if (status != 'PAID' &&
                                          status != 'OVERPAID') ...[
                                        _compactChip('${agingDays}D', Colors.blue),
                                        _compactChip(agingBucket, agingColor),
                                      ],
                                      _compactChip(status, statusColor),
                                    ],
                                  ),
                                ),
                              ),
                              if (latestPaidText.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    latestPaidText,
                                    style: const TextStyle(
                                      fontSize: 8.8,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                      height: 1.0,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _compactChip(
                              '$itemCount item${itemCount == 1 ? '' : 's'}',
                              const Color(0xFF64748B),
                              fontSize: 7.8,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Order ${_peso(finalTotal)}',
                              style: const TextStyle(
                                fontSize: 9.6,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                                height: 1.0,
                              ),
                              textAlign: TextAlign.right,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Paid ${_peso(amountPaid)}',
                              style: const TextStyle(
                                fontSize: 8.9,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                                height: 1.0,
                              ),
                              textAlign: TextAlign.right,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Bal ${_peso(balance)}',
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF2F6FD6),
                                height: 1.0,
                              ),
                              textAlign: TextAlign.right,
                            ),
                            if (status == 'OVERPAID')
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Text(
                                  'Over ${_peso(overpayment)}',
                                  style: const TextStyle(
                                    fontSize: 8.8,
                                    color: Colors.purple,
                                    fontWeight: FontWeight.w700,
                                    height: 1.0,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Wrap(
                spacing: 0,
                runSpacing: 0,
                alignment: WrapAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Payment Entry',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: orderNo.isEmpty || finalTotal <= 0
                        ? null
                        : () => _collectPaymentForOrder(orderNo, finalTotal),
                    icon: const Icon(Icons.payments_outlined),
                  ),
                  IconButton(
                    tooltip: 'Payment History',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed:
                    orderNo.isEmpty ? null : () => _showPaymentHistory(orderNo),
                    icon: const Icon(Icons.history),
                  ),
                  IconButton(
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: orderNo.isEmpty
                        ? null
                        : () => _editSavedSalesOrder(file),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    constraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                    onSelected: (value) async {
                      switch (value) {
                        case 'open':
                          await _openDocumentFile(file);
                          break;
                        case 'share':
                          await _shareFile(file);
                          break;
                        case 'screenshot':
                          await _savePdfToScreenshotFolder(file);
                          break;
                        case 'delete':
                          await _deleteFile(file);
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'open',
                        child: Row(
                          children: [
                            Icon(Icons.open_in_new, size: 18),
                            SizedBox(width: 8),
                            Text('Open PDF'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'share',
                        child: Row(
                          children: [
                            Icon(Icons.share, size: 18),
                            SizedBox(width: 8),
                            Text('Share'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'screenshot',
                        child: Row(
                          children: [
                            Icon(Icons.photo_camera_back_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Save Screenshot'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18),
                            SizedBox(width: 8),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDocumentList() {
    final files = List<File>.from(_items);

    if (files.isEmpty) {
      return _EmptySectionView(
        message: 'No ${widget.section.title.toLowerCase()} yet',
      );
    }

    final imageFiles = files.where((f) => _isImageFile(f.path)).toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final name = p.basename(file.path);
        final ext = p.extension(file.path).toLowerCase();
        final isPdf = ext == '.pdf';
        final isImage = _isImageFile(file.path);
        final isVideo = _isVideoFile(file.path);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ListTile(
            onTap: () => _openAnyFile(file, imageFiles: imageFiles),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            leading: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: isPdf
                    ? const Color(0xFFFFEBEE)
                    : isVideo
                    ? const Color(0xFFE8F0FE)
                    : const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isPdf
                    ? Icons.picture_as_pdf_outlined
                    : isVideo
                    ? Icons.movie_creation_outlined
                    : Icons.image_outlined,
              ),
            ),
            title: Text(name, maxLines: 4, softWrap: true),
            subtitle: Text(
              isPdf
                  ? 'PDF • Tap to open'
                  : isVideo
                  ? 'VIDEO • Tap to open'
                  : isImage
                  ? 'IMAGE • Tap to view'
                  : 'FILE • Tap to open',
            ),
            trailing: Wrap(
              spacing: 0,
              children: [
                IconButton(
                  onPressed: () => _openAnyFile(file, imageFiles: imageFiles),
                  icon: const Icon(Icons.open_in_new),
                ),
                IconButton(
                  onPressed: () => _shareFile(file),
                  icon: const Icon(Icons.share_outlined),
                ),
                IconButton(
                  onPressed: () => _deleteFile(file),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMedicineSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          if (!mounted) return;
          setState(() {
            _searchQuery = value;
          });
        },
        decoration: InputDecoration(
          hintText: _isScreenshotSection
              ? 'Search screenshot image...'
              : 'Search medicine image...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.trim().isEmpty
              ? null
              : IconButton(
            onPressed: () {
              _searchController.clear();
              if (!mounted) return;
              setState(() {
                _searchQuery = '';
              });
            },
            icon: const Icon(Icons.close),
          ),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD8E6FA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD8E6FA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF7AA7E8)),
          ),
        ),
      ),
    );
  }

  Widget _buildMedicineImageList() {
    final files = _medicineFiles;

    if (files.isEmpty) {
      return _EmptySectionView(
        message: _searchQuery.trim().isEmpty
            ? (_isScreenshotSection
            ? 'No screenshot images yet'
            : 'No medicine images yet')
            : (_isScreenshotSection
            ? 'No screenshot matched your search'
            : 'No medicine matched your search'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                InkWell(
                  onTap: () async => _openImageViewerFromFiles(files, index),
                  child: Container(
                    width: double.infinity,
                    color: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Image.file(
                      file,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) {
                        return Container(
                          height: 240,
                          color: Colors.grey.shade100,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image, size: 40),
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(14),
                    child: PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        color: Colors.white,
                        size: 20,
                      ),
                      onSelected: (value) async {
                        if (value == 'open') {
                          await _openImageViewerFromFiles(files, index);
                        } else if (value == 'share') {
                          await _shareFile(file);
                        } else if (value == 'delete') {
                          await _deleteFile(file);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem<String>(
                          value: 'open',
                          child: Text('Open'),
                        ),
                        PopupMenuItem<String>(
                          value: 'share',
                          child: Text('Share'),
                        ),
                        PopupMenuItem<String>(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openLedgerPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerLedgerPage(
          customerName: widget.customerName,
          customerDir: _customerDir,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = _items.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.customerName} • ${widget.section.title}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_isInvoiceSection)
            IconButton(
              tooltip: 'Ledger',
              onPressed: _busy ? null : _openLedgerPage,
              icon: const Icon(Icons.menu_book_outlined),
            ),
          IconButton(
            tooltip: 'Scan QR',
            onPressed: _busy
                ? null
                : () async {
              final otherDir = Directory(
                p.join(_customerDir.path, 'other'),
              );

              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OrganizerQrScannerPage(
                    saveDirectory: otherDir.path,
                  ),
                ),
              );

              if (widget.section.keyName == 'other') {
                await _loadItems();
              }
            },
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _loadItems,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Container(
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
          child: Column(
            children: [
              _buildCompactHeader(totalCount),
              if (_isMedicineSection || _isScreenshotSection)
                _buildMedicineSearchBar(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _isInvoiceSection
                    ? _buildInvoiceList()
                    : (_isMedicineSection || _isScreenshotSection)
                    ? _buildMedicineImageList()
                    : _buildDocumentList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentEntry {
  final String date;
  final double amount;
  final String reference;

  const _PaymentEntry({
    required this.date,
    required this.amount,
    this.reference = '',
  });
}

class _EmptySectionView extends StatelessWidget {
  final String message;

  const _EmptySectionView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.folder_open_outlined,
              size: 62,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

bool _isImageFile(String path) {
  final ext = p.extension(path).toLowerCase();
  return [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
    '.heic',
    '.heif',
    '.jfif',
  ].contains(ext);
}

bool _isVideoFile(String path) {
  final ext = p.extension(path).toLowerCase();
  return ['.mp4', '.mov', '.mkv', '.avi', '.3gp', '.webm', '.m4v']
      .contains(ext);
}

bool _isAllowedDocumentFile(String path) {
  final ext = p.extension(path).toLowerCase();
  return [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
    '.heic',
    '.heif',
    '.jfif',
    '.pdf',
    '.json',
    '.txt',
    '.mp4',
    '.mov',
    '.mkv',
    '.avi',
    '.3gp',
    '.webm',
    '.m4v',
  ].contains(ext);
}