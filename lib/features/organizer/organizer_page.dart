import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/license_manager.dart';
import '../pricelist/pricelist_import_page.dart';
import '../pricelist/pricelist_upload_page.dart';
import 'customer_detail_page.dart';
import 'name_input_page.dart';
import 'qr_scanner_page.dart';

class OrganizerPage extends StatefulWidget {
  const OrganizerPage({super.key});

  @override
  State<OrganizerPage> createState() => _OrganizerPageState();
}

class _OrganizerPageState extends State<OrganizerPage> {
  static const List<String> priorityFolders = [
    'Raw Images 2026',
    'By Product Lines',
    'By Pharmacological Category',
    'By Specialty',
  ];

  static const List<String> customerSections = [
    'medicine',
    'videos',
    'ids',
    'receipts',
    'invoices',
    'orders',
    'contracts',
    'accounts',
    'other',
    'rgs',
    'dlf',
    'srb',
    'casd',
  ];

  static const String _paymongoUrl =
      'https://pm.link/org-csvj8V43WCuWzDfBHQyQgkMd/UAFxTqE';

  final TextEditingController _searchController = TextEditingController();

  Directory? _customersRootDir;
  String? _sourceRootPath;

  bool _loading = true;
  bool _refreshing = false;
  bool _creatingCustomer = false;

  bool _checkingAccess = true;
  bool _canAccess = false;
  bool _startingPayment = false;

  int _trialDaysLeft = 0;
  int _premiumDaysLeft = 0;
  String _deviceCode = '...';

  List<Directory> _customerDirs = [];
  Map<String, int> _customerFileCounts = {};

  @override
  void initState() {
    super.initState();
    _checkAccess();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkAccess({bool showActivatedMessage = false}) async {
    final allowed = await LicenseManager.canUseOrganizer();
    final trialDaysLeft = await LicenseManager.getTrialDaysLeft();
    final premiumDaysLeft = await LicenseManager.getPremiumDaysLeft();
    final deviceCode = await LicenseManager.getDeviceCode();

    if (!mounted) return;

    setState(() {
      _canAccess = allowed;
      _checkingAccess = false;
      _trialDaysLeft = trialDaysLeft;
      _premiumDaysLeft = premiumDaysLeft;
      _deviceCode = deviceCode;
    });

    if (allowed) {
      if (showActivatedMessage) {
        _showSnack('Premium activated!');
      }
      await _initOrganizer();
    }
  }

  Future<void> _openPayment() async {
    if (_startingPayment) return;

    try {
      setState(() => _startingPayment = true);

      final opened = await launchUrl(
        Uri.parse(_paymongoUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        _showSnack('Could not open payment page.');
      }
    } catch (e) {
      _showSnack('Payment error: $e');
    } finally {
      if (mounted) {
        setState(() => _startingPayment = false);
      }
    }
  }

  Future<void> _initOrganizer() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final customersRoot = Directory(p.join(docsDir.path, 'customers'));

      if (!await customersRoot.exists()) {
        await customersRoot.create(recursive: true);
      }

      final prefs = await SharedPreferences.getInstance();
      final sourceRootPath = prefs.getString('priority_source_root');

      _customersRootDir = customersRoot;
      _sourceRootPath = sourceRootPath;

      await _loadCustomerFolders(showLoader: false);
    } catch (e) {
      _showSnack('Failed to initialize organizer: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadCustomerFolders({bool showLoader = false}) async {
    if (_customersRootDir == null) return;

    if (mounted) {
      setState(() {
        if (showLoader) _loading = true;
        _refreshing = true;
      });
    }

    try {
      final dirs = _customersRootDir!
          .listSync()
          .whereType<Directory>()
          .toList()
        ..sort(
              (a, b) => p
              .basename(a.path)
              .toLowerCase()
              .compareTo(p.basename(b.path).toLowerCase()),
        );

      final counts = <String, int>{};

      for (final dir in dirs) {
        counts[dir.path] = await _countAllFilesRecursively(dir);
      }

      if (!mounted) return;
      setState(() {
        _customerDirs = dirs;
        _customerFileCounts = counts;
      });
    } catch (e) {
      _showSnack('Failed to load customer folders: $e');
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          if (showLoader) _loading = false;
        });
      }
    }
  }

  List<Directory> get _filteredCustomerDirs {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _customerDirs;

    return _customerDirs.where((dir) {
      final name = p.basename(dir.path).toLowerCase();
      return name.contains(query);
    }).toList();
  }

  Future<void> _pickSourceRootFolder() async {
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select root folder containing the priority folders',
      );

      if (selected == null || selected.trim().isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('priority_source_root', selected);

      if (!mounted) return;
      setState(() {
        _sourceRootPath = selected;
      });

      _showSnack('Priority source folder saved.');
    } catch (e) {
      _showSnack('Failed to select source folder: $e');
    }
  }

  bool _customerNameExists(String folderName) {
    final target = folderName.trim().toLowerCase();
    return _customerDirs.any(
          (dir) => p.basename(dir.path).trim().toLowerCase() == target,
    );
  }

  String _sanitizeFolderName(String value) {
    var cleaned = value.trim();
    cleaned = cleaned.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.trim();
  }

  Future<void> _createCustomerFolder() async {
    if (_customersRootDir == null || _creatingCustomer) return;

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => NameInputPage(
          title: 'Add Customer',
          hintText: 'Enter customer name',
          actionLabel: 'Create',
          validator: (value) {
            final folderName = _sanitizeFolderName(value);

            if (value.trim().isEmpty) return 'Customer name is required';
            if (folderName.isEmpty) return 'Customer name is invalid';
            if (_customerNameExists(folderName)) return 'Customer already exists';

            return null;
          },
        ),
      ),
    );

    if (result == null) return;

    final folderName = _sanitizeFolderName(result);
    if (folderName.isEmpty) {
      _showSnack('Customer name is required.');
      return;
    }

    if (_customerNameExists(folderName)) {
      _showSnack('Customer already exists.');
      return;
    }

    final customerDir = Directory(p.join(_customersRootDir!.path, folderName));

    try {
      if (mounted) {
        setState(() => _creatingCustomer = true);
      }

      if (!await customerDir.exists()) {
        await customerDir.create(recursive: true);
        await _createCustomerSubfolders(customerDir);
      }

      await _loadCustomerFolders();
      _showSnack('Customer folder created.');
    } catch (e) {
      _showSnack('Failed to create customer folder: $e');
    } finally {
      if (mounted) {
        setState(() => _creatingCustomer = false);
      }
    }
  }

  Future<void> _createCustomerSubfolders(Directory customerDir) async {
    for (final section in customerSections) {
      final dir = Directory(p.join(customerDir.path, section));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    final customRoot = Directory(p.join(customerDir.path, 'custom'));
    if (!await customRoot.exists()) {
      await customRoot.create(recursive: true);
    }
  }

  Future<void> _renameCustomerFolder(Directory dir) async {
    final oldName = p.basename(dir.path);

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => NameInputPage(
          title: 'Rename Customer',
          hintText: 'New customer name',
          actionLabel: 'Save',
          initialValue: oldName,
          validator: (value) {
            final newName = _sanitizeFolderName(value);

            if (value.trim().isEmpty) return 'Customer name is required';
            if (newName.isEmpty) return 'Customer name is invalid';

            final duplicate = _customerDirs.any(
                  (d) =>
              d.path != dir.path &&
                  p.basename(d.path).toLowerCase() == newName.toLowerCase(),
            );

            if (duplicate) return 'Customer already exists';
            return null;
          },
        ),
      ),
    );

    if (result == null) return;

    final newName = _sanitizeFolderName(result);
    if (newName.isEmpty || newName == oldName) return;

    final newDir = Directory(p.join(dir.parent.path, newName));

    if (await newDir.exists()) {
      _showSnack('A folder with that name already exists.');
      return;
    }

    try {
      await dir.rename(newDir.path);
      await _loadCustomerFolders();
      _showSnack('Folder renamed.');
    } catch (e) {
      _showSnack('Failed to rename folder: $e');
    }
  }

  Future<bool> _folderHasFilesRecursively(Directory dir) async {
    try {
      final entities = dir.listSync(recursive: true, followLinks: false);
      return entities.any((e) => e is File);
    } catch (_) {
      return true;
    }
  }

  Future<void> _deleteCustomerFolder(Directory dir) async {
    final folderName = p.basename(dir.path);
    final hasFiles = await _folderHasFilesRecursively(dir);

    if (hasFiles) {
      _showSnack('Cannot delete. "$folderName" still contains files.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Empty Customer Folder'),
          content: Text('Delete "$folderName"? It has no files inside.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await dir.delete(recursive: true);
      await _loadCustomerFolders();
      _showSnack('Empty folder deleted.');
    } catch (e) {
      _showSnack('Failed to delete folder: $e');
    }
  }

  Future<int> _countAllFilesRecursively(Directory dir) async {
    try {
      return dir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .length;
    } catch (_) {
      return 0;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildCustomerRow(Directory dir) {
    final name = p.basename(dir.path);
    final count = _customerFileCounts[dir.path] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD7DFEA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFFDCEBFF),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.folder,
            color: Color(0xFF2F6FD6),
            size: 24,
          ),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$count file${count == 1 ? '' : 's'}',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
            ),
          ),
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CustomerDetailPage(
                customerDir: dir,
                sourceRootPath: _sourceRootPath,
                priorityFolders: priorityFolders,
                onRequestSetSourceRoot: _pickSourceRootFolder,
              ),
            ),
          );
          await _loadCustomerFolders();
        },
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'rename') {
              await _renameCustomerFolder(dir);
            } else if (value == 'delete') {
              await _deleteCustomerFolder(dir);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'rename',
              child: Text('Rename'),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text('Delete Empty Folder'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedScreen() {
    final trialMessage = _trialDaysLeft > 0
        ? 'Your trial ends in $_trialDaysLeft day(s).\nSubscribe early to avoid interruption.'
        : 'Your trial has ended.\nSubscribe to continue using Organizer.';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Organizer',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () async {
              setState(() => _checkingAccess = true);
              await _checkAccess(showActivatedMessage: true);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFD7DFEA)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCEBFF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    size: 38,
                    color: Color(0xFF2F6FD6),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Organizer Premium',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  trialMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFD8E6FA)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Subscription',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '₱249 / month',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2F6FD6),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Device Code',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _deviceCode,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Trial days left: $_trialDaysLeft',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Premium days left: $_premiumDaysLeft',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _startingPayment ? null : _openPayment,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F6FD6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _startingPayment
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.payment),
                    label: Text(
                      _startingPayment
                          ? 'Opening payment...'
                          : 'Subscribe via GCash',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      setState(() => _checkingAccess = true);
                      await _checkAccess(showActivatedMessage: true);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('I already paid'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrialWarningBar() {
    if (!(_trialDaysLeft > 0 && _trialDaysLeft <= 3 && _premiumDaysLeft <= 0)) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Trial ends in $_trialDaysLeft day(s)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: _startingPayment ? null : _openPayment,
            child: const Text('Subscribe'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAccess) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_canAccess) {
      return _buildLockedScreen();
    }

    final folders = _filteredCustomerDirs;
    final hasSearch = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Organizer',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Upload Pricelist',
            onPressed: _loading || _refreshing
                ? null
                : () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PricelistUploadPage(),
                ),
              );
              await _loadCustomerFolders();
            },
            icon: const Icon(Icons.upload_file),
          ),
          IconButton(
            tooltip: 'Import Pricelist',
            onPressed: _loading || _refreshing
                ? null
                : () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PricelistImportPage(),
                ),
              );
              await _loadCustomerFolders();
            },
            icon: const Icon(Icons.list_alt),
          ),
          IconButton(
            tooltip: 'Scan QR',
            onPressed: _loading || _refreshing
                ? null
                : () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OrganizerQrScannerPage(),
                ),
              );
            },
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: 'Add Customer',
            onPressed: _loading || _refreshing || _creatingCustomer
                ? null
                : _createCustomerFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshing ? null : () => _loadCustomerFolders(),
            icon: _refreshing
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _refreshing || _creatingCustomer
            ? null
            : _createCustomerFolder,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(
          _creatingCustomer ? 'Creating...' : 'Add Customer',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(
        child: CircularProgressIndicator(),
      )
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
        child: Column(
          children: [
            _buildTrialWarningBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search customer folder...',
                  suffixIcon: hasSearch
                      ? IconButton(
                    onPressed: () => _searchController.clear(),
                    icon: const Icon(Icons.close),
                  )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFFD7DFEA),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFFD7DFEA),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF2F6FD6),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: folders.isEmpty
                  ? Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
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
                        Icons.folder_copy_outlined,
                        size: 58,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        hasSearch
                            ? 'No folders match your search'
                            : 'No customer folders yet',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasSearch
                            ? 'Try another customer name.'
                            : 'Tap Add Customer to create a customer folder.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
                  : RefreshIndicator(
                onRefresh: () => _loadCustomerFolders(),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    return _buildCustomerRow(folders[index]);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}