import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'customer_section_page.dart';
import 'name_input_page.dart';

class CustomerDetailPage extends StatefulWidget {
  final Directory customerDir;
  final String? sourceRootPath;
  final List<String> priorityFolders;
  final Future<void> Function()? onRequestSetSourceRoot;

  const CustomerDetailPage({
    super.key,
    required this.customerDir,
    required this.sourceRootPath,
    required this.priorityFolders,
    this.onRequestSetSourceRoot,
  });

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  static const List<CustomerSectionInfo> sections = [
    CustomerSectionInfo(
      keyName: 'medicine',
      title: 'Medicine',
      icon: Icons.medication_outlined,
      color: Color(0xFFDCEBFF),
    ),
    CustomerSectionInfo(
      keyName: 'invoices',
      title: 'Sales Order',
      icon: Icons.picture_as_pdf_outlined,
      color: Color(0xFFF3E5F5),
    ),
    CustomerSectionInfo(
      keyName: 'screenshot',
      title: 'Screenshot',
      icon: Icons.photo_camera_back_outlined,
      color: Color(0xFFE8F5E9),
    ),
    CustomerSectionInfo(
      keyName: 'receipts',
      title: 'Receipts',
      icon: Icons.receipt_long_outlined,
      color: Color(0xFFFFF3E0),
    ),
    CustomerSectionInfo(
      keyName: 'accounts',
      title: 'Accounts',
      icon: Icons.account_balance_wallet_outlined,
      color: Color(0xFFFFEBEE),
    ),
    CustomerSectionInfo(
      keyName: 'videos',
      title: 'Videos',
      icon: Icons.video_library_outlined,
      color: Color(0xFFE3F2FD),
    ),
    CustomerSectionInfo(
      keyName: 'ids',
      title: 'IDs',
      icon: Icons.badge_outlined,
      color: Color(0xFFE8F5E9),
    ),
    CustomerSectionInfo(
      keyName: 'contracts',
      title: 'Contracts',
      icon: Icons.handshake_outlined,
      color: Color(0xFFE0F7FA),
    ),
    CustomerSectionInfo(
      keyName: 'other',
      title: 'Other',
      icon: Icons.folder_open_outlined,
      color: Color(0xFFF1F5F9),
    ),
    CustomerSectionInfo(
      keyName: 'rgs',
      title: 'RGS',
      icon: Icons.local_shipping_outlined,
      color: Color(0xFFE3F2FD),
    ),
    CustomerSectionInfo(
      keyName: 'dlf',
      title: 'DLF',
      icon: Icons.inventory_2_outlined,
      color: Color(0xFFFFF8E1),
    ),
    CustomerSectionInfo(
      keyName: 'srb',
      title: 'SRB',
      icon: Icons.assignment_outlined,
      color: Color(0xFFE8EAF6),
    ),
    CustomerSectionInfo(
      keyName: 'casd',
      title: 'CASD',
      icon: Icons.folder_special_outlined,
      color: Color(0xFFFCE4EC),
    ),
  ];

  final Map<String, int> _counts = {};
  bool _loading = true;
  bool _refreshing = false;
  bool _busyCustomFolderAction = false;

  List<Directory> _customDirs = [];
  Directory? _customRootDir;

  String get _customerName => p.basename(widget.customerDir.path);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCounts(initialLoad: true);
    });
  }

  Future<void> _ensureBaseFolders() async {
    for (final section in sections) {
      final dir = Directory(p.join(widget.customerDir.path, section.keyName));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    final screenshotDir = Directory(p.join(widget.customerDir.path, 'screenshot'));
    if (!await screenshotDir.exists()) {
      await screenshotDir.create(recursive: true);
    }

    final customRoot = Directory(p.join(widget.customerDir.path, 'custom'));
    if (!await customRoot.exists()) {
      await customRoot.create(recursive: true);
    }
    _customRootDir = customRoot;
  }

  Future<int> _countFilesRecursively(Directory dir) async {
    try {
      var count = 0;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _loadCounts({bool initialLoad = false}) async {
    if (!mounted) return;

    setState(() {
      _refreshing = true;
      if (initialLoad) {
        _loading = true;
      }
    });

    try {
      await _ensureBaseFolders();

      final nextCounts = <String, int>{};

      for (final section in sections) {
        final dir = Directory(p.join(widget.customerDir.path, section.keyName));
        nextCounts[section.keyName] = await _countFilesRecursively(dir);
      }

      final screenshotDir = Directory(p.join(widget.customerDir.path, 'screenshot'));
      nextCounts['screenshot'] = await _countFilesRecursively(screenshotDir);

      final customDirs = <Directory>[];
      if (_customRootDir != null && await _customRootDir!.exists()) {
        await for (final entity
        in _customRootDir!.list(recursive: false, followLinks: false)) {
          if (entity is Directory) {
            customDirs.add(entity);
          }
        }
      }

      customDirs.sort(
            (a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()),
      );

      for (final dir in customDirs) {
        nextCounts[dir.path] = await _countFilesRecursively(dir);
      }

      if (!mounted) return;

      setState(() {
        _counts
          ..clear()
          ..addAll(nextCounts);
        _customDirs = customDirs;
      });
    } catch (e) {
      _showSnack('Failed to load customer folders: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  String _sanitizeFolderName(String value) {
    var cleaned = value.trim();
    cleaned = cleaned.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.trim();
  }

  String _normalizeFolderName(String value) {
    return _sanitizeFolderName(value).trim().toLowerCase();
  }

  bool _folderNameExists(String name, {String? ignorePath}) {
    final normalized = _normalizeFolderName(name);
    if (normalized.isEmpty) return false;

    final builtInExists = sections.any(
          (section) =>
      section.keyName.trim().toLowerCase() == normalized ||
          section.title.trim().toLowerCase() == normalized,
    );
    if (builtInExists) return true;

    if (normalized == 'custom') return true;
    if (normalized == 'screenshot') return true;

    for (final dir in _customDirs) {
      if (ignorePath != null && dir.path == ignorePath) continue;
      final folderName = p.basename(dir.path).trim().toLowerCase();
      if (folderName == normalized) return true;
    }

    return false;
  }

  Future<void> _createCustomFolder() async {
    if (_busyCustomFolderAction) return;
    await _ensureBaseFolders();

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => NameInputPage(
          title: 'Add Custom Folder',
          hintText: 'Folder name',
          actionLabel: 'Create',
          validator: (value) {
            final raw = value.trim();
            final cleaned = _sanitizeFolderName(raw);

            if (raw.isEmpty) return 'Folder name is required';
            if (cleaned.isEmpty) return 'Folder name is invalid';

            if (_folderNameExists(cleaned)) {
              return 'Folder already exists';
            }

            return null;
          },
        ),
      ),
    );

    if (result == null || result.isEmpty || _customRootDir == null) return;

    final cleaned = _sanitizeFolderName(result);
    if (cleaned.isEmpty) {
      _showSnack('Folder name is invalid.');
      return;
    }

    if (_folderNameExists(cleaned)) {
      _showSnack('Folder already exists.');
      return;
    }

    final newDir = Directory(p.join(_customRootDir!.path, cleaned));

    if (await newDir.exists()) {
      _showSnack('A custom folder with that name already exists.');
      return;
    }

    try {
      if (mounted) {
        setState(() => _busyCustomFolderAction = true);
      }

      await newDir.create(recursive: true);
      await _loadCounts();
      _showSnack('Custom folder created.');
    } catch (e) {
      _showSnack('Failed to create custom folder: $e');
    } finally {
      if (mounted) {
        setState(() => _busyCustomFolderAction = false);
      }
    }
  }

  Future<void> _renameCustomFolder(Directory dir) async {
    final oldName = p.basename(dir.path);

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => NameInputPage(
          title: 'Rename Folder',
          hintText: 'New folder name',
          actionLabel: 'Save',
          initialValue: oldName,
          validator: (value) {
            final raw = value.trim();
            final cleaned = _sanitizeFolderName(raw);

            if (raw.isEmpty) return 'Folder name is required';
            if (cleaned.isEmpty) return 'Folder name is invalid';

            if (_folderNameExists(cleaned, ignorePath: dir.path)) {
              return 'Folder already exists';
            }

            return null;
          },
        ),
      ),
    );

    if (result == null || result.isEmpty) return;

    final cleaned = _sanitizeFolderName(result);
    if (cleaned.isEmpty) return;

    if (cleaned.toLowerCase() == oldName.toLowerCase()) return;

    if (_folderNameExists(cleaned, ignorePath: dir.path)) {
      _showSnack('Folder already exists.');
      return;
    }

    final newDir = Directory(p.join(dir.parent.path, cleaned));

    if (await newDir.exists()) {
      _showSnack('A folder with that name already exists.');
      return;
    }

    try {
      await dir.rename(newDir.path);
      await _loadCounts();
      _showSnack('Folder renamed.');
    } catch (e) {
      _showSnack('Failed to rename folder: $e');
    }
  }

  Future<bool> _folderHasFilesRecursively(Directory dir) async {
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) return true;
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  Future<void> _deleteCustomFolderIfEmpty(Directory dir) async {
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
          title: const Text('Delete Empty Folder'),
          content: Text('Delete "$folderName"? It has no files inside.'),
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
      await dir.delete(recursive: true);
      await _loadCounts();
      _showSnack('Empty folder deleted.');
    } catch (e) {
      _showSnack('Failed to delete folder: $e');
    }
  }

  Future<void> _deleteCustomFolder(Directory dir) async {
    final folderName = p.basename(dir.path);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Folder'),
          content: Text('Delete "$folderName" and all files inside it?'),
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
      await dir.delete(recursive: true);
      await _loadCounts();
      _showSnack('Folder deleted.');
    } catch (e) {
      _showSnack('Failed to delete folder: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  int get _totalFiles =>
      _counts.values.fold<int>(0, (previous, count) => previous + count);

  Future<void> _openSection(CustomerSectionInfo section) async {
    final sectionDir = Directory(p.join(widget.customerDir.path, section.keyName));

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerSectionPage(
          customerName: _customerName,
          section: section,
          sectionDir: sectionDir,
          sourceRootPath: widget.sourceRootPath,
          priorityFolders: widget.priorityFolders,
          onRequestSetSourceRoot: widget.onRequestSetSourceRoot,
        ),
      ),
    );

    await _loadCounts();
  }

  Future<void> _openScreenshotSection() async {
    final screenshotDir = Directory(p.join(widget.customerDir.path, 'screenshot'));

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerSectionPage(
          customerName: _customerName,
          section: const CustomerSectionInfo(
            keyName: 'screenshot',
            title: 'Screenshot',
            icon: Icons.photo_camera_back_outlined,
            color: Color(0xFFE8F5E9),
          ),
          sectionDir: screenshotDir,
          sourceRootPath: widget.sourceRootPath,
          priorityFolders: widget.priorityFolders,
          onRequestSetSourceRoot: widget.onRequestSetSourceRoot,
        ),
      ),
    );

    await _loadCounts();
  }

  Future<void> _openCustomFolder(Directory dir) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerSectionPage(
          customerName: _customerName,
          section: CustomerSectionInfo(
            keyName: 'custom',
            title: p.basename(dir.path),
            icon: Icons.create_new_folder_outlined,
            color: const Color(0xFFFFF4CC),
          ),
          sectionDir: dir,
          sourceRootPath: widget.sourceRootPath,
          priorityFolders: widget.priorityFolders,
          onRequestSetSourceRoot: widget.onRequestSetSourceRoot,
        ),
      ),
    );

    await _loadCounts();
  }

  Widget _buildSectionCard(CustomerSectionInfo section, int count) {
    return _FolderCard(
      title: section.title,
      count: count,
      icon: section.icon,
      iconColor: const Color(0xFF2F6FD6),
      iconBg: section.color,
      borderColor: const Color(0xFFD7DFEA),
      onTap: () => _openSection(section),
    );
  }

  Widget _buildScreenshotCard() {
    final count = _counts['screenshot'] ?? 0;

    return _FolderCard(
      title: 'Screenshot',
      count: count,
      icon: Icons.photo_camera_back_outlined,
      iconColor: const Color(0xFF2F6FD6),
      iconBg: const Color(0xFFE8F5E9),
      borderColor: const Color(0xFFD7DFEA),
      onTap: _openScreenshotSection,
    );
  }

  Widget _buildCustomCard(Directory dir, int count) {
    final name = p.basename(dir.path);

    return _FolderCard(
      title: name,
      count: count,
      icon: Icons.create_new_folder_outlined,
      iconColor: const Color(0xFFD4A017),
      iconBg: const Color(0xFFFFF4CC),
      borderColor: const Color(0xFFE8DFC3),
      onTap: () => _openCustomFolder(dir),
      menuBuilder: () => PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'rename') {
            await _renameCustomFolder(dir);
          } else if (value == 'delete_empty') {
            await _deleteCustomFolderIfEmpty(dir);
          } else if (value == 'delete') {
            await _deleteCustomFolder(dir);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'rename',
            child: Text('Rename'),
          ),
          PopupMenuItem(
            value: 'delete_empty',
            child: Text('Delete Empty Folder'),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text('Delete'),
          ),
        ],
        icon: const Icon(
          Icons.more_vert,
          size: 18,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _buildAddFolderCard() {
    return _FolderCard(
      title: 'Add Folder',
      subtitle: 'Create custom folder',
      count: null,
      icon: Icons.add,
      iconColor: const Color(0xFF2F6FD6),
      iconBg: const Color(0xFFDCEBFF),
      borderColor: const Color(0xFFD7DFEA),
      onTap: _busyCustomFolderAction ? null : _createCustomFolder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width > 1000 ? 4 : width > 700 ? 3 : 2;
    final childAspectRatio = width > 1000 ? 1.28 : width > 700 ? 1.18 : 1.00;

    final builtInCardsCount = sections.length + 1; // + screenshot
    final totalCards = builtInCardsCount + _customDirs.length + 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _customerName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Add Folder',
            onPressed: _busyCustomFolderAction ? null : _createCustomFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshing ? null : _loadCounts,
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
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
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.folder_open,
                        color: Color(0xFF2F6FD6),
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Document categories',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${builtInCardsCount + _customDirs.length} folders • $_totalFiles file${_totalFiles == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 90),
                child: GridView.builder(
                  itemCount: totalCards,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: childAspectRatio,
                  ),
                  itemBuilder: (context, index) {
                    if (index < sections.length) {
                      final section = sections[index];
                      final count = _counts[section.keyName] ?? 0;
                      return _buildSectionCard(section, count);
                    }

                    if (index == sections.length) {
                      return _buildScreenshotCard();
                    }

                    final customStart = sections.length + 1;
                    final customEnd = customStart + _customDirs.length;

                    if (index < customEnd) {
                      final dir = _customDirs[index - customStart];
                      final count = _counts[dir.path] ?? 0;
                      return _buildCustomCard(dir, count);
                    }

                    return _buildAddFolderCard();
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

class _FolderCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int? count;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color borderColor;
  final VoidCallback? onTap;
  final Widget Function()? menuBuilder;

  const _FolderCard({
    required this.title,
    this.subtitle,
    required this.count,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.borderColor,
    required this.onTap,
    this.menuBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final line2 = subtitle ?? '${count ?? 0} file${count == 1 ? '' : 's'}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      height: 1.1,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    line2,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              if (menuBuilder != null)
                Positioned(
                  top: -6,
                  right: -8,
                  child: menuBuilder!(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerSectionInfo {
  final String keyName;
  final String title;
  final IconData icon;
  final Color color;

  const CustomerSectionInfo({
    required this.keyName,
    required this.title,
    required this.icon,
    required this.color,
  });
}