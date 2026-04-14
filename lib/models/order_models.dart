import 'dart:convert';

class OrderItem {
  final String category;
  final String brand;
  final String generic;
  final String formulation;
  final String packing;
  final String uom;
  final double unitPrice;
  final int qty;
  final int freeQty;
  final double discountPercent;
  final double directDiscountPercent;

  const OrderItem({
    required this.category,
    required this.brand,
    required this.generic,
    required this.formulation,
    required this.packing,
    this.uom = '',
    required this.unitPrice,
    required this.qty,
    required this.freeQty,
    required this.discountPercent,
    required this.directDiscountPercent,
  });

  bool get hasFreeGoods => freeQty > 0;
  bool get hasDiscount => discountPercent > 0;
  bool get hasDirectDiscount => directDiscountPercent > 0;

  int get totalQty => qty + freeQty;

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

  double get adjustedUnitPrice {
    if (hasDirectDiscount) {
      return unitPrice * (1 - (directDiscountPercent / 100));
    }
    return unitPrice;
  }

  double get grossAmount => qty * adjustedUnitPrice;

  double get discountAmount {
    if (!hasDiscount) return 0;
    return grossAmount * (discountPercent / 100);
  }

  double get directDiscountAmount {
    if (!hasDirectDiscount) return 0;
    return (unitPrice - adjustedUnitPrice) * qty;
  }

  double get netAmount => grossAmount - discountAmount;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      category: (json['category'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      generic: (json['generic'] ?? '').toString(),
      formulation: (json['formulation'] ?? '').toString(),
      packing: (json['packing'] ?? '').toString(),
      uom: (json['uom'] ?? '').toString(),
      unitPrice: (json['unitPrice'] is num)
          ? (json['unitPrice'] as num).toDouble()
          : double.tryParse('${json['unitPrice']}') ?? 0,
      qty: (json['qty'] is num)
          ? (json['qty'] as num).toInt()
          : int.tryParse('${json['qty']}') ?? 0,
      freeQty: (json['freeQty'] is num)
          ? (json['freeQty'] as num).toInt()
          : int.tryParse('${json['freeQty']}') ?? 0,
      discountPercent: (json['discountPercent'] is num)
          ? (json['discountPercent'] as num).toDouble()
          : double.tryParse('${json['discountPercent']}') ?? 0,
      directDiscountPercent: (json['directDiscountPercent'] is num)
          ? (json['directDiscountPercent'] as num).toDouble()
          : double.tryParse('${json['directDiscountPercent']}') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'brand': brand,
      'generic': generic,
      'formulation': formulation,
      'packing': packing,
      'uom': uom,
      'packWithUom': packWithUom,
      'uomLabelUpper': uomLabelUpper,
      'unitPrice': unitPrice,
      'adjustedUnitPrice': adjustedUnitPrice,
      'qty': qty,
      'freeQty': freeQty,
      'totalQty': totalQty,
      'discountPercent': discountPercent,
      'directDiscountPercent': directDiscountPercent,
      'grossAmount': grossAmount,
      'discountAmount': discountAmount,
      'directDiscountAmount': directDiscountAmount,
      'netAmount': netAmount,
    };
  }
}

class CustomerOrder {
  final String orderNo;
  final String customerName;
  final String dateIso;
  final String medrep;
  final String area;
  final String collection;
  final String freeGoods;
  final String headerNote;
  final double discountPercent;
  final double directDiscountPercent;
  final List<OrderItem> items;

  const CustomerOrder({
    required this.orderNo,
    required this.customerName,
    required this.dateIso,
    required this.medrep,
    required this.area,
    required this.collection,
    required this.freeGoods,
    required this.headerNote,
    required this.discountPercent,
    required this.directDiscountPercent,
    required this.items,
  });

  int get totalPaidQty => items.fold(0, (sum, item) => sum + item.qty);

  int get totalFreeQty => items.fold(0, (sum, item) => sum + item.freeQty);

  int get totalOverallQty => items.fold(0, (sum, item) => sum + item.totalQty);

  double get grossTotal => items.fold(0, (sum, item) => sum + item.grossAmount);

  double get itemDiscountTotal =>
      items.fold(0, (sum, item) => sum + item.discountAmount);

  double get itemDirectDiscountTotal =>
      items.fold(0, (sum, item) => sum + item.directDiscountAmount);

  double get subtotalAfterItemDiscounts =>
      items.fold(0, (sum, item) => sum + item.netAmount);

  double get headerDiscountAmount => 0;

  double get headerDirectDiscountAmount => 0;

  double get finalTotal => subtotalAfterItemDiscounts;

  factory CustomerOrder.fromJson(Map<String, dynamic> json) {
    return CustomerOrder(
      orderNo: (json['orderNo'] ?? '').toString(),
      customerName: (json['customerName'] ?? '').toString(),
      dateIso: (json['dateIso'] ?? '').toString(),
      medrep: (json['medrep'] ?? '').toString(),
      area: (json['area'] ?? '').toString(),
      collection: (json['collection'] ?? '').toString(),
      freeGoods: (json['freeGoods'] ?? '').toString(),
      headerNote: (json['headerNote'] ?? '').toString(),
      discountPercent: (json['discountPercent'] is num)
          ? (json['discountPercent'] as num).toDouble()
          : double.tryParse('${json['discountPercent']}') ?? 0,
      directDiscountPercent: (json['directDiscountPercent'] is num)
          ? (json['directDiscountPercent'] as num).toDouble()
          : double.tryParse('${json['directDiscountPercent']}') ?? 0,
      items: (json['items'] as List? ?? [])
          .whereType<Map>()
          .map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'orderNo': orderNo,
      'customerName': customerName,
      'dateIso': dateIso,
      'medrep': medrep,
      'area': area,
      'collection': collection,
      'freeGoods': freeGoods,
      'headerNote': headerNote,
      'discountPercent': discountPercent,
      'directDiscountPercent': directDiscountPercent,
      'totalPaidQty': totalPaidQty,
      'totalFreeQty': totalFreeQty,
      'totalOverallQty': totalOverallQty,
      'grossTotal': grossTotal,
      'itemDiscountTotal': itemDiscountTotal,
      'itemDirectDiscountTotal': itemDirectDiscountTotal,
      'subtotalAfterItemDiscounts': subtotalAfterItemDiscounts,
      'headerDiscountAmount': headerDiscountAmount,
      'headerDirectDiscountAmount': headerDirectDiscountAmount,
      'finalTotal': finalTotal,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }

  String toPrettyJson() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }
}