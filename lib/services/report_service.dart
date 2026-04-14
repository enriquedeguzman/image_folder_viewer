import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/order_models.dart';

class DailySalesPoint {
  final DateTime date;
  final double total;

  DailySalesPoint({
    required this.date,
    required this.total,
  });
}

class TopCustomerStat {
  final String customerName;
  final double totalSales;
  final int orderCount;

  TopCustomerStat({
    required this.customerName,
    required this.totalSales,
    required this.orderCount,
  });
}

class TopProductStat {
  final String brand;
  final double totalSales;
  final int paidQty;
  final int freeQty;
  final int orderCount;

  TopProductStat({
    required this.brand,
    required this.totalSales,
    required this.paidQty,
    required this.freeQty,
    required this.orderCount,
  });
}

class DashboardAnalytics {
  final List<CustomerOrder> allOrders;
  final List<CustomerOrder> weekOrders;
  final List<CustomerOrder> monthOrders;
  final List<CustomerOrder> yearOrders;
  final List<DailySalesPoint> dailyTrend;
  final TopCustomerStat? topCustomer;
  final TopProductStat? topProduct;

  DashboardAnalytics({
    required this.allOrders,
    required this.weekOrders,
    required this.monthOrders,
    required this.yearOrders,
    required this.dailyTrend,
    required this.topCustomer,
    required this.topProduct,
  });
}

class ReportService {
  static Future<List<CustomerOrder>> loadAllOrders() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final customersDir = Directory(p.join(docsDir.path, 'customers'));

    if (!customersDir.existsSync()) return [];

    final orders = <CustomerOrder>[];

    for (final customerDir in customersDir.listSync().whereType<Directory>()) {
      final ordersDir = Directory(p.join(customerDir.path, 'orders'));
      if (!ordersDir.existsSync()) continue;

      for (final file in ordersDir.listSync().whereType<File>()) {
        if (!file.path.toLowerCase().endsWith('.json')) continue;

        try {
          final jsonMap = json.decode(await file.readAsString());
          orders.add(CustomerOrder.fromJson(jsonMap));
        } catch (_) {}
      }
    }

    orders.sort((a, b) {
      final ad = DateTime.tryParse(a.dateIso) ?? DateTime(2000);
      final bd = DateTime.tryParse(b.dateIso) ?? DateTime(2000);
      return bd.compareTo(ad);
    });

    return orders;
  }

  static double sum(List<CustomerOrder> orders) {
    return orders.fold(0.0, (sum, order) => sum + order.finalTotal);
  }

  static List<CustomerOrder> thisWeek(List<CustomerOrder> orders) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));

    return orders.where((order) {
      final d = DateTime.tryParse(order.dateIso);
      if (d == null) return false;
      final date = DateTime(d.year, d.month, d.day);
      return !date.isBefore(startOfWeek) && date.isBefore(endOfWeek);
    }).toList();
  }

  static List<CustomerOrder> thisMonth(List<CustomerOrder> orders) {
    final now = DateTime.now();
    return orders.where((order) {
      final d = DateTime.tryParse(order.dateIso);
      if (d == null) return false;
      return d.year == now.year && d.month == now.month;
    }).toList();
  }

  static List<CustomerOrder> thisYear(List<CustomerOrder> orders) {
    final now = DateTime.now();
    return orders.where((order) {
      final d = DateTime.tryParse(order.dateIso);
      if (d == null) return false;
      return d.year == now.year;
    }).toList();
  }

  static List<DailySalesPoint> dailySalesTrend(
      List<CustomerOrder> orders, {
        int days = 7,
      }) {
    final now = DateTime.now();
    final start =
    DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));

    final totals = <String, double>{};

    for (int i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      final key = _dateKey(d);
      totals[key] = 0;
    }

    for (final order in orders) {
      final d = DateTime.tryParse(order.dateIso);
      if (d == null) continue;

      final date = DateTime(d.year, d.month, d.day);
      if (date.isBefore(start)) continue;

      final key = _dateKey(date);
      if (totals.containsKey(key)) {
        totals[key] = (totals[key] ?? 0) + order.finalTotal;
      }
    }

    return totals.entries.map((e) {
      final parts = e.key.split('-');
      return DailySalesPoint(
        date: DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        ),
        total: e.value,
      );
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  static TopCustomerStat? topCustomer(List<CustomerOrder> orders) {
    if (orders.isEmpty) return null;

    final totals = <String, double>{};
    final counts = <String, int>{};

    for (final order in orders) {
      final name = order.customerName.trim().isEmpty
          ? 'Unknown Customer'
          : order.customerName.trim();

      totals[name] = (totals[name] ?? 0) + order.finalTotal;
      counts[name] = (counts[name] ?? 0) + 1;
    }

    String? bestName;
    double bestTotal = -1;

    for (final entry in totals.entries) {
      if (entry.value > bestTotal) {
        bestName = entry.key;
        bestTotal = entry.value;
      }
    }

    if (bestName == null) return null;

    return TopCustomerStat(
      customerName: bestName,
      totalSales: bestTotal,
      orderCount: counts[bestName] ?? 0,
    );
  }

  static TopProductStat? topProduct(List<CustomerOrder> orders) {
    if (orders.isEmpty) return null;

    final totals = <String, double>{};
    final paidQty = <String, int>{};
    final freeQty = <String, int>{};
    final counts = <String, int>{};

    for (final order in orders) {
      for (final item in order.items) {
        final brand =
        item.brand.trim().isEmpty ? 'Unknown Product' : item.brand.trim();

        totals[brand] = (totals[brand] ?? 0) + item.netAmount;
        paidQty[brand] = (paidQty[brand] ?? 0) + item.qty;
        freeQty[brand] = (freeQty[brand] ?? 0) + item.freeQty;
        counts[brand] = (counts[brand] ?? 0) + 1;
      }
    }

    String? bestBrand;
    double bestTotal = -1;

    for (final entry in totals.entries) {
      if (entry.value > bestTotal) {
        bestBrand = entry.key;
        bestTotal = entry.value;
      }
    }

    if (bestBrand == null) return null;

    return TopProductStat(
      brand: bestBrand,
      totalSales: bestTotal,
      paidQty: paidQty[bestBrand] ?? 0,
      freeQty: freeQty[bestBrand] ?? 0,
      orderCount: counts[bestBrand] ?? 0,
    );
  }

  static Future<DashboardAnalytics> loadDashboardAnalytics() async {
    final allOrders = await loadAllOrders();
    final weekOrders = thisWeek(allOrders);
    final monthOrders = thisMonth(allOrders);
    final yearOrders = thisYear(allOrders);

    return DashboardAnalytics(
      allOrders: allOrders,
      weekOrders: weekOrders,
      monthOrders: monthOrders,
      yearOrders: yearOrders,
      dailyTrend: dailySalesTrend(allOrders, days: 7),
      topCustomer: topCustomer(allOrders),
      topProduct: topProduct(allOrders),
    );
  }

  static String _dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}