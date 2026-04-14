import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/order_models.dart';
import '../../../../services/invoice_pdf.dart';
import '../../../../services/pricelist_manager.dart';

class OrderEntryPage extends StatefulWidget {
  final String customerName;
  final Directory invoicesDir;

  final String? existingOrderNo;
  final Map<String, dynamic>? existingOrderData;
  final File? existingJsonFile;
  final File? existingPdfFile;

  const OrderEntryPage({
    super.key,
    required this.customerName,
    required this.invoicesDir,
    this.existingOrderNo,
    this.existingOrderData,
    this.existingJsonFile,
    this.existingPdfFile,
  });

  bool get isEditMode => existingOrderData != null;

  @override
  State<OrderEntryPage> createState() => _OrderEntryPageState();
}

class _OrderEntryPageState extends State<OrderEntryPage> {
  final _medrepController = TextEditingController();
  final _areaController = TextEditingController();
  final _collectionController = TextEditingController();
  final _headerNoteController = TextEditingController();

  final _promoController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  final _directDiscountController = TextEditingController(text: '0');

  final List<_DraftOrderItem> _draftItems = [];
  List<PricelistItem> _pricelist = [];

  bool _loading = true;
  bool _saving = false;

  Directory get _customerDir => widget.invoicesDir.parent;
  Directory get _ordersDir => Directory(p.join(_customerDir.path, 'orders'));

  @override
  void initState() {
    super.initState();
    _loadPricelist();
    _loadLastInputs();
    _loadExistingOrderIfAny();
  }

  @override
  void dispose() {
    _medrepController.dispose();
    _areaController.dispose();
    _collectionController.dispose();
    _headerNoteController.dispose();
    _promoController.dispose();
    _discountController.dispose();
    _directDiscountController.dispose();

    for (final item in _draftItems) {
      item.dispose();
    }
    super.dispose();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    final raw = value.toString().trim().replaceAll(',', '').replaceAll('₱', '');
    return double.tryParse(raw) ?? 0;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim()) ?? 0;
  }

  String _toText(dynamic value) => (value ?? '').toString();

  String _formatPercentForField(double value) {
    if (value <= 0) return '0';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  Future<void> _loadLastInputs() async {
    if (widget.isEditMode) return;

    final prefs = await SharedPreferences.getInstance();
    _medrepController.text = prefs.getString('last_medrep') ?? '';
    _areaController.text = prefs.getString('last_area') ?? '';

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveLastInputs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_medrep', _medrepController.text.trim());
    await prefs.setString('last_area', _areaController.text.trim());
  }

  void _loadExistingOrderIfAny() {
    final map = widget.existingOrderData;
    if (map == null) return;

    _medrepController.text = _toText(map['medrep']);
    _areaController.text = _toText(map['area']);
    _collectionController.text = _toText(map['collection']);
    _headerNoteController.text = _toText(map['headerNote']);

    _promoController.text = _toText(map['freeGoods']).isNotEmpty
        ? _toText(map['freeGoods'])
        : _toText(map['promo']);

    _discountController.text = _formatPercentForField(
      _toDouble(map['discountPercent'] ?? map['discount']),
    );
    _directDiscountController.text = _formatPercentForField(
      _toDouble(map['directDiscountPercent'] ?? map['directDiscount']),
    );

    final itemsRaw = map['items'];
    if (itemsRaw is List) {
      _draftItems.clear();

      for (final row in itemsRaw) {
        if (row is! Map) continue;

        final qty = _toInt(row['qty']);
        _draftItems.add(
          _DraftOrderItem(
            category: _toText(row['category']),
            brand: _toText(row['brand']),
            generic: _toText(row['generic']),
            formulation: _toText(row['formulation']),
            packing: _toText(row['packing']),
            uom: _toText(row['uom']),
            unitPrice: _toDouble(row['unitPrice']),
            qtyController: TextEditingController(text: qty.toString()),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadPricelist() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final items = await PricelistManager.loadPricelistItems();

      items.sort((a, b) {
        final brandCompare =
        a.brand.toLowerCase().compareTo(b.brand.toLowerCase());
        if (brandCompare != 0) return brandCompare;

        final formCompare =
        a.formulation.toLowerCase().compareTo(b.formulation.toLowerCase());
        if (formCompare != 0) return formCompare;

        final packingCompare =
        a.packing.toLowerCase().compareTo(b.packing.toLowerCase());
        if (packingCompare != 0) return packingCompare;

        return a.uom.toLowerCase().compareTo(b.uom.toLowerCase());
      });

      if (!mounted) return;

      setState(() {
        _pricelist = List<PricelistItem>.from(items);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('Failed to load pricelist: $e');
    }
  }

  double _parsePercent(String value) {
    final cleaned = value.replaceAll('%', '').trim();
    return double.tryParse(cleaned) ?? 0;
  }

  ({int buy, int free}) _parsePromo(String rawValue) {
    final raw = rawValue.trim().replaceAll(' ', '');
    if (raw.isEmpty || !raw.contains('+')) {
      return (buy: 0, free: 0);
    }

    final parts = raw.split('+');
    if (parts.length != 2) {
      return (buy: 0, free: 0);
    }

    final buy = int.tryParse(parts[0]) ?? 0;
    final free = int.tryParse(parts[1]) ?? 0;
    return (buy: buy, free: free);
  }

  int get _promoBuyQty => _parsePromo(_promoController.text).buy;
  int get _promoFreeQty => _parsePromo(_promoController.text).free;

  bool get _hasFreeGoodsPromo => _promoBuyQty > 0 && _promoFreeQty > 0;
  bool get _hasDiscount => _parsePercent(_discountController.text) > 0;
  bool get _hasDirectDiscount =>
      _parsePercent(_directDiscountController.text) > 0;

  double get _globalDiscountPercent =>
      _hasFreeGoodsPromo || _hasDirectDiscount
          ? 0
          : _parsePercent(_discountController.text);

  double get _globalDirectDiscountPercent =>
      _hasFreeGoodsPromo || _hasDiscount
          ? 0
          : _parsePercent(_directDiscountController.text);

  double get _grossTotal => _draftItems.fold(
    0,
        (sum, item) => sum + item.grossAmount(),
  );

  double get _discountAmount =>
      _grossTotal * (_globalDiscountPercent / 100);

  double get _directDiscountAmount =>
      (_grossTotal - _discountAmount) *
          (_globalDirectDiscountPercent / 100);

  double get _finalTotal =>
      _grossTotal - _discountAmount - _directDiscountAmount;

  int get _totalPaidQty => _draftItems.fold(0, (sum, item) => sum + item.qty);

  int get _totalFreeQty => _draftItems.fold(
    0,
        (sum, item) =>
    sum +
        item.freeQty(
          promoBuyQty: _promoBuyQty,
          promoFreeQty: _promoFreeQty,
          hasDiscount: _hasDiscount,
          hasDirectDiscount: _hasDirectDiscount,
        ),
  );

  int get _totalOverallQty => _draftItems.fold(
    0,
        (sum, item) =>
    sum +
        item.totalQty(
          promoBuyQty: _promoBuyQty,
          promoFreeQty: _promoFreeQty,
          hasDiscount: _hasDiscount,
          hasDirectDiscount: _hasDirectDiscount,
        ),
  );

  void _handlePromoChanged() {
    if (_hasFreeGoodsPromo) {
      if (_discountController.text.trim() != '0') {
        _discountController.text = '0';
      }
      if (_directDiscountController.text.trim() != '0') {
        _directDiscountController.text = '0';
      }
    }
    setState(() {});
  }

  void _handleDiscountChanged() {
    if (_hasDiscount) {
      if (_promoController.text.trim().isNotEmpty) {
        _promoController.text = '';
      }
      if (_directDiscountController.text.trim() != '0') {
        _directDiscountController.text = '0';
      }
    }
    setState(() {});
  }

  void _handleDirectDiscountChanged() {
    if (_hasDirectDiscount) {
      if (_promoController.text.trim().isNotEmpty) {
        _promoController.text = '';
      }
      if (_discountController.text.trim() != '0') {
        _discountController.text = '0';
      }
    }
    setState(() {});
  }

  Future<void> _showItemDetails(PricelistItem item) async {
    final fileName = PricelistManager.normalizeDetailsFile(item.detailsFile);

    String details;
    if (fileName.isEmpty) {
      details = 'No details file assigned for ${item.brand}.';
    } else {
      try {
        details = await rootBundle.loadString('assets/details/$fileName');
      } catch (e) {
        details = 'Unable to load details file: $fileName';
      }
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 560,
            maxHeight: 760,
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFFEAF3FF),
                      Color(0xFFF4F8FF),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.medication_outlined,
                        color: Color(0xFF2F6FD6),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.brand,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (item.category.trim().isNotEmpty)
                                _infoChip(
                                  icon: Icons.category_outlined,
                                  label: item.category,
                                ),
                              _infoChip(
                                icon: Icons.payments_outlined,
                                label: '₱${item.price.toStringAsFixed(2)}',
                              ),
                              if (item.sourcePage != null)
                                _infoChip(
                                  icon: Icons.menu_book_outlined,
                                  label: 'Page ${item.sourcePage}',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionCard(
                          title: 'Product Information',
                          icon: Icons.info_outline,
                          child: Column(
                            children: [
                              _detailRow('Generic', item.generic),
                              _detailRow('Formulation', item.formulation),
                              _detailRow('Packing', item.packWithUom),
                              _detailRow('UOM', item.uom),
                              _detailRow(
                                'Details File',
                                PricelistManager.normalizeDetailsFile(
                                  item.detailsFile,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _sectionCard(
                          title: 'Drug Reference',
                          icon: Icons.description_outlined,
                          child: _buildPharmaStyledDetails(details),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8E6FA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: const Color(0xFF2F6FD6),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: const Color(0xFF2F6FD6),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF2F6FD6),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF334155),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPharmaStyledDetails(String text) {
    final sections = _parseDrugSections(text);

    if (sections.isEmpty) {
      return SelectableText(
        text,
        style: const TextStyle(
          fontSize: 14,
          height: 1.45,
          color: Color(0xFF334155),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections.map((section) {
        final isTitled = section.title.trim().isNotEmpty;

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
              isTitled ? const Color(0xFFF8FBFF) : const Color(0xFFFCFCFD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isTitled
                    ? const Color(0xFFDCEBFF)
                    : const Color(0xFFE5E7EB),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isTitled) ...[
                  Text(
                    section.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2F6FD6),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SelectableText.rich(
                  TextSpan(
                    children: _buildInlineBoldSpans(section.body),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  List<_DrugSection> _parseDrugSections(String text) {
    final rawLines =
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

    final sectionTitles = <String, String>{
      'contents': 'Contents',
      'content': 'Contents',
      'description': 'Description',
      'indications/uses': 'Indications / Uses',
      'indications/use': 'Indications / Uses',
      'indications': 'Indications',
      'uses': 'Uses',
      'dosage/direction for use': 'Dosage / Direction for Use',
      'dosage': 'Dosage',
      'direction for use': 'Direction for Use',
      'contraindications': 'Contraindications',
      'special precaution': 'Special Precaution',
      'special precautions': 'Special Precautions',
      'precautions': 'Precautions',
      'storage': 'Storage',
      'mims class': 'MIMS Class',
      'atc classification': 'ATC Classification',
    };

    final sections = <_DrugSection>[];
    String currentTitle = '';
    final currentBody = StringBuffer();

    void pushCurrent() {
      final body = currentBody.toString().trim();
      if (currentTitle.trim().isNotEmpty || body.isNotEmpty) {
        sections.add(_DrugSection(title: currentTitle.trim(), body: body));
      }
      currentTitle = '';
      currentBody.clear();
    }

    for (final rawLine in rawLines) {
      final line = rawLine.trimRight();
      final normalized = line.trim().toLowerCase();

      final matchedTitle = sectionTitles[normalized];

      if (matchedTitle != null) {
        pushCurrent();
        currentTitle = matchedTitle;
        continue;
      }

      if (currentBody.isNotEmpty) {
        currentBody.writeln();
      }
      currentBody.write(line);
    }

    pushCurrent();

    return sections
        .where((e) => e.title.isNotEmpty || e.body.isNotEmpty)
        .toList();
  }

  List<TextSpan> _buildInlineBoldSpans(String text) {
    final lines = text.split('\n');
    final spans = <TextSpan>[];

    final boldPrefixes = [
      'generic:',
      'formulation:',
      'packing:',
      'uom:',
      'category:',
      'price:',
      'source page:',
      'details file:',
      'contents:',
      'description:',
      'indications:',
      'indications/uses:',
      'dosage:',
      'dosage/direction for use:',
      'contraindications:',
      'special precaution:',
      'special precautions:',
      'precautions:',
      'storage:',
      'mims class:',
      'atc classification:',
    ];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.trim().toLowerCase();

      bool matched = false;

      for (final prefix in boldPrefixes) {
        if (lower.startsWith(prefix)) {
          final colonIndex = line.indexOf(':');
          if (colonIndex >= 0) {
            final label = line.substring(0, colonIndex + 1);
            final value = line.substring(colonIndex + 1).trimLeft();

            spans.add(
              TextSpan(
                text: label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            );
            spans.add(TextSpan(text: value));
            matched = true;
          }
          break;
        }
      }

      if (!matched) {
        spans.add(TextSpan(text: line));
      }

      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }

    return spans;
  }

  Future<void> _pickMedicineAndAdd() async {
    if (_pricelist.isEmpty) {
      _showSnack('No pricelist items found yet.');
      return;
    }

    final picked = await showDialog<List<_DraftOrderItem>>(
      context: context,
      builder: (_) => _MultiPricelistPickerDialog(
        items: _pricelist,
        onInfoTap: _showItemDetails,
      ),
    );

    if (picked == null || picked.isEmpty) return;

    setState(() {
      for (final newItem in picked) {
        final existingIndex = _draftItems.indexWhere(
              (e) =>
          e.brand.toLowerCase() == newItem.brand.toLowerCase() &&
              e.formulation.toLowerCase() ==
                  newItem.formulation.toLowerCase() &&
              e.packing.toLowerCase() == newItem.packing.toLowerCase() &&
              e.uom.toLowerCase() == newItem.uom.toLowerCase(),
        );

        if (existingIndex >= 0) {
          final existing = _draftItems[existingIndex];
          final mergedQty = existing.qty + newItem.qty;
          existing.qtyController.text = mergedQty.toString();
          newItem.dispose();
        } else {
          _draftItems.add(newItem);
        }
      }

      _draftItems.sort((a, b) {
        final brandCompare =
        a.brand.toLowerCase().compareTo(b.brand.toLowerCase());
        if (brandCompare != 0) return brandCompare;

        final formCompare =
        a.formulation.toLowerCase().compareTo(b.formulation.toLowerCase());
        if (formCompare != 0) return formCompare;

        final packingCompare =
        a.packing.toLowerCase().compareTo(b.packing.toLowerCase());
        if (packingCompare != 0) return packingCompare;

        return a.uom.toLowerCase().compareTo(b.uom.toLowerCase());
      });
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    final validItems = _draftItems.where((e) => e.qty > 0).toList();

    if (validItems.isEmpty) {
      _showSnack('Please add at least one item with quantity greater than 0.');
      return;
    }

    if (_medrepController.text.trim().isEmpty) {
      _showSnack('Please enter Medrep.');
      return;
    }

    if (_areaController.text.trim().isEmpty) {
      _showSnack('Please enter Area.');
      return;
    }

    setState(() => _saving = true);

    try {
      final customerDir = widget.invoicesDir.parent;
      final invoicesDir = Directory(p.join(customerDir.path, 'invoices'));
      final ordersDir = Directory(p.join(customerDir.path, 'orders'));

      if (!await invoicesDir.exists()) {
        await invoicesDir.create(recursive: true);
      }
      if (!await ordersDir.exists()) {
        await ordersDir.create(recursive: true);
      }

      final now = DateTime.now();

      final orderNo = widget.isEditMode &&
          (widget.existingOrderNo ?? '').trim().isNotEmpty
          ? widget.existingOrderNo!.trim()
          : 'ORD-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
          '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

      final orderItems = validItems.map((e) {
        final freeQty = e.freeQty(
          promoBuyQty: _promoBuyQty,
          promoFreeQty: _promoFreeQty,
          hasDiscount: _hasDiscount,
          hasDirectDiscount: _hasDirectDiscount,
        );

        return OrderItem(
          category: e.category,
          brand: e.brand,
          generic: e.generic,
          formulation: e.formulation,
          packing: e.packing,
          uom: e.uom,
          unitPrice: e.unitPrice,
          qty: e.qty,
          freeQty: freeQty,
          discountPercent: _globalDiscountPercent,
          directDiscountPercent: _globalDirectDiscountPercent,
        );
      }).toList();

      final existingMap =
      Map<String, dynamic>.from(widget.existingOrderData ?? const {});

      final order = CustomerOrder(
        orderNo: orderNo,
        customerName: widget.customerName,
        dateIso: widget.isEditMode
            ? _toText(existingMap['dateIso']).isNotEmpty
            ? _toText(existingMap['dateIso'])
            : now.toIso8601String()
            : now.toIso8601String(),
        medrep: _medrepController.text.trim(),
        area: _areaController.text.trim(),
        collection: _collectionController.text.trim(),
        freeGoods: _promoController.text.trim(),
        headerNote: _headerNoteController.text.trim(),
        discountPercent: _globalDiscountPercent,
        directDiscountPercent: _globalDirectDiscountPercent,
        items: orderItems,
      );

      final currentFinalTotal = _finalTotal;

      final existingPaymentsRaw = existingMap['payments'];
      final existingPayments = <Map<String, dynamic>>[];

      if (existingPaymentsRaw is List) {
        for (final row in existingPaymentsRaw) {
          if (row is Map) {
            existingPayments.add(Map<String, dynamic>.from(row));
          }
        }
      }

      double amountPaid = 0;
      for (final row in existingPayments) {
        amountPaid += _toDouble(row['amount']);
      }

      if (amountPaid > currentFinalTotal) {
        amountPaid = currentFinalTotal;
      }

      final balance = (currentFinalTotal - amountPaid) < 0
          ? 0.0
          : (currentFinalTotal - amountPaid);

      String status;
      if (currentFinalTotal > 0 && balance <= 0) {
        status = 'PAID';
      } else if (amountPaid > 0) {
        status = 'PARTIAL';
      } else {
        status = 'UNPAID';
      }

      final jsonMap = <String, dynamic>{
        ...order.toJson(),
        'grossTotal': _grossTotal,
        'discountAmount': _discountAmount,
        'directDiscountAmount': _directDiscountAmount,
        'finalTotal': currentFinalTotal,
        'itemCount': validItems.length,
        'payments': existingPayments,
        'amountPaid': amountPaid,
        'balance': balance,
        'status': status,
        'collectedAt': existingMap['collectedAt'],
        'savedAt': now.toIso8601String(),
      };

      final jsonFile =
          widget.existingJsonFile ?? File(p.join(ordersDir.path, '$orderNo.json'));
      await jsonFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(jsonMap),
      );

      final oldPdfPath = widget.existingPdfFile?.path;

      final pdfFile = await InvoicePdf.generate(
        order: order,
        saveDir: invoicesDir,
      );

      if (widget.isEditMode &&
          oldPdfPath != null &&
          oldPdfPath.isNotEmpty &&
          oldPdfPath != pdfFile.path) {
        final oldFile = File(oldPdfPath);
        if (await oldFile.exists()) {
          try {
            await oldFile.delete();
          } catch (_) {}
        }
      }

      await _saveLastInputs();

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => _PreviewDialog(
          order: order,
          grossTotal: _grossTotal,
          discountAmount: _discountAmount,
          directDiscountAmount: _directDiscountAmount,
          finalTotal: currentFinalTotal,
          pdfFile: pdfFile,
        ),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showSnack('Failed to save order: $e');
    } finally {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  void _removeItem(_DraftOrderItem item) {
    setState(() {
      _draftItems.remove(item);
      item.dispose();
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  String peso(double v) => '₱${v.toStringAsFixed(2)}';

  Widget _buildNoPricelistView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 220),
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.medication_outlined,
                size: 58,
                color: Colors.grey,
              ),
              SizedBox(height: 12),
              Text(
                'No pricelist items found yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Go to Pricelist Builder and save your medicine items first.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(widget.isEditMode ? 'Edit Sales Order' : 'New Order'),
        actions: [
          IconButton(
            tooltip: 'Refresh Pricelist',
            onPressed: _loadPricelist,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: widget.isEditMode ? 'Update Order' : 'Save Order',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.save_outlined),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: bottomInset > 0 ? bottomInset + 16 : 76,
        ),
        child: FloatingActionButton.extended(
          onPressed: _pickMedicineAndAdd,
          label: const Text('Add Item'),
          icon: const Icon(Icons.add),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.save),
          label: Text(
            _saving
                ? (widget.isEditMode ? 'Updating...' : 'Saving...')
                : (widget.isEditMode ? 'Update Order' : 'Save Order'),
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pricelist.isEmpty
          ? _buildNoPricelistView()
          : ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 170),
        children: [
          Text(
            widget.customerName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _medrepController,
                  decoration:
                  const InputDecoration(labelText: 'Medrep'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _collectionController,
                  decoration:
                  const InputDecoration(labelText: 'Collection'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _areaController,
                  decoration: const InputDecoration(labelText: 'Area'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _directDiscountController,
                  keyboardType:
                  const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Direct Discount %',
                    hintText: '10 or 10%',
                  ),
                  onChanged: (_) => _handleDirectDiscountChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _promoController,
            decoration: const InputDecoration(
              labelText: 'Free Goods',
              hintText: '1+1, 2+1, 3+1, 5+1, 10+1',
            ),
            onChanged: (_) => _handlePromoChanged(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _discountController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Discount %',
              hintText: '5 or 5%',
            ),
            onChanged: (_) => _handleDiscountChanged(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _headerNoteController,
            decoration: const InputDecoration(
              labelText: 'Header Note',
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isEditMode ? 'Updated Totals' : 'Order Totals',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Paid Qty: $_totalPaidQty'),
                  Text('Free Qty: $_totalFreeQty'),
                  Text('Overall Qty: $_totalOverallQty'),
                  Text('Gross: ${peso(_grossTotal)}'),
                  Text(
                    'Discount (${_globalDiscountPercent.toStringAsFixed(0)}%): ${peso(_discountAmount)}',
                  ),
                  Text(
                    'Direct Discount (${_globalDirectDiscountPercent.toStringAsFixed(0)}%): ${peso(_directDiscountAmount)}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Final Total: ${peso(_finalTotal)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_draftItems.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No items yet. Tap Add Item.'),
              ),
            )
          else
            ..._draftItems.map(
                  (item) => _DraftItemCard(
                key: ValueKey(
                  '${item.brand}_${item.formulation}_${item.packing}_${item.uom}',
                ),
                item: item,
                promoText: _promoController.text.trim(),
                discountPercent: _globalDiscountPercent,
                directDiscountPercent: _globalDirectDiscountPercent,
                hasDiscount: _hasDiscount,
                hasDirectDiscount: _hasDirectDiscount,
                promoBuyQty: _promoBuyQty,
                promoFreeQty: _promoFreeQty,
                onChanged: () => setState(() {}),
                onDelete: () => _removeItem(item),
              ),
            ),
        ],
      ),
    );
  }
}

class _DraftItemCard extends StatelessWidget {
  final _DraftOrderItem item;
  final String promoText;
  final double discountPercent;
  final double directDiscountPercent;
  final bool hasDiscount;
  final bool hasDirectDiscount;
  final int promoBuyQty;
  final int promoFreeQty;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  const _DraftItemCard({
    super.key,
    required this.item,
    required this.promoText,
    required this.discountPercent,
    required this.directDiscountPercent,
    required this.hasDiscount,
    required this.hasDirectDiscount,
    required this.promoBuyQty,
    required this.promoFreeQty,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final freeQty = item.freeQty(
      promoBuyQty: promoBuyQty,
      promoFreeQty: promoFreeQty,
      hasDiscount: hasDiscount,
      hasDirectDiscount: hasDirectDiscount,
    );

    final qtyText = freeQty > 0 ? '${item.qty}+$freeQty' : '${item.qty}';

    String promoLabel = 'None';
    if (promoText.isNotEmpty && !hasDiscount && !hasDirectDiscount) {
      promoLabel = promoText;
    } else if (discountPercent > 0) {
      promoLabel = 'Discount ${discountPercent.toStringAsFixed(0)}%';
    } else if (directDiscountPercent > 0) {
      promoLabel = 'Direct ${directDiscountPercent.toStringAsFixed(0)}%';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$qtyText ${item.uomLabelUpper} ${item.brand}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          item.generic,
                          item.formulation,
                          item.packWithUom,
                        ].where((e) => e.trim().isNotEmpty).join(' • '),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Promo: $promoLabel',
                        style: const TextStyle(
                          color: Color(0xFF2F6FD6),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: item.qtyController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Qty (${item.uomLabelUpper})',
              ),
              onChanged: (_) => onChanged(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewDialog extends StatelessWidget {
  final CustomerOrder order;
  final double grossTotal;
  final double discountAmount;
  final double directDiscountAmount;
  final double finalTotal;
  final File pdfFile;

  const _PreviewDialog({
    required this.order,
    required this.grossTotal,
    required this.discountAmount,
    required this.directDiscountAmount,
    required this.finalTotal,
    required this.pdfFile,
  });

  String peso(double v) => '₱${v.toStringAsFixed(2)}';

  String _uomUpper(String value) {
    final v = value.trim();
    return v.isEmpty ? 'UNIT' : v.toUpperCase();
  }

  String _packWithUom(String packing, String uom) {
    final p = packing.trim();
    final u = uom.trim();
    if (p.isEmpty && u.isEmpty) return '';
    if (p.isEmpty) return u;
    if (u.isEmpty) return p;
    return '$p $u';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(order.orderNo.isNotEmpty ? 'Print Preview' : 'Preview'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Customer: ${order.customerName}'),
              Text('Order No: ${order.orderNo}'),
              Text('Medrep: ${order.medrep}'),
              Text('Area: ${order.area}'),
              if (order.collection.trim().isNotEmpty)
                Text('Collection: ${order.collection}'),
              if (order.freeGoods.trim().isNotEmpty)
                Text('Free Goods: ${order.freeGoods}'),
              if (order.headerNote.trim().isNotEmpty)
                Text('Header Note: ${order.headerNote}'),
              Text('Discount: ${order.discountPercent.toStringAsFixed(0)}%'),
              Text(
                'Direct Discount: ${order.directDiscountPercent.toStringAsFixed(0)}%',
              ),
              const SizedBox(height: 10),
              const Text(
                'Order Summary',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Divider(),
              ...order.items.map((e) {
                final qtyText = e.freeQty > 0 ? '${e.qty}+${e.freeQty}' : '${e.qty}';
                final packDisplay = _packWithUom(e.packing, e.uom);

                String promoText = '';
                if (e.freeQty > 0) {
                  promoText = ' [FREE GOODS]';
                } else if (e.discountPercent > 0) {
                  promoText = ' [DISCOUNT ${e.discountPercent.toStringAsFixed(0)}%]';
                } else if (e.directDiscountPercent > 0) {
                  promoText = ' [DIRECT ${e.directDiscountPercent.toStringAsFixed(0)}%]';
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '$qtyText ${_uomUpper(e.uom)} ${e.brand}$promoText\n'
                        '${[
                      e.generic,
                      e.formulation,
                      packDisplay,
                    ].where((x) => x.trim().isNotEmpty).join(' • ')}\n'
                        '@${e.unitPrice.toStringAsFixed(2)} = ${peso(e.unitPrice * e.qty)}',
                  ),
                );
              }),
              const Divider(),
              Text('Gross Total: ${peso(grossTotal)}'),
              Text('Discount: ${peso(discountAmount)}'),
              Text('Direct Discount: ${peso(directDiscountAmount)}'),
              const SizedBox(height: 6),
              Text(
                'Final Total: ${peso(finalTotal)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () async {
            await OpenFilex.open(pdfFile.path);
          },
          child: const Text('Open PDF'),
        ),
      ],
    );
  }
}

class _DraftOrderItem {
  final String category;
  final String brand;
  final String generic;
  final String formulation;
  final String packing;
  final String uom;
  final double unitPrice;

  final TextEditingController qtyController;

  _DraftOrderItem({
    required this.category,
    required this.brand,
    required this.generic,
    required this.formulation,
    required this.packing,
    this.uom = '',
    required this.unitPrice,
    required this.qtyController,
  });

  factory _DraftOrderItem.fromPricelist(PricelistItem item) {
    return _DraftOrderItem(
      category: item.category,
      brand: item.brand,
      generic: item.generic,
      formulation: item.formulation,
      packing: item.packing,
      uom: item.uom,
      unitPrice: item.price,
      qtyController: TextEditingController(text: '0'),
    );
  }

  int get qty => int.tryParse(qtyController.text.trim()) ?? 0;

  String get packWithUom {
    final p = packing.trim();
    final u = uom.trim();
    if (p.isEmpty && u.isEmpty) return '';
    if (p.isEmpty) return u;
    if (u.isEmpty) return p;
    return '$p $u';
  }

  String get uomLabelUpper {
    final trimmed = uom.trim();
    return trimmed.isEmpty ? 'UNIT' : trimmed.toUpperCase();
  }

  int freeQty({
    required int promoBuyQty,
    required int promoFreeQty,
    required bool hasDiscount,
    required bool hasDirectDiscount,
  }) {
    if (hasDiscount || hasDirectDiscount) return 0;
    if (promoBuyQty <= 0 || promoFreeQty <= 0 || qty <= 0) return 0;
    return (qty ~/ promoBuyQty) * promoFreeQty;
  }

  int totalQty({
    required int promoBuyQty,
    required int promoFreeQty,
    required bool hasDiscount,
    required bool hasDirectDiscount,
  }) {
    return qty +
        freeQty(
          promoBuyQty: promoBuyQty,
          promoFreeQty: promoFreeQty,
          hasDiscount: hasDiscount,
          hasDirectDiscount: hasDirectDiscount,
        );
  }

  double grossAmount() {
    return qty * unitPrice;
  }

  void dispose() {
    qtyController.dispose();
  }
}

class _MultiPricelistPickerDialog extends StatefulWidget {
  final List<PricelistItem> items;
  final Future<void> Function(PricelistItem item) onInfoTap;

  const _MultiPricelistPickerDialog({
    required this.items,
    required this.onInfoTap,
  });

  @override
  State<_MultiPricelistPickerDialog> createState() =>
      _MultiPricelistPickerDialogState();
}

class _MultiPricelistPickerDialogState
    extends State<_MultiPricelistPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  late List<_MultiEntryRowState> _rows;

  @override
  void initState() {
    super.initState();

    final sorted = [...widget.items]
      ..sort((a, b) {
        final brandCompare =
        a.brand.toLowerCase().compareTo(b.brand.toLowerCase());
        if (brandCompare != 0) return brandCompare;

        final formCompare =
        a.formulation.toLowerCase().compareTo(b.formulation.toLowerCase());
        if (formCompare != 0) return formCompare;

        final packingCompare =
        a.packing.toLowerCase().compareTo(b.packing.toLowerCase());
        if (packingCompare != 0) return packingCompare;

        return a.uom.toLowerCase().compareTo(b.uom.toLowerCase());
      });

    _rows = sorted.map((e) => _MultiEntryRowState(item: e)).toList();

    _searchController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  List<_MultiEntryRowState> get _filteredRows {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _rows;

    final filtered = _rows.where((row) {
      final item = row.item;
      return item.brand.toLowerCase().contains(q) ||
          item.generic.toLowerCase().contains(q) ||
          item.formulation.toLowerCase().contains(q) ||
          item.packing.toLowerCase().contains(q) ||
          item.uom.toLowerCase().contains(q) ||
          item.category.toLowerCase().contains(q) ||
          item.detailsFile.toLowerCase().contains(q);
    }).toList();

    filtered.sort((a, b) {
      final brandCompare =
      a.item.brand.toLowerCase().compareTo(b.item.brand.toLowerCase());
      if (brandCompare != 0) return brandCompare;

      final formCompare = a.item.formulation.toLowerCase().compareTo(
        b.item.formulation.toLowerCase(),
      );
      if (formCompare != 0) return formCompare;

      final packingCompare =
      a.item.packing.toLowerCase().compareTo(b.item.packing.toLowerCase());
      if (packingCompare != 0) return packingCompare;

      return a.item.uom.toLowerCase().compareTo(b.item.uom.toLowerCase());
    });

    return filtered;
  }

  int get _selectedCount => _rows.where((row) => row.qty > 0).length;

  void _submitSelected() {
    final selected = _rows
        .where((row) => row.qty > 0)
        .map((row) => row.toDraftOrderItem())
        .toList();

    Navigator.pop(context, selected);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;
    final screen = MediaQuery.of(context).size;
    final dialogHeight = screen.height * 0.82;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
      ),
      child: SizedBox(
        width: 900,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select Medicine',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText:
                  'Search brand, generic, formulation, packing, uom...',
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('No matching items'))
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return _MultiPricelistEntryCard(
                    row: row,
                    onChanged: () => setState(() {}),
                    onInfoTap: () => widget.onInfoTap(row.item),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(26),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Selected: $_selectedCount item${_selectedCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _submitSelected,
                    icon: const Icon(Icons.add_shopping_cart, size: 18),
                    label: const Text('Add Selected'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MultiEntryRowState {
  final PricelistItem item;
  final TextEditingController qtyController;

  _MultiEntryRowState({
    required this.item,
  }) : qtyController = TextEditingController(text: '0');

  int get qty => int.tryParse(qtyController.text.trim()) ?? 0;

  _DraftOrderItem toDraftOrderItem() {
    return _DraftOrderItem(
      category: item.category,
      brand: item.brand,
      generic: item.generic,
      formulation: item.formulation,
      packing: item.packing,
      uom: item.uom,
      unitPrice: item.price,
      qtyController: TextEditingController(text: qty.toString()),
    );
  }

  void dispose() {
    qtyController.dispose();
  }
}

class _MultiPricelistEntryCard extends StatelessWidget {
  final _MultiEntryRowState row;
  final VoidCallback onChanged;
  final VoidCallback? onInfoTap;

  const _MultiPricelistEntryCard({
    required this.row,
    required this.onChanged,
    this.onInfoTap,
  });

  Future<void> _showQtyInputDialog(BuildContext context) async {
    final controller = TextEditingController(text: row.qty.toString());

    final result = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enter Quantity'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Type quantity',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim()) ?? 0;
              Navigator.pop(context, value);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (result != null) {
      row.qtyController.text = result.toString();
      onChanged();
    }
  }

  void _decrementQty() {
    final current = row.qty;
    if (current > 0) {
      row.qtyController.text = (current - 1).toString();
      onChanged();
    }
  }

  void _incrementQty() {
    final current = row.qty;
    row.qtyController.text = (current + 1).toString();
    onChanged();
  }

  void _decrementQtyFast() {
    final current = row.qty;
    final newValue = current - 10;
    row.qtyController.text = (newValue < 0 ? 0 : newValue).toString();
    onChanged();
  }

  void _incrementQtyFast() {
    final current = row.qty;
    row.qtyController.text = (current + 10).toString();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final item = row.item;
    final uomUpper =
    item.uom.trim().isEmpty ? 'UNIT' : item.uom.trim().toUpperCase();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7DFEA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.brand,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    item.generic,
                    item.formulation,
                    item.packWithUom,
                  ].where((e) => e.trim().isNotEmpty).join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.category,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2F6FD6),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                if (item.detailsFile.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Info file: ${item.detailsFile}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '₱${item.price.toStringAsFixed(2)} / $uomUpper',
                  style: const TextStyle(
                    color: Color(0xFF2F6FD6),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: onInfoTap,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(64, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('Info'),
              ),
              const SizedBox(height: 8),
              Text(
                'Qty ($uomUpper)',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD7DFEA)),
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _decrementQty,
                      onLongPress: _decrementQtyFast,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.remove, size: 16),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _showQtyInputDialog(context),
                      child: SizedBox(
                        width: 34,
                        child: Text(
                          row.qty.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _incrementQty,
                      onLongPress: _incrementQtyFast,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.add, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Tap #',
                style: TextStyle(
                  fontSize: 9.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DrugSection {
  final String title;
  final String body;

  const _DrugSection({
    required this.title,
    required this.body,
  });
}