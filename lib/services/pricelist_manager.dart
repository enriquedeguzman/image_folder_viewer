import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PricelistItem {
  final String category;
  final String brand;
  final String generic;
  final String formulation;
  final String packing;
  final String uom;
  final double price;
  final int? sourcePage;
  final String detailsFile;
  final String imageFile;

  const PricelistItem({
    required this.category,
    required this.brand,
    required this.generic,
    required this.formulation,
    required this.packing,
    this.uom = '',
    required this.price,
    this.sourcePage,
    required this.detailsFile,
    required this.imageFile,
  });

  factory PricelistItem.fromJson(Map<String, dynamic> json) {
    return PricelistItem(
      category: (json['category'] ?? '').toString().trim(),
      brand: (json['brand'] ?? '').toString().trim(),
      generic: (json['generic'] ?? '').toString().trim(),
      formulation: (json['formulation'] ?? '').toString().trim(),
      packing: (json['packing'] ?? '').toString().trim(),
      uom: (json['uom'] ?? '').toString().trim().toLowerCase(),
      price: (json['price'] is num)
          ? (json['price'] as num).toDouble()
          : double.tryParse(
        '${json['price'] ?? ''}'.replaceAll(',', '').trim(),
      ) ??
          0,
      sourcePage: json['sourcePage'] is int
          ? json['sourcePage'] as int
          : int.tryParse('${json['sourcePage'] ?? ''}'.trim()),
      detailsFile: PricelistManager.normalizeDetailsFile(
        (json['detailsFile'] ?? '').toString(),
      ),
      imageFile: PricelistManager.normalizeImageFile(
        (json['imageFile'] ?? '').toString(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category.trim(),
      'brand': brand.trim(),
      'generic': generic.trim(),
      'formulation': formulation.trim(),
      'packing': packing.trim(),
      'uom': uom.trim().toLowerCase(),
      'price': price,
      'sourcePage': sourcePage,
      'detailsFile': PricelistManager.normalizeDetailsFile(detailsFile),
      'imageFile': PricelistManager.normalizeImageFile(imageFile),
    };
  }

  String get packWithUom {
    final p = packing.trim();
    final u = uom.trim();
    if (p.isEmpty && u.isEmpty) return '';
    if (p.isEmpty) return u;
    if (u.isEmpty) return p;
    return '$p $u';
  }

  String get displayName {
    final parts = <String>[
      if (brand.trim().isNotEmpty) brand.trim(),
      if (formulation.trim().isNotEmpty) formulation.trim(),
      if (packWithUom.isNotEmpty) packWithUom,
    ];
    return parts.join(' ');
  }
}

class PricelistManager {
  static const String masterFolderName = 'master_data';
  static const String pricelistPdfName = 'pricelist.pdf';
  static const String pricelistJsonName = 'pricelist.json';
  static const String pricelistCsvName = 'pricelist.csv';
  static const String medicineImagesFolderName = 'medicine_images';
  static const String medicineItemsFileName = 'medicine_items.json';

  static const String _bundledCsvAssetPath =
      'assets/master_data/pricelist.csv';
  static const String _bundledVersionAssetPath =
      'assets/master_data/pricelist_version.txt';
  static const String _bundledVersionPrefsKey = 'bundled_pricelist_version';

  static const List<String> supportedMedicineImageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
  ];

  static const Map<String, String> uomAliases = {
    'box': 'box',
    'bx': 'box',
    'bxs': 'box',
    'bot': 'bot',
    'bottle': 'bot',
    'bottles': 'bot',
    'amp': 'amp',
    'ampule': 'amp',
    'ampules': 'amp',
    'ampoule': 'amp',
    'ampoules': 'amp',
    'vial': 'vial',
    'vials': 'vial',
    'tab': 'tab',
    'tabs': 'tab',
    'tablet': 'tab',
    'tablets': 'tab',
    'cap': 'cap',
    'caps': 'cap',
    'capsule': 'cap',
    'capsules': 'cap',
    'sachet': 'sachet',
    'sachets': 'sachet',
    'tube': 'tube',
    'tubes': 'tube',
    'pc': 'pc',
    'pcs': 'pc',
    'piece': 'pc',
    'pieces': 'pc',
  };

  static Future<Directory> getApplicationRootDirectory() async {
    return getApplicationDocumentsDirectory();
  }

  static Future<Directory> getMasterDataDirectory() async {
    final docs = await getApplicationRootDirectory();
    final dir = Directory(p.join(docs.path, masterFolderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<Directory> getMedicineImagesDirectory() async {
    final masterDir = await getMasterDataDirectory();
    final imagesDir = Directory(
      p.join(masterDir.path, medicineImagesFolderName),
    );
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  static Future<String> resolveMedicineImagePath(String imageFile) async {
    final imagesDir = await getMedicineImagesDirectory();
    return p.join(imagesDir.path, normalizeImageFile(imageFile));
  }

  static Future<File> resolveMedicineImageFile(String imageFile) async {
    final fullPath = await resolveMedicineImagePath(imageFile);
    return File(fullPath);
  }

  static Future<bool> medicineImageExists(String imageFile) async {
    final file = await resolveMedicineImageFile(imageFile);
    return file.exists();
  }

  static Future<File> getPricelistPdfFile() async {
    final dir = await getMasterDataDirectory();
    return File(p.join(dir.path, pricelistPdfName));
  }

  static Future<File> getPricelistJsonFile() async {
    final dir = await getMasterDataDirectory();
    return File(p.join(dir.path, pricelistJsonName));
  }

  static Future<File> getPricelistCsvFile() async {
    final dir = await getMasterDataDirectory();
    return File(p.join(dir.path, pricelistCsvName));
  }

  static Future<bool> hasPricelistJson() async {
    final file = await getPricelistJsonFile();
    return file.exists();
  }

  static Future<bool> hasPricelistPdf() async {
    final file = await getPricelistPdfFile();
    return file.exists();
  }

  static Future<bool> hasPricelistCsv() async {
    final file = await getPricelistCsvFile();
    return file.exists();
  }

  static Future<void> ensureBundledPricelistImported() async {
    final prefs = await SharedPreferences.getInstance();

    final bundledVersion =
    (await rootBundle.loadString(_bundledVersionAssetPath)).trim();
    final savedVersion =
    (prefs.getString(_bundledVersionPrefsKey) ?? '').trim();

    final jsonFile = await getPricelistJsonFile();
    final csvFile = await getPricelistCsvFile();

    final hasJson = await jsonFile.exists();
    final hasCsv = await csvFile.exists();

    bool jsonHasData = false;
    if (hasJson) {
      try {
        final content = await jsonFile.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is List && decoded.isNotEmpty) {
            jsonHasData = true;
          }
        }
      } catch (_) {
        jsonHasData = false;
      }
    }

    final shouldImport =
        bundledVersion.isNotEmpty && bundledVersion != savedVersion;
    final shouldForceRebuild = !jsonHasData || !hasCsv;

    if (!shouldImport && !shouldForceRebuild) {
      return;
    }

    final csvContent = await rootBundle.loadString(_bundledCsvAssetPath);
    await csvFile.writeAsString(csvContent, flush: true);

    final items = await importPricelistFromSavedCsv();
    stdout.writeln('Bundled pricelist imported: ${items.length} items');

    if (bundledVersion.isNotEmpty) {
      await prefs.setString(_bundledVersionPrefsKey, bundledVersion);
    }
  }

  static Future<void> savePricelistPdfFromPath(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Selected PDF file does not exist.');
    }

    final targetFile = await getPricelistPdfFile();
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await sourceFile.copy(targetFile.path);
  }

  static Future<void> savePricelistCsvFromPath(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Selected CSV file does not exist.');
    }

    final targetFile = await getPricelistCsvFile();
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await sourceFile.copy(targetFile.path);
  }

  static Future<void> savePricelistItems(List<PricelistItem> items) async {
    final normalizedItems = items
        .map(
          (e) => PricelistItem(
        category: e.category.trim(),
        brand: e.brand.trim(),
        generic: e.generic.trim(),
        formulation: e.formulation.trim(),
        packing: e.packing.trim(),
        uom: normalizeUom(e.uom),
        price: e.price,
        sourcePage: e.sourcePage,
        detailsFile: normalizeDetailsFile(e.detailsFile),
        imageFile: normalizeImageFile(e.imageFile),
      ),
    )
        .toList()
      ..sort(_comparePricelistItems);

    final file = await getPricelistJsonFile();
    final jsonList = normalizedItems.map((e) => e.toJson()).toList();

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(jsonList),
      flush: true,
    );
  }

  static Future<List<PricelistItem>> loadPricelistItems() async {
    final jsonFile = await getPricelistJsonFile();

    if (await jsonFile.exists()) {
      final content = await jsonFile.readAsString();
      if (content.trim().isNotEmpty) {
        final decoded = jsonDecode(content);
        if (decoded is List) {
          final items = decoded
              .whereType<Map>()
              .map((e) => PricelistItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
            ..sort(_comparePricelistItems);

          if (items.isNotEmpty) {
            return items;
          }
        }
      }
    }

    final csvFile = await getPricelistCsvFile();
    if (await csvFile.exists()) {
      final rebuilt = await importPricelistFromCsvFile(
        csvFile,
        saveCsvCopy: false,
      );
      return rebuilt;
    }

    return [];
  }

  static Future<List<PricelistItem>> importPricelistFromCsvPath(
      String sourcePath,
      ) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Selected CSV file does not exist.');
    }

    await savePricelistCsvFromPath(sourcePath);
    return importPricelistFromCsvFile(
      await getPricelistCsvFile(),
      saveCsvCopy: false,
    );
  }

  static Future<List<PricelistItem>> importPricelistFromSavedCsv() async {
    final file = await getPricelistCsvFile();
    if (!await file.exists()) {
      throw Exception('No saved CSV file found.');
    }
    return importPricelistFromCsvFile(file, saveCsvCopy: false);
  }

  static Future<List<PricelistItem>> importPricelistFromCsvFile(
      File file, {
        bool saveCsvCopy = true,
      }) async {
    if (!await file.exists()) {
      throw Exception('CSV file not found.');
    }

    if (saveCsvCopy) {
      await savePricelistCsvFromPath(file.path);
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      throw Exception('CSV file is empty.');
    }

    final rows = _parseCsv(raw);
    if (rows.isEmpty) {
      throw Exception('No rows found in CSV.');
    }

    final headers = rows.first.map(_normalizeHeader).toList();

    int indexOfAny(List<String> names) {
      for (final name in names) {
        final idx = headers.indexOf(_normalizeHeader(name));
        if (idx >= 0) return idx;
      }
      return -1;
    }

    final categoryIndex = indexOfAny(['category']);
    final brandIndex = indexOfAny(['brand']);
    final genericIndex = indexOfAny(['generic']);
    final formulationIndex = indexOfAny(['formulation']);
    final packingIndex = indexOfAny(['packing']);
    final uomIndex = indexOfAny([
      'uom',
      'unit',
      'unitofmeasure',
      'unit_of_measure',
    ]);
    final priceIndex = indexOfAny(['price']);
    final sourcePageIndex = indexOfAny(['sourcePage', 'source_page', 'page']);
    final detailsFileIndex = indexOfAny([
      'detailsFile',
      'details_file',
      'details',
      'txtFile',
      'txt_file',
    ]);
    final imageFileIndex = indexOfAny([
      'imageFile',
      'image_file',
      'image',
      'imgFile',
      'img_file',
    ]);

    if (brandIndex < 0 || priceIndex < 0) {
      throw Exception('CSV must contain at least brand and price columns.');
    }

    final items = <PricelistItem>[];

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((e) => e.trim().isEmpty)) continue;

      String valueAt(int index) {
        if (index < 0 || index >= row.length) return '';
        return row[index].trim();
      }

      final brand = valueAt(brandIndex);
      if (brand.isEmpty) continue;

      final formulation = valueAt(formulationIndex);
      final packing = valueAt(packingIndex);
      final uom = normalizeUom(valueAt(uomIndex));

      var imageFile = normalizeImageFile(valueAt(imageFileIndex));
      if (imageFile.isEmpty) {
        imageFile = buildDefaultMedicineImageFileName(
          brand: brand,
          formulation: formulation,
          packing: packing,
          uom: uom,
          extension: '.jpg',
        );
      }

      final parsedPrice = _parsePrice(valueAt(priceIndex));

      items.add(
        PricelistItem(
          category: valueAt(categoryIndex),
          brand: brand,
          generic: valueAt(genericIndex),
          formulation: formulation,
          packing: packing,
          uom: uom,
          price: parsedPrice,
          sourcePage: _parseInt(valueAt(sourcePageIndex)),
          detailsFile: normalizeDetailsFile(valueAt(detailsFileIndex)),
          imageFile: imageFile,
        ),
      );
    }

    items.sort(_comparePricelistItems);
    await savePricelistItems(items);
    return items;
  }

  static int _comparePricelistItems(PricelistItem a, PricelistItem b) {
    final brandCompare = a.brand.toLowerCase().compareTo(b.brand.toLowerCase());
    if (brandCompare != 0) return brandCompare;

    final formulationCompare = a.formulation
        .toLowerCase()
        .compareTo(b.formulation.toLowerCase());
    if (formulationCompare != 0) return formulationCompare;

    final packingCompare =
    a.packing.toLowerCase().compareTo(b.packing.toLowerCase());
    if (packingCompare != 0) return packingCompare;

    return a.uom.toLowerCase().compareTo(b.uom.toLowerCase());
  }

  static String _normalizeFileNameOnly(String value) {
    var cleaned = value.trim().replaceAll('\\', '/');
    cleaned = cleaned.split('/').last.trim();
    return cleaned;
  }

  static String normalizeImageFile(String value) {
    return _normalizeFileNameOnly(value).toLowerCase();
  }

  static String normalizeDetailsFile(String value) {
    return _normalizeFileNameOnly(value).toLowerCase();
  }

  static String normalizeUom(String value) {
    final key = value.trim().toLowerCase();
    if (key.isEmpty) return '';
    return uomAliases[key] ?? key;
  }

  static String normalizeImageBaseName(String value) {
    final cleaned = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\.(jpg|jpeg|png|webp|bmp)$'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned;
  }

  static String _slugifyFilePart(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  static String buildMedicineImageBaseName({
    required String brand,
    required String formulation,
    required String packing,
    required String uom,
  }) {
    final brandPart = _slugifyFilePart(brand);
    final formPart = _slugifyFilePart(formulation);
    final packPart = _slugifyFilePart(packing);
    final uomPart = _slugifyFilePart(normalizeUom(uom));

    final parts = <String>[
      if (brandPart.isNotEmpty) brandPart,
      if (formPart.isNotEmpty) formPart,
      if (packPart.isNotEmpty) packPart,
      if (uomPart.isNotEmpty) uomPart,
    ];

    return parts.join('_');
  }

  static String buildBrandOnlyImageBaseName(String brand) {
    return _slugifyFilePart(brand);
  }

  static String buildDefaultMedicineImageFileName({
    required String brand,
    required String formulation,
    required String packing,
    required String uom,
    String extension = '.jpg',
  }) {
    final ext = supportedMedicineImageExtensions.contains(
      extension.toLowerCase(),
    )
        ? extension.toLowerCase()
        : '.jpg';

    final base = buildMedicineImageBaseName(
      brand: brand,
      formulation: formulation,
      packing: packing,
      uom: uom,
    );

    if (base.isEmpty) return '';
    return '$base$ext';
  }

  static List<String> buildMedicineImageCandidateNames({
    required String imageFile,
    required String brand,
    required String formulation,
    required String packing,
    required String uom,
  }) {
    final results = <String>[];
    final seen = <String>{};

    void addName(String fileName) {
      final normalized = normalizeImageFile(fileName);
      if (normalized.isEmpty) return;
      if (seen.add(normalized)) {
        results.add(normalized);
      }
    }

    void addBaseWithExtensions(String base) {
      final normalizedBase = normalizeImageBaseName(base);
      if (normalizedBase.isNotEmpty) {
        for (final ext in supportedMedicineImageExtensions) {
          addName('$normalizedBase$ext');
        }
      }
    }

    final exact = normalizeImageFile(imageFile);
    if (exact.isNotEmpty) {
      addName(exact);

      final ext = p.extension(exact).toLowerCase();
      if (supportedMedicineImageExtensions.contains(ext)) {
        addBaseWithExtensions(p.basenameWithoutExtension(exact));
      } else {
        addBaseWithExtensions(exact);
      }
    }

    final fullBase = buildMedicineImageBaseName(
      brand: brand,
      formulation: formulation,
      packing: packing,
      uom: uom,
    );
    addBaseWithExtensions(fullBase);

    final oldBase = buildMedicineImageBaseName(
      brand: brand,
      formulation: formulation,
      packing: packing,
      uom: '',
    );
    addBaseWithExtensions(oldBase);

    final brandBase = buildBrandOnlyImageBaseName(brand);
    addBaseWithExtensions(brandBase);

    return results;
  }

  static Future<File?> findBestMedicineImageFile({
    required String imageFile,
    required String brand,
    required String formulation,
    required String packing,
    String uom = '',
  }) async {
    final dir = await getMedicineImagesDirectory();
    if (!await dir.exists()) return null;

    final candidates = buildMedicineImageCandidateNames(
      imageFile: imageFile,
      brand: brand,
      formulation: formulation,
      packing: packing,
      uom: uom,
    );

    for (final candidate in candidates) {
      final file = File(p.join(dir.path, candidate));
      if (await file.exists()) return file;
    }

    final brandBase = buildBrandOnlyImageBaseName(brand);
    if (brandBase.isNotEmpty) {
      try {
        final entities = dir.listSync(followLinks: false);
        for (final entity in entities) {
          if (entity is! File) continue;
          final fileName = p.basename(entity.path).toLowerCase();
          final baseName = normalizeImageBaseName(fileName);
          if (baseName == brandBase || baseName.startsWith('${brandBase}_')) {
            return entity;
          }
        }
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  static List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    final currentRow = <String>[];
    final currentCell = StringBuffer();

    bool inQuotes = false;
    int i = 0;

    while (i < input.length) {
      final char = input[i];

      if (char == '"') {
        if (inQuotes && i + 1 < input.length && input[i + 1] == '"') {
          currentCell.write('"');
          i += 2;
          continue;
        }
        inQuotes = !inQuotes;
        i++;
        continue;
      }

      if (char == ',' && !inQuotes) {
        currentRow.add(currentCell.toString());
        currentCell.clear();
        i++;
        continue;
      }

      if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') {
          i++;
        }
        currentRow.add(currentCell.toString());
        currentCell.clear();

        if (currentRow.isNotEmpty) {
          rows.add(List<String>.from(currentRow));
          currentRow.clear();
        }

        i++;
        continue;
      }

      currentCell.write(char);
      i++;
    }

    currentRow.add(currentCell.toString());
    if (currentRow.isNotEmpty &&
        !(currentRow.length == 1 && currentRow.first.trim().isEmpty)) {
      rows.add(List<String>.from(currentRow));
    }

    return rows;
  }

  static String _normalizeHeader(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('.', '');
  }

  static double _parsePrice(String value) {
    final cleaned = value
        .replaceAll('₱', '')
        .replaceAll('PHP', '')
        .replaceAll('php', '')
        .replaceAll(',', '')
        .trim();
    return double.tryParse(cleaned) ?? 0;
  }

  static int? _parseInt(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    return int.tryParse(cleaned);
  }
}