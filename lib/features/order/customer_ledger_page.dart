import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

class CustomerLedgerPage extends StatefulWidget {
  final String customerName;
  final Directory customerDir;

  const CustomerLedgerPage({
    super.key,
    required this.customerName,
    required this.customerDir,
  });

  @override
  State<CustomerLedgerPage> createState() => _CustomerLedgerPageState();
}

class _CustomerLedgerPageState extends State<CustomerLedgerPage> {
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  );

  bool _loading = true;
  List<_LedgerEntry> _entries = [];

  Directory get _ordersDir => Directory(p.join(widget.customerDir.path, 'orders'));

  @override
  void initState() {
    super.initState();
    _loadLedger();
  }

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

  String _peso(double value) => _currencyFormat.format(value);

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
        String date = '';
        if (oldCollectedAt.isNotEmpty) {
          final parsed = DateTime.tryParse(oldCollectedAt);
          if (parsed != null) {
            date = parsed.toIso8601String().split('T').first;
          }
        }
        if (date.isEmpty) {
          date = DateTime.now().toIso8601String().split('T').first;
        }

        payments.add(
          _PaymentEntry(
            date: date,
            amount: oldAmountPaid,
            reference: '',
          ),
        );
      }
    }

    payments.sort((a, b) => a.date.compareTo(b.date));
    return payments;
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso.isEmpty ? '--' : iso;
    return '${dt.month}/${dt.day}/${dt.year.toString().substring(2)}';
  }

  String _statusFromValues(double totalOrder, double totalPaid) {
    final balance = totalOrder - totalPaid;
    if (totalOrder <= 0) return 'UNPAID';
    if (balance < 0) return 'OVERPAID';
    if (balance == 0) return 'PAID';
    if (totalPaid > 0) return 'PARTIAL';
    return 'UNPAID';
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

  Future<void> _loadLedger() async {
    if (!mounted) return;

    setState(() => _loading = true);

    final rawEntries = <Map<String, dynamic>>[];

    try {
      if (!await _ordersDir.exists()) {
        await _ordersDir.create(recursive: true);
      }

      await for (final entity in _ordersDir.list(followLinks: false)) {
        if (entity is! File) continue;
        if (p.extension(entity.path).toLowerCase() != '.json') continue;

        try {
          final raw = await entity.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is! Map<String, dynamic>) continue;

          final orderNo = (decoded['orderNo'] ?? '').toString().trim();
          if (orderNo.isEmpty) continue;

          final dateIso = (decoded['dateIso'] ?? '').toString().trim();

          double finalTotal = _toDouble(decoded['finalTotal']);
          if (finalTotal <= 0) {
            final itemsRaw = decoded['items'];
            if (itemsRaw is List) {
              finalTotal = _computeFinalTotalFromItems(itemsRaw);
            }
          }

          final payments = _parsePayments(decoded);
          final totalPaid =
          payments.fold(0.0, (sum, item) => sum + item.amount);

          double balance = finalTotal - totalPaid;
          double overpayment = 0.0;

          if (balance < 0) {
            overpayment = balance.abs();
            balance = 0.0;
          }

          final storedOverpayment = _toDouble(decoded['overpayment']);
          if (storedOverpayment > 0) {
            overpayment = storedOverpayment;
          }

          rawEntries.add({
            'orderNo': orderNo,
            'dateIso': dateIso,
            'totalOrder': finalTotal,
            'totalPaid': totalPaid,
            'balance': balance,
            'overpayment': overpayment,
            'payments': payments,
            'status': _statusFromValues(finalTotal, totalPaid),
            'jsonFile': entity,
          });
        } catch (_) {}
      }

      rawEntries.sort((a, b) {
        final aDate = DateTime.tryParse((a['dateIso'] ?? '').toString());
        final bDate = DateTime.tryParse((b['dateIso'] ?? '').toString());

        if (aDate != null && bDate != null) {
          return aDate.compareTo(bDate);
        }
        if (aDate != null) return -1;
        if (bDate != null) return 1;
        return (a['orderNo'] ?? '')
            .toString()
            .compareTo((b['orderNo'] ?? '').toString());
      });

      final entries = <_LedgerEntry>[];
      double runningBalance = 0.0;

      for (final row in rawEntries) {
        final totalOrder = (row['totalOrder'] as num).toDouble();
        final totalPaid = (row['totalPaid'] as num).toDouble();

        runningBalance = runningBalance + totalOrder - totalPaid;

        entries.add(
          _LedgerEntry(
            orderNo: row['orderNo'] as String,
            dateIso: row['dateIso'] as String,
            totalOrder: totalOrder,
            totalPaid: totalPaid,
            balance: (row['balance'] as num).toDouble(),
            overpayment: (row['overpayment'] as num).toDouble(),
            runningBalance: runningBalance,
            payments: row['payments'] as List<_PaymentEntry>,
            status: row['status'] as String,
            jsonFile: row['jsonFile'] as File,
          ),
        );
      }

      entries.sort((a, b) {
        final aDate = DateTime.tryParse(a.dateIso);
        final bDate = DateTime.tryParse(b.dateIso);

        if (aDate != null && bDate != null) {
          return bDate.compareTo(aDate);
        }
        if (aDate != null) return -1;
        if (bDate != null) return 1;
        return b.orderNo.compareTo(a.orderNo);
      });

      if (!mounted) return;
      setState(() {
        _entries = entries;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load ledger: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _showPaymentHistory(_LedgerEntry entry) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(entry.orderNo),
        content: SizedBox(
          width: 340,
          child: entry.payments.isEmpty
              ? const Text('No payment entries yet.')
              : ListView.separated(
            shrinkWrap: true,
            itemCount: entry.payments.length,
            separatorBuilder: (_, __) => const Divider(height: 14),
            itemBuilder: (context, index) {
              final item = entry.payments[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatDate(item.date),
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
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Ref: ${item.reference}',
                        style: const TextStyle(
                          fontSize: 11,
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

  Widget _buildLedgerTable() {
    if (_entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, size: 62, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No ledger entries yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD7DFEA)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              const Color(0xFFF3F6FB),
            ),
            dataRowMinHeight: 52,
            dataRowMaxHeight: 72,
            columnSpacing: 18,
            columns: const [
              DataColumn(
                label: Text(
                  '#',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              DataColumn(
                label: Text(
                  'Order',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              DataColumn(
                label: Text(
                  'Date',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              DataColumn(
                numeric: true,
                label: Text(
                  'Amount',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              DataColumn(
                numeric: true,
                label: Text(
                  'Payment',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              DataColumn(
                numeric: true,
                label: Text(
                  'Balance',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              DataColumn(
                numeric: true,
                label: Text(
                  'Running Balance',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              DataColumn(
                label: Text(
                  'Status',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
            rows: List.generate(_entries.length, (index) {
              final entry = _entries[index];
              final statusColor = _statusColor(entry.status);

              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      '${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 120,
                      child: Text(
                        entry.orderNo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    onTap: () => _showPaymentHistory(entry),
                  ),
                  DataCell(Text(_formatDate(entry.dateIso))),
                  DataCell(
                    Text(
                      _peso(entry.totalOrder),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  DataCell(
                    Text(
                      _peso(entry.totalPaid),
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                  DataCell(
                    Text(
                      _peso(entry.balance),
                      style: const TextStyle(
                        color: Color(0xFF2F6FD6),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      _peso(entry.runningBalance),
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        entry.status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                    onTap: () => _showPaymentHistory(entry),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.customerName} Ledger',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadLedger,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
            : _buildLedgerTable(),
      ),
    );
  }
}

class _LedgerEntry {
  final String orderNo;
  final String dateIso;
  final double totalOrder;
  final double totalPaid;
  final double balance;
  final double overpayment;
  final double runningBalance;
  final List<_PaymentEntry> payments;
  final String status;
  final File jsonFile;

  const _LedgerEntry({
    required this.orderNo,
    required this.dateIso,
    required this.totalOrder,
    required this.totalPaid,
    required this.balance,
    required this.overpayment,
    required this.runningBalance,
    required this.payments,
    required this.status,
    required this.jsonFile,
  });
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