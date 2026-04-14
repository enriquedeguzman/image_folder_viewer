import 'package:flutter/material.dart';
import '../../services/pricelist_manager.dart';

class PricelistImportPage extends StatefulWidget {
  const PricelistImportPage({super.key});

  @override
  State<PricelistImportPage> createState() => _PricelistImportPageState();
}

class _PricelistImportPageState extends State<PricelistImportPage> {
  List<PricelistItem> _items = [];
  List<PricelistItem> _filteredItems = [];

  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  static const List<String> _uomOptions = [
    '',
    'box',
    'bot',
    'amp',
    'vial',
    'tab',
    'cap',
    'sachet',
    'tube',
    'pc',
  ];

  @override
  void initState() {
    super.initState();
    _loadItems();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);

    try {
      final items = await PricelistManager.loadPricelistItems();

      if (!mounted) return;
      setState(() {
        _items = List<PricelistItem>.from(items);
        _sortItems();
        _loading = false;
      });

      _applyFilter();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('Failed to load pricelist: $e');
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = query.isEmpty
        ? List<PricelistItem>.from(_items)
        : _items.where((item) {
      return item.category.toLowerCase().contains(query) ||
          item.brand.toLowerCase().contains(query) ||
          item.generic.toLowerCase().contains(query) ||
          item.formulation.toLowerCase().contains(query) ||
          item.packing.toLowerCase().contains(query) ||
          item.uom.toLowerCase().contains(query) ||
          item.packWithUom.toLowerCase().contains(query) ||
          item.price.toString().contains(query) ||
          item.detailsFile.toLowerCase().contains(query) ||
          item.imageFile.toLowerCase().contains(query);
    }).toList();

    if (!mounted) return;
    setState(() {
      _filteredItems = filtered;
    });
  }

  Future<void> _saveItems() async {
    setState(() => _saving = true);

    try {
      await PricelistManager.savePricelistItems(_items);

      if (!mounted) return;
      setState(() => _saving = false);

      _showSnack('Pricelist saved successfully.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack('Failed to save pricelist: $e');
    }
  }

  Future<void> _addItem() async {
    final item = await _showItemDialog();

    if (item != null) {
      setState(() {
        _items.add(item);
        _sortItems();
      });
      _applyFilter();
    }
  }

  Future<void> _editItem(PricelistItem item) async {
    final index = _items.indexOf(item);
    if (index == -1) return;

    final updated = await _showItemDialog(existing: item);

    if (updated != null) {
      setState(() {
        _items[index] = updated;
        _sortItems();
      });
      _applyFilter();
    }
  }

  Future<void> _deleteItem(PricelistItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Item'),
          content: Text('Delete "${item.brand}" from pricelist?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _items.remove(item);
    });
    _applyFilter();
  }

  void _sortItems() {
    _items.sort((a, b) {
      final brandCompare =
      a.brand.toLowerCase().compareTo(b.brand.toLowerCase());
      if (brandCompare != 0) return brandCompare;

      final formulationCompare =
      a.formulation.toLowerCase().compareTo(b.formulation.toLowerCase());
      if (formulationCompare != 0) return formulationCompare;

      final packingCompare =
      a.packing.toLowerCase().compareTo(b.packing.toLowerCase());
      if (packingCompare != 0) return packingCompare;

      return a.uom.toLowerCase().compareTo(b.uom.toLowerCase());
    });
  }

  Future<PricelistItem?> _showItemDialog({PricelistItem? existing}) async {
    final category = TextEditingController(text: existing?.category ?? '');
    final brand = TextEditingController(text: existing?.brand ?? '');
    final generic = TextEditingController(text: existing?.generic ?? '');
    final formulation = TextEditingController(text: existing?.formulation ?? '');
    final packing = TextEditingController(text: existing?.packing ?? '');
    String selectedUom = PricelistManager.normalizeUom(existing?.uom ?? '');

    final price = TextEditingController(
      text: existing != null ? existing.price.toStringAsFixed(2) : '',
    );
    final sourcePage = TextEditingController(
      text: existing?.sourcePage?.toString() ?? '',
    );
    final detailsFile =
    TextEditingController(text: existing?.detailsFile ?? '');
    final imageFile = TextEditingController(text: existing?.imageFile ?? '');

    return showDialog<PricelistItem>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                existing == null ? 'Add Pricelist Item' : 'Edit Pricelist Item',
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _field(category, 'Category'),
                      _field(brand, 'Brand'),
                      _field(generic, 'Generic'),
                      _field(formulation, 'Formulation'),
                      _field(packing, 'Packing'),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DropdownButtonFormField<String>(
                          value: _uomOptions.contains(selectedUom)
                              ? selectedUom
                              : '',
                          items: _uomOptions
                              .map(
                                (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e.isEmpty ? 'UOM' : e),
                            ),
                          )
                              .toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedUom =
                                  PricelistManager.normalizeUom(value ?? '');
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'UOM',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      _field(price, 'Price', isNumber: true),
                      _field(sourcePage, 'Source Page', isNumber: true),
                      _field(detailsFile, 'Details File'),
                      _field(imageFile, 'Image File'),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (brand.text.trim().isEmpty) {
                      _showSnack('Brand is required.');
                      return;
                    }

                    Navigator.pop(
                      context,
                      PricelistItem(
                        category: category.text.trim(),
                        brand: brand.text.trim(),
                        generic: generic.text.trim(),
                        formulation: formulation.text.trim(),
                        packing: packing.text.trim(),
                        uom: selectedUom,
                        price: double.tryParse(price.text.trim()) ?? 0,
                        sourcePage: int.tryParse(sourcePage.text.trim()),
                        detailsFile: detailsFile.text.trim(),
                        imageFile: imageFile.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _field(
      TextEditingController controller,
      String label, {
        bool isNumber = false,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7DFEA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.medication_outlined,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pricelist Builder',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_items.length} item${_items.length == 1 ? '' : 's'} in master pricelist',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(PricelistItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        title: Text(
          item.brand.isEmpty ? '(No Brand)' : item.brand,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.generic.isNotEmpty) Text('Generic: ${item.generic}'),
              if (item.formulation.isNotEmpty)
                Text('Formulation: ${item.formulation}'),
              if (item.packWithUom.isNotEmpty)
                Text('Packing: ${item.packWithUom}'),
              if (item.category.isNotEmpty) Text('Category: ${item.category}'),
              if (item.sourcePage != null)
                Text('Source Page: ${item.sourcePage}'),
              if (item.detailsFile.isNotEmpty)
                Text('Details File: ${item.detailsFile}'),
              if (item.imageFile.isNotEmpty)
                Text('Image File: ${item.imageFile}'),
              const SizedBox(height: 4),
              Text(
                'Price: ₱${item.price.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.indigo,
                ),
              ),
            ],
          ),
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editItem(item),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteItem(item),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.list_alt_outlined,
                size: 58,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(
                _items.isEmpty
                    ? 'No pricelist items yet'
                    : 'No items match your search',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _items.isEmpty
                    ? 'Tap Add Item to build your pricelist.'
                    : 'Try another keyword.',
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
        title: const Text(
          'Pricelist Builder',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadItems,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: bottomInset > 0 ? bottomInset + 16 : 76,
        ),
        child: FloatingActionButton.extended(
          onPressed: _addItem,
          icon: const Icon(Icons.add),
          label: const Text('Add Item'),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: FilledButton(
            onPressed: _saving ? null : _saveItems,
            child: Text(_saving ? 'Saving...' : 'Save Pricelist'),
          ),
        ),
      ),
      body: Container(
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
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                children: [
                  _buildSummaryCard(),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText:
                      'Search brand, generic, formulation, packing, uom...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _filteredItems.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                padding:
                const EdgeInsets.fromLTRB(12, 4, 12, 160),
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  return _buildItemCard(_filteredItems[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}