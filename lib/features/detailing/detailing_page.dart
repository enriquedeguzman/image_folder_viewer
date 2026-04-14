import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../services/pricelist_manager.dart';

const Color kGold = Color(0xFFD4A017);
const Color kDarkGold = Color(0xFFB8860B);
const Color kGreen = Color(0xFF2E7D32);
const Color kLightGreen = Color(0xFF388E3C);

class DetailingPage extends StatefulWidget {
  const DetailingPage({super.key});

  @override
  State<DetailingPage> createState() => _DetailingPageState();
}

class _DetailingPageState extends State<DetailingPage> {
  List<PricelistItem> _items = [];
  List<PricelistItem> _filteredItems = [];
  bool _loading = true;
  String _searchText = '';

  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _detailsCache = {};

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    try {
      final items = await PricelistManager.loadPricelistItems();

      if (!mounted) return;

      setState(() {
        _items = items;
        _filteredItems = List<PricelistItem>.from(items);
        _loading = false;
      });

      _preloadDetails();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load pricelist: $e')),
      );
    }
  }

  void _applySearch(String value) {
    final query = value.trim().toLowerCase();

    setState(() {
      _searchText = value;

      if (query.isEmpty) {
        _filteredItems = List<PricelistItem>.from(_items);
        return;
      }

      _filteredItems = _items.where((item) {
        final haystack = [
          item.brand,
          item.generic,
          item.formulation,
          item.packing,
          item.uom,
          item.category,
        ].join(' ').toLowerCase();

        return haystack.contains(query);
      }).toList();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _applySearch('');
  }

  String _slugify(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r"[']"), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  List<String> _buildDetailsCandidates(PricelistItem item) {
    final result = <String>[];
    final seen = <String>{};

    void add(String value) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) return;
      if (seen.add(normalized)) {
        result.add(normalized);
      }
    }

    if (item.detailsFile.trim().isNotEmpty) {
      add(item.detailsFile);
    }

    final brandSlug = _slugify(item.brand);
    if (brandSlug.isNotEmpty) add('$brandSlug.txt');

    final brandFormSlug = _slugify('${item.brand} ${item.formulation}');
    if (brandFormSlug.isNotEmpty) add('$brandFormSlug.txt');

    final fullSlug =
    _slugify('${item.brand} ${item.formulation} ${item.packing}');
    if (fullSlug.isNotEmpty) add('$fullSlug.txt');

    return result;
  }

  Future<String> _loadDetailsFromAsset(String fileName) async {
    final normalized = fileName.trim().toLowerCase();
    if (normalized.isEmpty) return '';

    try {
      return await rootBundle.loadString('assets/details/$normalized');
    } catch (_) {
      return '';
    }
  }

  Future<void> _preloadDetails() async {
    for (final item in _items) {
      final candidates = _buildDetailsCandidates(item);

      for (final candidate in candidates) {
        final key = candidate.toLowerCase();
        if (_detailsCache.containsKey(key)) continue;

        final content = await _loadDetailsFromAsset(candidate);

        if (!mounted) return;

        setState(() {
          _detailsCache[key] = content;
        });

        if (content.isNotEmpty) break;
      }
    }
  }

  String _getCachedDetails(PricelistItem item) {
    final candidates = _buildDetailsCandidates(item);

    for (final candidate in candidates) {
      final value = _detailsCache[candidate.toLowerCase()];
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  String _extractIndication(String content) {
    if (content.trim().isEmpty) return '';

    final text = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = text.split('\n');

    bool capture = false;
    final buffer = StringBuffer();

    for (final rawLine in lines) {
      final line = rawLine.trim();
      final lower = line.toLowerCase();

      if (!capture) {
        if (lower.startsWith('indication') ||
            lower.startsWith('indications') ||
            lower.contains('indications/uses')) {
          capture = true;
          continue;
        }
      } else {
        if (lower.startsWith('dosage') ||
            lower.startsWith('dosage/direction') ||
            lower.startsWith('contraindication') ||
            lower.startsWith('special precaution') ||
            lower.startsWith('special precautions') ||
            lower.startsWith('storage') ||
            lower.startsWith('mims') ||
            lower.startsWith('atc')) {
          break;
        }

        if (line.isNotEmpty) {
          buffer.writeln(line);
        }
      }
    }

    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _assetImagePath(PricelistItem item) {
    if (item.imageFile.trim().isNotEmpty) {
      return 'assets/master_data/medicine_images/${item.imageFile.trim().toLowerCase()}';
    }

    final generated = _slugify(
      '${item.brand} ${item.formulation} ${item.packing}',
    );
    if (generated.isEmpty) return '';
    return 'assets/master_data/medicine_images/$generated.png';
  }

  String _formatMoney(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts[0];
    final decimal = parts.length > 1 ? parts[1] : '00';

    return '$whole.$decimal'.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
    );
  }

  void _openAssetImagePreview(PricelistItem item) {
    final assetPath = _assetImagePath(item);
    if (assetPath.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _DetailingAssetImagePreviewPage(
          assetPath: assetPath,
          title: item.brand,
          subtitle: item.formulation,
        ),
      ),
    );
  }

  void _openMedicineDetails(PricelistItem item) {
    final currentIndex = _filteredItems.indexWhere(
          (e) =>
      e.brand == item.brand &&
          e.formulation == item.formulation &&
          e.packing == item.packing &&
          e.uom == item.uom,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MedicineDetailsPage(
          item: item,
          assetImagePath: _assetImagePath(item),
          detailsText: _getCachedDetails(item),
          onOpenAssetImage: () => _openAssetImagePreview(item),
          onOpenPresentation: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MedRepPresentationPage(
                  items: _filteredItems,
                  initialIndex: currentIndex < 0 ? 0 : currentIndex,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: TextField(
        controller: _searchController,
        onChanged: _applySearch,
        decoration: InputDecoration(
          hintText: 'Search medicine, generic, formulation, uom...',
          prefixIcon: const Icon(Icons.search, color: kGreen),
          suffixIcon: _searchText.trim().isEmpty
              ? null
              : IconButton(
            onPressed: _clearSearch,
            icon: const Icon(Icons.close),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kGreen),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kGreen),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kGold, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildMedicineImage(PricelistItem item) {
    final assetPath = _assetImagePath(item);

    if (assetPath.isNotEmpty) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openAssetImagePreview(item),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kGold, width: 0.9),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              assetPath,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.medication_outlined,
                    size: 34,
                    color: Colors.white70,
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kGold, width: 0.9),
      ),
      child: const Icon(
        Icons.medication_outlined,
        size: 34,
        color: Colors.white70,
      ),
    );
  }

  Widget _buildMedicineCard(PricelistItem item) {
    final details = _getCachedDetails(item);
    final indication = _extractIndication(details);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openMedicineDetails(item),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [
              kGreen.withOpacity(0.88),
              kLightGreen.withOpacity(0.78),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: kGreen.withOpacity(0.28),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kGold.withOpacity(0.85), width: 1),
            color: Colors.white.withOpacity(0.05),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMedicineImage(item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.brand,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Colors.white.withOpacity(0.96),
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (item.generic.trim().isNotEmpty)
                      Text(
                        item.generic,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.86),
                        ),
                      ),
                    if (item.formulation.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.formulation,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.84),
                        ),
                      ),
                    ],
                    if (item.packing.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Pack: ${item.packing}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.84),
                        ),
                      ),
                    ],
                    if (item.uom.trim().isNotEmpty)
                      Text(
                        'UOM: ${item.uom}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.84),
                        ),
                      ),
                    if (item.category.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Category: ${item.category}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.72),
                        ),
                      ),
                    ],
                    if (indication.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: kGreen.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: Text(
                          indication,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: Colors.white.withOpacity(0.88),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '₱${_formatMoney(item.price)}${item.uom.isNotEmpty ? ' / ${item.uom}' : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: kGold,
                      ),
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return const Center(child: Text('No pricelist items found'));
    }

    return Column(
      children: [
        _buildSearchBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Results: ${_filteredItems.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
        ),
        Expanded(
          child: _filteredItems.isEmpty
              ? const Center(
            child: Text('No matching medicine found'),
          )
              : ListView.builder(
            padding: const EdgeInsets.only(top: 2, bottom: 12),
            itemCount: _filteredItems.length,
            itemBuilder: (context, index) {
              final item = _filteredItems[index];
              return _buildMedicineCard(item);
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detailing'),
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }
}

class MedicineDetailsPage extends StatelessWidget {
  final PricelistItem item;
  final String assetImagePath;
  final String detailsText;
  final VoidCallback? onOpenAssetImage;
  final VoidCallback? onOpenPresentation;

  const MedicineDetailsPage({
    super.key,
    required this.item,
    required this.assetImagePath,
    required this.detailsText,
    this.onOpenAssetImage,
    this.onOpenPresentation,
  });

  String _sectionText(String title, String source) {
    if (source.trim().isEmpty) return '';

    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');

    bool capture = false;
    final buffer = StringBuffer();

    final headers = <String>[
      'contents',
      'description',
      'indication',
      'indications',
      'indications/uses',
      'dosage',
      'dosage/direction',
      'contraindication',
      'contraindications',
      'special precaution',
      'special precautions',
      'storage',
      'mims',
      'atc',
      'mims class',
      'atc classification',
    ];

    final wanted = title.toLowerCase();

    for (final raw in lines) {
      final line = raw.trim();
      final lower = line.toLowerCase();

      if (!capture) {
        if (lower.startsWith(wanted)) {
          capture = true;

          final colonIndex = line.indexOf(':');
          if (colonIndex >= 0 && colonIndex < line.length - 1) {
            final after = line.substring(colonIndex + 1).trim();
            if (after.isNotEmpty) {
              buffer.writeln(after);
            }
          }
          continue;
        }
      } else {
        if (line.isEmpty) {
          if (buffer.isNotEmpty) break;
          continue;
        }

        final isNextHeader = headers.any((h) => lower.startsWith(h));
        if (isNextHeader) break;

        buffer.writeln(line);
      }
    }

    return buffer.toString().trim();
  }

  String _formatMoney(double value) {
    return value.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
    );
  }

  Widget _buildInfoRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.35,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: kGold,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(String title, String body) {
    if (body.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kGreen, kLightGreen],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kGold, width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: kGold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body.replaceAll(RegExp(r'\n{2,}'), '\n\n'),
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormattedDetails(String text) {
    if (text.trim().isEmpty) return const SizedBox();

    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    final spans = <TextSpan>[];

    bool isHeader(String line) {
      final lower = line.trim().toLowerCase();

      return lower.startsWith('contents') ||
          lower.startsWith('description') ||
          lower.startsWith('indication') ||
          lower.startsWith('indications') ||
          lower.startsWith('indications/uses') ||
          lower.startsWith('dosage') ||
          lower.startsWith('dosage/direction') ||
          lower.startsWith('contraindication') ||
          lower.startsWith('contraindications') ||
          lower.startsWith('special precaution') ||
          lower.startsWith('special precautions') ||
          lower.startsWith('storage') ||
          lower.startsWith('mims') ||
          lower.startsWith('mims class') ||
          lower.startsWith('atc') ||
          lower.startsWith('atc classification');
    }

    for (final raw in lines) {
      final line = raw.trim();

      if (line.isEmpty) {
        spans.add(const TextSpan(text: '\n\n'));
        continue;
      }

      if (isHeader(line)) {
        spans.add(
          TextSpan(
            text: '$line\n',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: kGold,
              height: 1.4,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: '$line\n',
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.white,
            ),
          ),
        );
      }
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contents = _sectionText('contents', detailsText);
    final description = _sectionText('description', detailsText);
    final indication = _sectionText('indications/uses', detailsText).isNotEmpty
        ? _sectionText('indications/uses', detailsText)
        : (_sectionText('indication', detailsText).isNotEmpty
        ? _sectionText('indication', detailsText)
        : _sectionText('indications', detailsText));

    final dosage = _sectionText('dosage/direction', detailsText).isNotEmpty
        ? _sectionText('dosage/direction', detailsText)
        : (_sectionText('dosage', detailsText).isNotEmpty
        ? _sectionText('dosage', detailsText)
        : _sectionText('dose', detailsText));

    final contraindications =
    _sectionText('contraindications', detailsText).isNotEmpty
        ? _sectionText('contraindications', detailsText)
        : _sectionText('contraindication', detailsText);

    final precautions =
    _sectionText('special precautions', detailsText).isNotEmpty
        ? _sectionText('special precautions', detailsText)
        : _sectionText('special precaution', detailsText);

    final storage = _sectionText('storage', detailsText);
    final mimsClass = _sectionText('mims class', detailsText);
    final atc = _sectionText('atc classification', detailsText);

    return Scaffold(
      backgroundColor: const Color(0xFF102915),
      appBar: AppBar(
        title: const Text('Medicine Details'),
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        actions: [
          if (onOpenPresentation != null)
            IconButton(
              onPressed: onOpenPresentation,
              icon: const Icon(Icons.slideshow_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kGreen, kLightGreen],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: kGold, width: 0.9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: onOpenAssetImage,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: assetImagePath.trim().isNotEmpty
                          ? Image.asset(
                        assetImagePath,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          return Container(
                            height: 220,
                            width: double.infinity,
                            color: Colors.white.withOpacity(0.08),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.medication_outlined,
                              size: 72,
                              color: Colors.white70,
                            ),
                          );
                        },
                      )
                          : Container(
                        height: 220,
                        width: double.infinity,
                        color: Colors.white.withOpacity(0.08),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.medication_outlined,
                          size: 72,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onOpenPresentation,
                    style: FilledButton.styleFrom(
                      backgroundColor: kGold,
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.slideshow_outlined),
                    label: const Text('Presentation Mode'),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  item.brand,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                _buildInfoRow('Generic', item.generic),
                _buildInfoRow('Formulation', item.formulation),
                _buildInfoRow('Packing', item.packing),
                _buildInfoRow('UOM', item.uom),
                _buildInfoRow('Category', item.category),
                _buildInfoRow(
                  'Price',
                  '₱${_formatMoney(item.price)}${item.uom.isNotEmpty ? ' / ${item.uom}' : ''}',
                ),
              ],
            ),
          ),
          _buildSectionCard('Contents', contents),
          _buildSectionCard('Description', description),
          _buildSectionCard('Indication', indication),
          _buildSectionCard('Dosage', dosage),
          _buildSectionCard('Contraindications', contraindications),
          _buildSectionCard('Special Precautions', precautions),
          _buildSectionCard('Storage', storage),
          _buildSectionCard('MIMS Class', mimsClass),
          _buildSectionCard('ATC Classification', atc),
          if (detailsText.trim().isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [kGreen, kLightGreen],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kGold, width: 0.9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Full Details',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: kGold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildFormattedDetails(detailsText),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class MedRepPresentationPage extends StatefulWidget {
  final List<PricelistItem> items;
  final int initialIndex;

  const MedRepPresentationPage({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  @override
  State<MedRepPresentationPage> createState() => _MedRepPresentationPageState();
}

class _MedRepPresentationPageState extends State<MedRepPresentationPage> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _showOverlay = true;
  final Map<String, String> _detailsCache = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _preloadAround(_currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _slugify(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r"[']"), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  List<String> _buildDetailsCandidates(PricelistItem item) {
    final result = <String>[];
    final seen = <String>{};

    void add(String value) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) return;
      if (seen.add(normalized)) {
        result.add(normalized);
      }
    }

    if (item.detailsFile.trim().isNotEmpty) {
      add(item.detailsFile);
    }

    final brandSlug = _slugify(item.brand);
    if (brandSlug.isNotEmpty) add('$brandSlug.txt');

    final brandFormSlug = _slugify('${item.brand} ${item.formulation}');
    if (brandFormSlug.isNotEmpty) add('$brandFormSlug.txt');

    final fullSlug =
    _slugify('${item.brand} ${item.formulation} ${item.packing}');
    if (fullSlug.isNotEmpty) add('$fullSlug.txt');

    return result;
  }

  Future<String> _loadDetailsFromAsset(String fileName) async {
    final normalized = fileName.trim().toLowerCase();
    if (normalized.isEmpty) return '';

    try {
      return await rootBundle.loadString('assets/details/$normalized');
    } catch (_) {
      return '';
    }
  }

  Future<void> _ensureDetailsLoaded(PricelistItem item) async {
    final candidates = _buildDetailsCandidates(item);

    for (final candidate in candidates) {
      final key = candidate.toLowerCase();
      if (_detailsCache.containsKey(key)) {
        if ((_detailsCache[key] ?? '').isNotEmpty) return;
        continue;
      }

      final content = await _loadDetailsFromAsset(candidate);
      if (!mounted) return;

      setState(() {
        _detailsCache[key] = content;
      });

      if (content.isNotEmpty) return;
    }
  }

  Future<void> _preloadAround(int index) async {
    final indexes = <int>{index, index - 1, index + 1};

    for (final i in indexes) {
      if (i < 0 || i >= widget.items.length) continue;
      await _ensureDetailsLoaded(widget.items[i]);
    }
  }

  String _getCachedDetails(PricelistItem item) {
    final candidates = _buildDetailsCandidates(item);
    for (final candidate in candidates) {
      final value = _detailsCache[candidate.toLowerCase()];
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  String _sectionText(List<String> titles, String source) {
    if (source.trim().isEmpty) return '';

    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    bool capture = false;
    final buffer = StringBuffer();

    final headers = <String>[
      'contents',
      'description',
      'indication',
      'indications',
      'indications/uses',
      'dosage',
      'dosage/direction',
      'dosage/direction for use',
      'contraindication',
      'contraindications',
      'special precaution',
      'special precautions',
      'storage',
      'mims',
      'mims class',
      'atc',
      'atc classification',
    ];

    for (final raw in lines) {
      final line = raw.trim();
      final lower = line.toLowerCase();

      if (!capture) {
        final matched = titles.any((t) => lower.startsWith(t));
        if (matched) {
          capture = true;
          final colonIndex = line.indexOf(':');
          if (colonIndex >= 0 && colonIndex < line.length - 1) {
            final after = line.substring(colonIndex + 1).trim();
            if (after.isNotEmpty) {
              buffer.writeln(after);
            }
          }
          continue;
        }
      } else {
        if (line.isEmpty) {
          if (buffer.isNotEmpty) break;
          continue;
        }

        final isNextHeader = headers.any((h) => lower.startsWith(h));
        if (isNextHeader) break;

        buffer.writeln(line);
      }
    }

    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _assetImagePath(PricelistItem item) {
    if (item.imageFile.trim().isNotEmpty) {
      return 'assets/master_data/medicine_images/${item.imageFile.trim().toLowerCase()}';
    }

    final generated = _slugify(
      '${item.brand} ${item.formulation} ${item.packing}',
    );
    if (generated.isEmpty) return '';
    return 'assets/master_data/medicine_images/$generated.png';
  }

  String _formatMoney(double value) {
    return value.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
    );
  }

  Widget _buildSlide(PricelistItem item) {
    final details = _getCachedDetails(item);

    final contents = _sectionText(['contents'], details);
    final indication = _sectionText(
      ['indications/uses', 'indication', 'indications'],
      details,
    );
    final dosage = _sectionText(
      ['dosage/direction for use', 'dosage/direction', 'dosage', 'dose'],
      details,
    );
    final contraindications = _sectionText(
      ['contraindications', 'contraindication'],
      details,
    );
    final precautions = _sectionText(
      ['special precautions', 'special precaution'],
      details,
    );
    final storage = _sectionText(['storage'], details);
    final mimsClass = _sectionText(['mims class', 'mims'], details);
    final atc = _sectionText(['atc classification', 'atc'], details);

    final size = MediaQuery.of(context).size;
    final isTabletLike = size.width >= 900;
    final assetPath = _assetImagePath(item);

    return GestureDetector(
      onTap: () {
        setState(() {
          _showOverlay = !_showOverlay;
        });
      },
      child: Container(
        color: const Color(0xFF08111F),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isTabletLike ? 28 : 14,
              vertical: 14,
            ),
            child: isTabletLike
                ? Row(
              children: [
                Expanded(
                  flex: 11,
                  child: _PresentationImagePanel(
                    assetImagePath: assetPath,
                    brand: item.brand,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 9,
                  child: _PresentationInfoPanel(
                    brand: item.brand,
                    generic: item.generic,
                    formulation: item.formulation,
                    packing: item.packing,
                    uom: item.uom,
                    category: item.category,
                    price: item.price,
                    formattedPrice: _formatMoney(item.price),
                    contents: contents,
                    indication: indication,
                    dosage: dosage,
                    contraindications: contraindications,
                    precautions: precautions,
                    storage: storage,
                    mimsClass: mimsClass,
                    atc: atc,
                  ),
                ),
              ],
            )
                : Column(
              children: [
                Expanded(
                  flex: 6,
                  child: _PresentationImagePanel(
                    assetImagePath: assetPath,
                    brand: item.brand,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  flex: 10,
                  child: SingleChildScrollView(
                    child: _PresentationInfoPanel(
                      brand: item.brand,
                      generic: item.generic,
                      formulation: item.formulation,
                      packing: item.packing,
                      uom: item.uom,
                      category: item.category,
                      price: item.price,
                      formattedPrice: _formatMoney(item.price),
                      contents: contents,
                      indication: indication,
                      dosage: dosage,
                      contraindications: contraindications,
                      precautions: precautions,
                      storage: storage,
                      mimsClass: mimsClass,
                      atc: atc,
                      compact: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_currentIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF08111F),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
              _preloadAround(index);
            },
            itemBuilder: (context, index) {
              return _buildSlide(widget.items[index]);
            },
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: _showOverlay ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_showOverlay,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _GlassButton(
                            icon: Icons.arrow_back,
                            onTap: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.28),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.brand,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_currentIndex + 1} of ${widget.items.length}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.28),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Text(
                            'Swipe',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _PresentationImagePanel extends StatelessWidget {
  final String assetImagePath;
  final String brand;

  const _PresentationImagePanel({
    required this.assetImagePath,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: assetImagePath.trim().isNotEmpty
            ? InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Container(
            color: Colors.white,
            alignment: Alignment.center,
            child: Image.asset(
              assetImagePath,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) {
                return Container(
                  color: Colors.white.withOpacity(0.04),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.medication_outlined,
                        size: 96,
                        color: Colors.white54,
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          brand,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        )
            : Container(
          color: Colors.white.withOpacity(0.04),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.medication_outlined,
                size: 96,
                color: Colors.white54,
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  brand,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
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

class _PresentationInfoPanel extends StatelessWidget {
  final String brand;
  final String generic;
  final String formulation;
  final String packing;
  final String uom;
  final String category;
  final double price;
  final String formattedPrice;
  final String contents;
  final String indication;
  final String dosage;
  final String contraindications;
  final String precautions;
  final String storage;
  final String mimsClass;
  final String atc;
  final bool compact;

  const _PresentationInfoPanel({
    required this.brand,
    required this.generic,
    required this.formulation,
    required this.packing,
    required this.uom,
    required this.category,
    required this.price,
    required this.formattedPrice,
    required this.contents,
    required this.indication,
    required this.dosage,
    required this.contraindications,
    required this.precautions,
    required this.storage,
    required this.mimsClass,
    required this.atc,
    this.compact = false,
  });

  Widget _chip(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 12 : 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _section(String title, String body) {
    if (body.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: Colors.white70,
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 15 : 18,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white24),
      ),
      padding: EdgeInsets.all(compact ? 14 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            brand,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 22 : 30,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          if (generic.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              generic,
              style: TextStyle(
                color: Colors.white70,
                fontSize: compact ? 15 : 18,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            children: [
              _chip('Formulation', formulation),
              _chip('Pack', packing),
              _chip('UOM', uom),
              _chip('Category', category),
              _chip('Price', '₱$formattedPrice${uom.isNotEmpty ? ' / $uom' : ''}'),
            ],
          ),
          _section('Contents', contents),
          _section('Indication', indication),
          _section('Dosage', dosage),
          _section('Contraindications', contraindications),
          _section('Precautions', precautions),
          _section('Storage', storage),
          _section('MIMS Class', mimsClass),
          _section('ATC', atc),
        ],
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.28),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(
            icon,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _DetailingAssetImagePreviewPage extends StatelessWidget {
  final String assetPath;
  final String title;
  final String subtitle;

  const _DetailingAssetImagePreviewPage({
    required this.assetPath,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Image.asset(assetPath),
              ),
            ),
            if (subtitle.trim().isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kGold),
                  ),
                  child: Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}