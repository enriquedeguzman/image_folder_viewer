import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/order_models.dart';

class InvoicePdf {
  static Future<File> generate({
    required CustomerOrder order,
    required Directory saveDir,
  }) async {
    final pdf = pw.Document();

    final fmt = NumberFormat('#,##0.00');

    String money(double v) => fmt.format(v);

    String formatDate(String iso) {
      final dt = DateTime.tryParse(iso);
      if (dt == null) return iso;
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }

    String uomUpper(String value) {
      final v = value.trim();
      return v.isEmpty ? 'UNIT' : v.toUpperCase();
    }

    String packWithUom(String packing, String uom) {
      final pck = packing.trim();
      final unit = uom.trim();
      if (pck.isEmpty && unit.isEmpty) return '';
      if (pck.isEmpty) return unit;
      if (unit.isEmpty) return pck;
      return '$pck $unit';
    }

    String freeGoodsText() {
      final fg = order.freeGoods.trim();
      return fg.isEmpty ? '0' : fg;
    }

    String percentText(double value) {
      if (value <= 0) return '0%';
      if (value == value.roundToDouble()) {
        return '${value.toInt()}%';
      }
      return '${value.toStringAsFixed(2)}%';
    }

    String collectionText() {
      final c = order.collection.trim();
      return c.isEmpty ? '-' : c;
    }

    String headerNoteText() {
      final note = order.headerNote.trim();
      return note.isEmpty ? '-' : note;
    }

    final grossTotal = order.grossTotal;
    final discountAmount = grossTotal * (order.discountPercent / 100);
    final directDiscountBase = grossTotal - discountAmount;
    final directDiscountAmount =
        directDiscountBase * (order.directDiscountPercent / 100);
    final finalTotal = grossTotal - discountAmount - directDiscountAmount;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => [
          pw.Text(
            'SALES ORDER',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),

          pw.Text('Date: ${formatDate(order.dateIso)}'),
          pw.Text('Customer: ${order.customerName}'),
          pw.Text('Area: ${order.area}'),

          pw.SizedBox(height: 6),

          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text('Medrep: ${order.medrep}'),
              ),
              pw.Expanded(
                child: pw.Text(
                  'Collection: ${collectionText()}',
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),

          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text('Free Goods: ${freeGoodsText()}'),
              ),
              pw.Expanded(
                child: pw.Text(
                  'Discount: ${percentText(order.discountPercent)}',
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),

          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text('Header Note: ${headerNoteText()}'),
              ),
              pw.Expanded(
                child: pw.Text(
                  'Direct Discount: ${percentText(order.directDiscountPercent)}',
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 6),
          pw.Divider(),

          pw.Text(
            'Order Summary',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),

          pw.SizedBox(height: 4),

          ...order.items.map((e) {
            final qtyText =
            e.freeQty > 0 ? '${e.qty}+${e.freeQty}' : '${e.qty}';

            final packDisplay = packWithUom(e.packing, e.uom);

            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      '$qtyText ${uomUpper(e.uom)} ${e.brand} ${e.formulation} $packDisplay @${money(e.unitPrice)}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.SizedBox(
                    width: 80,
                    child: pw.Text(
                      money(e.unitPrice * e.qty),
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            );
          }),

          pw.SizedBox(height: 6),
          pw.Divider(),

          pw.Row(
            children: [
              pw.Expanded(child: pw.Text('Gross')),
              pw.SizedBox(
                width: 90,
                child: pw.Text(
                  money(grossTotal),
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),

          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text('Discount (${percentText(order.discountPercent)})'),
              ),
              pw.SizedBox(
                width: 90,
                child: pw.Text(
                  '- ${money(discountAmount)}',
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),

          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Direct Discount (${percentText(order.directDiscountPercent)})',
                ),
              ),
              pw.SizedBox(
                width: 90,
                child: pw.Text(
                  '- ${money(directDiscountAmount)}',
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),

          pw.Divider(),

          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'FINAL TOTAL',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(
                width: 90,
                child: pw.Text(
                  money(finalTotal),
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final file = File(
      p.join(saveDir.path, '${order.orderNo}_${order.customerName}.pdf'),
    );

    await file.writeAsBytes(await pdf.save());
    return file;
  }
}